import 'dart:async';

import 'package:flutter/material.dart';

import '../models/report_models.dart';
import '../services/audio_service.dart';
import '../services/hive_storage_service.dart';
import '../services/openai_service.dart';
import '../services/settings_service.dart';
import '../services/voice_command_service.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_unavailable_banner.dart';

/// Voice-driven guided wizard backed by a parsed `TemplateSchema`.
///
/// Flow:
///   0. (Step 0) Pick template — by voice ("use breast template") or tap.
///      If only one template exists, this step is auto-skipped. If the
///      doctor says "next" / "confirm" without picking, the configured
///      default ([defaultTemplateId]) is used.
///   1. (Step 1) Confirm patient ID.
///   2. Walk through the schema's questions one at a time.
///       - For singleSelect / multiSelect, the live transcript is fuzzy-
///         matched against the answer labels.
///       - For free-text, the running transcript becomes the answer (refined
///         by Whisper when the doctor advances).
///       - For integer/decimal, digits/number-words are extracted via
///         `VoiceCommandService.normalizeSpokenId`.
///   3. "next" / Next advances; branching (`triggersQuestionIds`) splices
///      child questions into the queue after the current position.
///      "previous" / Back walks the queue backwards.
///      "skip" / Skip is allowed only on optional (`!required`) questions.
///   4. After the last required question is answered, "save" triggers the
///      LLM compose pass and saves the resulting PathologyReport.
class GuidedReportScreen extends StatefulWidget {
  final List<TemplateDocument> templates;
  final Map<String, TemplateSchema> schemas;
  final String defaultTemplateId;
  final ValueChanged<PathologyReport>? onReportSaved;
  final VoidCallback? onBack;

  const GuidedReportScreen({
    super.key,
    required this.templates,
    required this.schemas,
    required this.defaultTemplateId,
    this.onReportSaved,
    this.onBack,
  });

  @override
  State<GuidedReportScreen> createState() => _GuidedReportScreenState();
}


class _GuidedReportScreenState extends State<GuidedReportScreen>
    with TickerProviderStateMixin {
  final AudioService _audio = AudioService();
  final VoiceCommandService _voice = VoiceCommandService.instance;

  // Step 0 — template selection.
  // `_pickedTemplate` / `_pickedSchema` are null until the doctor (or the
  // auto-pick path for a single-template lab) chooses one.
  TemplateDocument? _pickedTemplate;
  TemplateSchema? _pickedSchema;

  // Patient context
  String _confirmedPatientId = '';
  final TextEditingController _patientIdCtrl = TextEditingController();
  bool _patientIdConfirmed = false;

  // Question queue (flat across sections, in order, with branched children
  // inserted just-in-time when an answer with triggers is picked). Empty
  // until a template is picked.
  List<TemplateQuestion> _queue = const [];
  int _cursor = 0;
  // Section title shown above the question — derived from where the question
  // originally sat in the schema.
  Map<String, String> _questionToSection = const {};

  // Captured answers: questionId -> dynamic (String, List<String>, num).
  final Map<String, dynamic> _answers = <String, dynamic>{};
  // Free-text dictation captured per question (for text type).
  final Map<String, String> _textAnswers = <String, String>{};

  // Live transcript pieces.
  String _liveFinal = '';
  String _livePartial = '';

  // ─── Voice feedback (per question) ─────────────────────────────────────
  // The doctor needs constant, unambiguous feedback about
  //   (a) whether the mic is actively capturing audio right now, and
  //   (b) what the recognizer just heard, and
  //   (c) which answer that mapped to (if any).
  //
  // These three fields back the always-visible feedback panel rendered
  // above the MCQ chips. They reset on every cursor move so each
  // question starts with a clean slate.
  String _lastFinal = '';
  String _lastMatchLabel = '';
  DateTime _lastMatchAt = DateTime.fromMillisecondsSinceEpoch(0);
  // One-shot timer that triggers a rebuild ~4s after a match, to fade the
  // green "→ Picked" chip when the doctor goes silent (no partials = no
  // organic rebuilds).
  Timer? _matchExpiryTimer;

  // ─── MCQ voice safety state ────────────────────────────────────────────
  // The on-device recognizer occasionally delivers a final transcript a
  // beat or two AFTER we've moved to the next question (latency, network
  // hiccups, or chunked finals on macOS/Windows). Without guarding, a
  // late "colon" final from Q1 would fuzzy-match against Q2's "Colon"
  // answer label and silently mis-select.
  //
  // Two guards:
  //   1. Stamp `_questionStartedAt` whenever the cursor moves, and drop
  //      any final transcript that arrives within `_staleGuardWindow`
  //      after that stamp — those are bleed-overs from the previous Q.
  //   2. Track the last accepted final text + timestamp; identical finals
  //      within `_dupWindow` are duplicates the recognizer emitted twice.
  DateTime _questionStartedAt = DateTime.now();
  String _lastAcceptedFinal = '';
  DateTime _lastAcceptedFinalAt =
      DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _staleGuardWindow = Duration(milliseconds: 500);
  static const Duration _dupWindow = Duration(milliseconds: 1500);

  /// Per-question prefix style. Alternating between A/B/C and 1/2/3 across
  /// adjacent questions means a stale final ("two") from a previous numeric
  /// question can't accidentally satisfy the prefix matcher when the
  /// current question is alphabet-prefixed (and vice versa). The value
  /// flips whenever `_cursor` moves.
  bool _useAlphaPrefix(int idx) => idx.isEven;

  // Recording state for the current question (used for text/numeric answers
  // so we can transcribe with Whisper).
  bool _recording = false;
  Duration _recordingDuration = Duration.zero;
  // Question id currently being Whisper-transcribed, so the per-question UI
  // can show a spinner while the API call is in flight.
  String? _transcribingQuestionId;
  // Raw audio captured per question — kept on the saved report so the detail
  // screen's playback panel can replay each clip and the doctor can correct
  // any Whisper mis-hears against the original audio.
  final List<VoiceRecording> _recordings = <VoiceRecording>[];

  String _statusMessage = '';
  bool _composing = false;
  bool _saved = false;
  PathologyReport? _composedReport;

  StreamSubscription<VoiceCommandEvent>? _cmdSub;
  StreamSubscription<TranscriptUpdate>? _transcriptSub;
  StreamSubscription<Duration>? _durationSub;

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _cmdSub = _voice.commands.listen(_handleCommand);
    _transcriptSub = _voice.transcript.listen(_handleTranscript);
    _durationSub = _audio.durationStream.listen((d) {
      if (mounted) setState(() => _recordingDuration = d);
    });
    _voice.start();

    // If only one template is available, auto-pick it — the picker step
    // would just be busywork. Otherwise leave `_pickedTemplate` null so the
    // picker UI renders; the doctor can speak a name OR say "confirm" /
    // "next" to take the configured default ([defaultTemplateId]).
    if (widget.templates.length == 1) {
      _pick(widget.templates.first);
    } else {
      _statusMessage =
          'Pick a template — say its name, tap one, or say "confirm" to use the default.';
    }
  }

  /// Lock in a template choice and prepare the question queue. Idempotent:
  /// callers can re-pick (e.g. tap a different template before patient ID
  /// is confirmed) and we'll rebuild the queue. Once patient ID is
  /// confirmed the picker is hidden, so re-pick can't accidentally clobber
  /// in-progress answers.
  void _pick(TemplateDocument t) {
    final schema = widget.schemas[t.id];
    if (schema == null) return;
    setState(() {
      _pickedTemplate = t;
      _pickedSchema = schema;
      _queue = [];
      _questionToSection = {};
      for (final s in schema.sections) {
        for (final q in s.questions) {
          if (q.parentAnswerId.isEmpty) _queue.add(q);
          _questionToSection[q.id] = s.title;
        }
      }
      _cursor = 0;
      _answers.clear();
      _textAnswers.clear();
      if (_queue.isEmpty) {
        _statusMessage =
            'Template "${t.name}" has no top-level questions. Re-parse it from the Templates screen.';
      } else {
        _statusMessage = widget.templates.length == 1
            ? 'Say or type your patient ID to begin.'
            : '"${t.name}" selected — say or type your patient ID to continue.';
      }
    });
  }

  /// Pick the configured default template. Used when the doctor hits
  /// confirm / next without naming a template.
  void _pickDefault() {
    final fallback = widget.templates.firstWhere(
      (t) => t.id == widget.defaultTemplateId,
      orElse: () => widget.templates.first,
    );
    _pick(fallback);
  }

  @override
  void dispose() {
    _cmdSub?.cancel();
    _transcriptSub?.cancel();
    _durationSub?.cancel();
    _matchExpiryTimer?.cancel();
    _pulse.dispose();
    _audio.dispose();
    _patientIdCtrl.dispose();
    super.dispose();
  }

  TemplateQuestion? get _currentQuestion {
    if (_pickedTemplate == null) return null;
    if (!_patientIdConfirmed) return null;
    if (_queue.isEmpty) return null;
    if (_cursor < 0 || _cursor >= _queue.length) return null;
    return _queue[_cursor];
  }

  bool get _allRequiredAnswered {
    for (final q in _queue) {
      if (!q.required) continue;
      final v = _answers[q.id];
      if (v == null) return false;
      if (v is String && v.trim().isEmpty) return false;
      if (v is List && v.isEmpty) return false;
    }
    return _queue.isNotEmpty;
  }

  // ─── Voice & input handlers ───────────────────────────────────────────

  void _handleTranscript(TranscriptUpdate u) {
    if (!mounted) return;
    setState(() {
      if (u.isFinal) {
        _liveFinal = _liveFinal.isEmpty
            ? u.text
            : '${_liveFinal.trim()} ${u.text.trim()}';
        _livePartial = '';
        // Capture the most recent single utterance separately from the
        // accumulating session transcript — the feedback panel shows
        // "Heard: '<this>'" so the doctor sees, in plain words, exactly
        // what the recognizer just committed.
        _lastFinal = u.text.trim();
      } else {
        _livePartial = u.text;
      }
    });
    if (u.isFinal) {
      // During Step 0 (template picker) try to match the spoken text against
      // a template name so the doctor can say "use breast template" without
      // tapping. Otherwise route to per-question answer matching.
      if (_pickedTemplate == null) {
        _maybeMatchTemplateFromTranscript(u.text);
      } else if (_isAcceptableFinal(u.text)) {
        _maybeMatchAnswerFromTranscript(u.text);
      }
    }
  }

  /// Drop final transcripts that are stale (arrived right after we moved
  /// to the next question) or duplicate (recognizer emitted the same
  /// final twice in quick succession). Either condition would otherwise
  /// produce a wrong selection on the *current* question.
  bool _isAcceptableFinal(String text) {
    final now = DateTime.now();
    if (now.difference(_questionStartedAt) < _staleGuardWindow) {
      return false; // bleed-over from the previous question
    }
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return false;
    if (t == _lastAcceptedFinal &&
        now.difference(_lastAcceptedFinalAt) < _dupWindow) {
      return false; // duplicate emission
    }
    _lastAcceptedFinal = t;
    _lastAcceptedFinalAt = now;
    return true;
  }

  /// Match the spoken text against the available template names. Reuses the
  /// same token-overlap fuzzy matcher used for answer choices, so phrases
  /// like "use the breast template" or "colon resection" match cleanly.
  void _maybeMatchTemplateFromTranscript(String text) {
    if (widget.templates.length <= 1) return;
    final tokens = _tokens(text);
    if (tokens.isEmpty) return;
    TemplateDocument? best;
    double bestScore = 0;
    for (final t in widget.templates) {
      final hay = '${t.name} ${t.label}';
      final lower = hay.toLowerCase();
      // Substring shortcut.
      if (lower.contains(t.name.toLowerCase()) &&
          text.toLowerCase().contains(t.name.toLowerCase())) {
        _pick(t);
        return;
      }
      final tplTokens = _tokens(hay);
      if (tplTokens.isEmpty) continue;
      final inter = tplTokens.where(tokens.contains).length;
      final union = ({...tplTokens, ...tokens}).length;
      final score = union == 0 ? 0.0 : inter / union;
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    if (best != null && bestScore >= 0.4) _pick(best);
  }

  void _maybeMatchAnswerFromTranscript(String text) {
    final q = _currentQuestion;
    if (q == null) return;
    if (q.type == TemplateQuestionType.singleSelect ||
        q.type == TemplateQuestionType.multiSelect) {
      // MCQ is prefix-only by design. The doctor says the option's
      // letter ("A" / "alpha") or number ("one" / "1") — nothing else
      // is accepted. Fuzzy label matching used to live here as a
      // fallback, but it was the source of two real bugs:
      //   1. A stale final from the previous question whose answer
      //      label happened to overlap with a current option's label
      //      would silently select the wrong option.
      //   2. Free-form dictation in earlier sentences that contained
      //      a current option's keyword would accidentally match.
      // Prefix-only is fast, local (no API), and unambiguous.
      final byPrefix = _matchAnswerByPrefix(text, q);
      if (byPrefix != null) _selectAnswer(q, byPrefix);
    } else if (q.type == TemplateQuestionType.integer ||
        q.type == TemplateQuestionType.decimal) {
      final n = _extractNumber(text);
      if (n != null) {
        setState(() => _answers[q.id] = n);
      }
    } else if (q.type == TemplateQuestionType.text) {
      // Accumulate the live transcript as the free-text answer.
      // Whisper-refinement (when the doctor uses the Dictate button)
      // runs asynchronously in the background — see
      // `_stopRecordingForCurrent` — so the doctor never has to wait.
      _textAnswers[q.id] = (_textAnswers[q.id] ?? '').isEmpty
          ? text
          : '${_textAnswers[q.id]} $text';
      _answers[q.id] = _textAnswers[q.id];
    }
  }

  /// Match the spoken text against this question's prefix style.
  ///
  /// Each MCQ option is shown with a leading "1." / "2." / "3." OR
  /// "A." / "B." / "C." (alternating per question). The doctor can say
  /// the digit, the number word ("one", "first"), the letter ("A"), or
  /// the NATO call-sign ("alpha"). We only accept matches in the style
  /// the current question is showing — that's why a stale "two" final
  /// from a numeric Q1 won't fire when an alphabet-prefixed Q2 is on
  /// screen. Local, no API.
  TemplateAnswer? _matchAnswerByPrefix(String spoken, TemplateQuestion q) {
    if (q.answers.isEmpty) return null;
    final lower = ' ${spoken.toLowerCase().trim()} ';
    final useAlpha = _useAlphaPrefix(_cursor);
    final dict = useAlpha ? _alphaWordToIndex : _numberWordToIndex;
    int? hitIndex;
    // Scan the dictionary for the LAST occurrence in the transcript so
    // self-corrections like "two — actually three" pick the latest token.
    int latestPos = -1;
    dict.forEach((word, idx) {
      final probe = ' $word ';
      final pos = lower.lastIndexOf(probe);
      if (pos > latestPos) {
        latestPos = pos;
        hitIndex = idx;
      }
    });
    if (hitIndex == null) return null;
    if (hitIndex! < 0 || hitIndex! >= q.answers.length) return null;
    return q.answers[hitIndex!];
  }

  /// Number-word / digit → option index (0-based) for numeric prefix Qs.
  static const Map<String, int> _numberWordToIndex = {
    '1': 0, 'one': 0, 'first': 0,
    '2': 1, 'two': 1, 'second': 1, 'too': 1, 'to': 1,
    '3': 2, 'three': 2, 'third': 2,
    '4': 3, 'four': 3, 'fourth': 3, 'for': 3,
    '5': 4, 'five': 4, 'fifth': 4,
    '6': 5, 'six': 5, 'sixth': 5,
    '7': 6, 'seven': 6, 'seventh': 6,
    '8': 7, 'eight': 7, 'eighth': 7,
    '9': 8, 'nine': 8, 'ninth': 8,
    '10': 9, 'ten': 9, 'tenth': 9,
  };

  /// Letter / NATO call-sign → option index (0-based) for alpha prefix Qs.
  static const Map<String, int> _alphaWordToIndex = {
    'a': 0, 'alpha': 0,
    'b': 1, 'bravo': 1, 'be': 1, 'bee': 1,
    'c': 2, 'charlie': 2, 'see': 2, 'sea': 2,
    'd': 3, 'delta': 3, 'dee': 3,
    'e': 4, 'echo': 4,
    'f': 5, 'foxtrot': 5, 'ef': 5,
    'g': 6, 'golf': 6, 'gee': 6,
    'h': 7, 'hotel': 7, 'aitch': 7,
    'i': 8, 'india': 8, 'eye': 8,
    'j': 9, 'juliet': 9, 'jay': 9,
  };

  Set<String> _tokens(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2 && !_stopwords.contains(t))
        .toSet();
  }

  static const _stopwords = {
    'the', 'a', 'an', 'is', 'and', 'or', 'of', 'with', 'as', 'to', 'in',
    'for', 'on', 'this', 'that', 'it', 'be', 'are', 'i', 'we', 'my',
  };

  num? _extractNumber(String text) {
    // First try direct parse from digits in the text.
    final direct = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(text);
    if (direct != null) {
      return num.tryParse(direct.group(0)!);
    }
    final normalized = VoiceCommandService.normalizeSpokenId(text);
    final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(normalized);
    if (m == null) return null;
    return num.tryParse(m.group(0)!);
  }

  Future<void> _handleCommand(VoiceCommandEvent e) async {
    if (!mounted) return;

    // While the doctor is actively dictating a free-text or numeric
    // answer, every word they say is CONTENT, not a command. Without
    // this guard, dictating a phrase like "the patient was saved" or
    // "stop the bleeding was noted" would fire `save` / `stop` and
    // truncate the recording mid-sentence. Only `stop` (finish
    // dictation) and `cancel`/`discard` (abandon this clip) survive.
    if (_recording) {
      if (e.command == VoiceCommand.stop) {
        await _stopRecordingForCurrent();
      } else if (e.command == VoiceCommand.cancel ||
          e.command == VoiceCommand.discard) {
        // Stop the recorder, drop the captured audio, leave the answer
        // empty so the doctor can re-record.
        await _audio.stopRecording();
        setState(() {
          _recording = false;
          _liveFinal = '';
          _livePartial = '';
          _statusMessage = 'Recording discarded — tap Dictate to retry.';
        });
      }
      return;
    }

    // Stale-guard for navigation commands. If the doctor just advanced
    // to a new question, drop any `next`/`previous`/`skip` that arrives
    // within the same window we use to drop stale answer transcripts —
    // it's almost always a delayed duplicate of the command that moved
    // us here, not a deliberate second advance.
    if (e.command == VoiceCommand.next ||
        e.command == VoiceCommand.previous ||
        e.command == VoiceCommand.skip) {
      if (DateTime.now().difference(_questionStartedAt) <
          _staleGuardWindow) {
        return;
      }
    }

    if (e.command == VoiceCommand.back ||
        e.command == VoiceCommand.dashboard) {
      widget.onBack?.call();
      return;
    }

    // Step 0 — picker: confirm/next without naming a template falls back
    // to the configured default. (Naming a template is handled by the
    // transcript matcher, not as a discrete command.)
    if (_pickedTemplate == null) {
      if (e.command == VoiceCommand.confirm ||
          e.command == VoiceCommand.next) {
        _pickDefault();
      }
      return;
    }

    if (!_patientIdConfirmed) {
      if (e.command == VoiceCommand.patientId && e.payload.isNotEmpty) {
        _patientIdCtrl.text = e.payload;
        setState(() {
          _statusMessage =
              'Patient ID: ${e.payload} — say "confirm" or tap the check.';
        });
      } else if (e.command == VoiceCommand.confirm &&
          _patientIdCtrl.text.trim().isNotEmpty) {
        _confirmPatientId(_patientIdCtrl.text);
      }
      return;
    }

    switch (e.command) {
      case VoiceCommand.next:
        await _advance();
        break;
      case VoiceCommand.previous:
        _retreat();
        break;
      case VoiceCommand.skip:
        await _skip();
        break;
      case VoiceCommand.start:
        if (!_recording) await _startRecordingForCurrent();
        break;
      case VoiceCommand.stop:
        if (_recording) await _stopRecordingForCurrent();
        break;
      case VoiceCommand.confirm:
        await _advance();
        break;
      case VoiceCommand.cancel:
      case VoiceCommand.discard:
        _clearCurrentAnswer();
        break;
      case VoiceCommand.save:
        if (_allRequiredAnswered) await _composeAndSave();
        break;
      case VoiceCommand.generate:
        if (_allRequiredAnswered) await _composeAndSave();
        break;
      default:
        break;
    }
  }

  void _confirmPatientId(String raw) {
    final id = raw.trim().toUpperCase();
    if (id.isEmpty) return;
    setState(() {
      _confirmedPatientId = id;
      _patientIdConfirmed = true;
      _questionStartedAt = DateTime.now();
      _lastAcceptedFinal = '';
      _statusMessage = _queue.isEmpty
          ? 'Template has no questions to answer.'
          : 'Question 1 of ${_queue.length} — answer with voice or tap.';
    });
  }

  void _selectAnswer(TemplateQuestion q, TemplateAnswer a) {
    setState(() {
      if (q.type == TemplateQuestionType.multiSelect) {
        final list = List<String>.from(_answers[q.id] as List? ?? <String>[]);
        if (!list.contains(a.label)) list.add(a.label);
        _answers[q.id] = list;
      } else {
        _answers[q.id] = a.label;
      }
      // Surface the match in the feedback panel so the doctor sees the
      // explicit "→ picked B. Colon" confirmation. Without this, voice
      // selection is invisible — the chip just lights up and the
      // doctor has to scan to verify.
      _lastMatchLabel = a.label;
      _lastMatchAt = DateTime.now();
      _maybeReshapeQueue(q, a);
    });
    // Schedule a rebuild so the green chip fades on its own even if no
    // partials arrive in the meantime. Re-arms on every match so rapid
    // multi-select picks each get their own 4s window.
    _matchExpiryTimer?.cancel();
    _matchExpiryTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() {});
    });
  }

  /// When an answer with `triggersQuestionIds` is picked, splice the child
  /// questions into the queue right after the current position. Conversely,
  /// if an answer that previously triggered children is replaced (single-
  /// select), drop those children from the queue (and their answers) so the
  /// wizard reflects the new branch.
  void _maybeReshapeQueue(TemplateQuestion q, TemplateAnswer picked) {
    final allQs = _pickedSchema!.allQuestions;

    // For single-select, remove children of *other* answers of this question
    // first (since picking a new answer invalidates the old branch).
    if (q.type == TemplateQuestionType.singleSelect) {
      for (final other in q.answers) {
        if (other.id == picked.id) continue;
        for (final cid in other.triggersQuestionIds) {
          _removeFromQueue(cid);
        }
      }
    }

    // Splice in the picked answer's triggered children at the current cursor + 1.
    if (picked.triggersQuestionIds.isNotEmpty) {
      var insertAt = _cursor + 1;
      for (final cid in picked.triggersQuestionIds) {
        if (_queue.any((qq) => qq.id == cid)) continue; // already there
        final child = allQs.firstWhere(
          (qq) => qq.id == cid,
          orElse: () => TemplateQuestion(id: '', label: ''),
        );
        if (child.id.isEmpty) continue;
        _queue.insert(insertAt, child);
        insertAt++;
      }
    }
  }

  void _removeFromQueue(String questionId) {
    final idx = _queue.indexWhere((q) => q.id == questionId);
    if (idx == -1) return;
    final removed = _queue[idx];
    _queue.removeAt(idx);
    _answers.remove(removed.id);
    _textAnswers.remove(removed.id);
    if (idx <= _cursor && _cursor > 0) _cursor -= 1;
    // Recursively prune children of this removed question that we previously
    // spliced in.
    for (final a in removed.answers) {
      for (final cid in a.triggersQuestionIds) {
        _removeFromQueue(cid);
      }
    }
  }

  Future<void> _advance() async {
    if (_recording) await _stopRecordingForCurrent();
    final q = _currentQuestion;
    if (q == null) return;
    // Required-check guard.
    if (q.required) {
      final v = _answers[q.id];
      final missing = v == null ||
          (v is String && v.trim().isEmpty) ||
          (v is List && v.isEmpty);
      if (missing) {
        _setStatus('"${q.label}" is required — answer or say "skip".');
        return;
      }
    }
    if (_cursor < _queue.length - 1) {
      setState(() {
        _cursor += 1;
        _liveFinal = '';
        _livePartial = '';
        _lastFinal = '';
        _lastMatchLabel = '';
        _questionStartedAt = DateTime.now();
        _lastAcceptedFinal = '';
        _statusMessage =
            'Question ${_cursor + 1} of ${_queue.length} — answer with voice or tap.';
      });
    } else {
      _setStatus('All questions answered. Say "save" to compose the report.');
    }
  }

  void _retreat() {
    if (_cursor == 0) return;
    setState(() {
      _cursor -= 1;
      _liveFinal = '';
      _livePartial = '';
      _lastFinal = '';
      _lastMatchLabel = '';
      _questionStartedAt = DateTime.now();
      _lastAcceptedFinal = '';
      _statusMessage =
          'Question ${_cursor + 1} of ${_queue.length}.';
    });
  }

  Future<void> _skip() async {
    final q = _currentQuestion;
    if (q == null) return;
    if (q.required) {
      _setStatus('Cannot skip a required question.');
      return;
    }
    _answers.remove(q.id);
    await _advance();
  }

  void _clearCurrentAnswer() {
    final q = _currentQuestion;
    if (q == null) return;
    setState(() {
      _answers.remove(q.id);
      _textAnswers.remove(q.id);
      _liveFinal = '';
      _livePartial = '';
    });
  }

  // ─── Per-question recording (text/numeric) ─────────────────────────────

  Future<void> _startRecordingForCurrent() async {
    final q = _currentQuestion;
    if (q == null) return;
    if (!await _audio.hasPermission()) {
      _setStatus('Microphone permission denied.');
      return;
    }
    final path = await _audio.startRecording();
    if (path == null) {
      _setStatus('Could not start recording.');
      return;
    }
    setState(() {
      _recording = true;
      _recordingDuration = Duration.zero;
      _liveFinal = '';
      _livePartial = '';
      _statusMessage = 'Recording — say your answer, then "stop" or "next".';
    });
  }

  Future<void> _stopRecordingForCurrent() async {
    if (!_recording) return;
    final q = _currentQuestion;
    // Snapshot what the on-device recognizer captured *before* we stop, so a
    // Whisper failure still leaves a usable transcript on the saved clip.
    final liveSeed = '${_liveFinal.trim()} ${_livePartial.trim()}'.trim();
    final clipDuration = _recordingDuration;
    final path = await _audio.stopRecording();
    setState(() => _recording = false);
    if (path == null || q == null) return;

    // Persist the raw clip immediately — the detail screen's playback panel
    // pulls from this list, and we want the file kept even if Whisper errors
    // or the user backs out. Seed the clip's transcription with the on-device
    // STT result so the report has a usable transcript even before any
    // background Whisper refinement returns.
    final rec = VoiceRecording(
      filePath: path,
      duration: clipDuration,
      label: q.label,
      transcription: liveSeed,
    );
    setState(() => _recordings.add(rec));

    // ─── Apply the live transcript IMMEDIATELY ─────────────────────────
    // The doctor should never wait on a network round-trip to move on.
    // We commit the on-device STT result as the answer right now; if a
    // background Whisper refinement arrives later, it silently upgrades
    // the stored clip transcription (and, for free-text answers only,
    // the displayed answer — but only if the doctor hasn't edited it).
    bool needsWhisper = false;
    switch (q.type) {
      case TemplateQuestionType.singleSelect:
      case TemplateQuestionType.multiSelect:
        // MCQ is alphabet-/numeric-only by design — no Whisper, no API
        // call. The doctor said "A" or "two"; the local prefix matcher
        // already chose the option from the live partials. If the live
        // seed (final) re-confirms a match, apply it; otherwise leave
        // whatever was selected during partials in place.
        final matched = _matchAnswerByPrefix(liveSeed, q);
        if (matched != null) _selectAnswer(q, matched);
        _setStatus(_answers[q.id] == null
            ? 'Say "A", "B"… or "one", "two"… to pick an option.'
            : 'Answer captured.');
        break;

      case TemplateQuestionType.integer:
      case TemplateQuestionType.decimal:
        // Digits and number-words transcribe reliably on-device. Try
        // parsing the live seed first — if we get a number, we're done
        // (no Whisper). Only fall back to Whisper when the doctor
        // dictated something the local parser couldn't read.
        final n = _extractNumber(liveSeed);
        if (n != null) {
          setState(() {
            _answers[q.id] = n;
            _statusMessage = 'Answer captured.';
          });
        } else {
          needsWhisper = true;
          setState(() => _statusMessage =
              'Refining number from audio · you can move on.');
        }
        break;

      case TemplateQuestionType.text:
        // Free-form comments — apply the live seed as the answer right
        // now so the doctor can advance, then call Whisper in the
        // background to upgrade transcription quality. This is the
        // ONLY place we still use Whisper.
        if (liveSeed.isNotEmpty) {
          setState(() {
            _textAnswers[q.id] = liveSeed;
            _answers[q.id] = liveSeed;
            _statusMessage =
                'Answer captured · refining transcript in background.';
          });
        }
        needsWhisper = true;
        break;

      case TemplateQuestionType.date:
        // Dates are picked via the date-picker, never Whisper-routed.
        break;
    }

    if (needsWhisper) {
      _refineWithWhisperInBackground(rec, q, path, liveSeed);
    }
  }

  /// Run Whisper transcription as a background task. Never blocks the UI.
  ///
  /// When it returns:
  ///   - The stored clip's transcription is upgraded to the Whisper text
  ///     (so the Detail screen and the composed report use the higher-
  ///     accuracy version).
  ///   - For free-text questions, if the doctor hasn't manually edited
  ///     the answer since we applied the live seed, the answer field is
  ///     also upgraded to the Whisper text.
  ///   - For numeric questions, if the answer is still empty (i.e. the
  ///     live seed couldn't be parsed), we try to extract a number from
  ///     the Whisper text and apply it.
  ///
  /// If the doctor advanced past this question, has answered something
  /// else, or has saved the report by the time Whisper returns, the
  /// upgrade is silent — never clobbering doctor input.
  void _refineWithWhisperInBackground(
      VoiceRecording rec, TemplateQuestion q, String path, String liveSeed) {
    setState(() => _transcribingQuestionId = q.id);
    OpenAIService.transcribeAudio(
      path,
      prompt: 'Histopathology answer to: ${q.label}',
    ).then((text) {
      if (!mounted) return;
      final corrected = text.trim();
      if (corrected.isNotEmpty) {
        // Upgrade clip transcription regardless of UI state.
        final idx = _recordings.indexWhere((r) => r.id == rec.id);
        if (idx != -1) {
          _recordings[idx] =
              _recordings[idx].copyWith(transcription: corrected);
        }
        // Conditional answer upgrade — only if the doctor hasn't moved
        // the goalposts since we seeded.
        if (q.type == TemplateQuestionType.text) {
          final current = (_answers[q.id] ?? '').toString();
          if (current == liveSeed || current.isEmpty) {
            setState(() {
              _textAnswers[q.id] = corrected;
              _answers[q.id] = corrected;
            });
          }
        } else if (q.type == TemplateQuestionType.integer ||
            q.type == TemplateQuestionType.decimal) {
          if (_answers[q.id] == null) {
            final n = _extractNumber(corrected);
            if (n != null) setState(() => _answers[q.id] = n);
          }
        }
      }
      if (mounted) setState(() => _transcribingQuestionId = null);
    }).catchError((Object _) {
      // Background refinement is best-effort. If it fails we keep the
      // live seed; nothing to surface to the doctor.
      if (mounted) setState(() => _transcribingQuestionId = null);
    });
  }

  // ─── Compose & save ───────────────────────────────────────────────────

  Future<void> _composeAndSave() async {
    if (_composing) return;
    // If a Whisper call is still in flight, wait it out so its corrected
    // transcript makes it into the saved clip.
    if (_transcribingQuestionId != null) {
      _setStatus('Waiting for transcription to finish…');
      while (_transcribingQuestionId != null && mounted) {
        await Future.delayed(const Duration(milliseconds: 120));
      }
      if (!mounted) return;
    }
    setState(() {
      _composing = true;
      _statusMessage = 'Composing synoptic report…';
    });
    try {
      final labels = <String, String>{};
      for (final q in _pickedSchema!.allQuestions) {
        labels[q.id] = q.label;
      }
      final composed = await OpenAIService.composeSynopticReport(
        answers: _answers,
        questionLabels: labels,
        templateName: _pickedTemplate!.name,
      );
      final reportNumber = HiveStorageService.nextReportNumber();
      final existing = HiveStorageService.getPatient(_confirmedPatientId);
      // Joined per-question dictation — keeps the same shape the free-form
      // voice flow uses, so the detail screen's "generated script" panel has
      // something to fall back to.
      final rawTranscript = _recordings
          .map((r) {
            final t = r.transcription.trim();
            if (t.isEmpty) return '';
            return r.label.isEmpty ? t : '${r.label}: $t';
          })
          .where((s) => s.isNotEmpty)
          .join('\n\n');
      final report = PathologyReport(
        reportNumber: reportNumber,
        patientId: _confirmedPatientId,
        patientName: existing?.name ?? '',
        patientAge: existing?.age ?? 0,
        patientGender: existing?.gender ?? '',
        mrn: _confirmedPatientId,
        labNo: existing?.labNumber ?? '',
        visitNo: existing?.visitNumber ?? '',
        orderedBy: existing?.orderedBy ?? '',
        referredBy: existing?.referringDoctor ?? '',
        clinicalInformation: composed['clinical_information'] ?? '',
        specimen: composed['specimen'] ?? '',
        grossExamination: composed['gross_examination'] ?? '',
        // Synoptic block lives in microscopy_impression so it surfaces in the
        // existing report layout. composeSynopticReport returns it as 'synoptic'.
        microscopyImpression: composed['synoptic'] ?? '',
        // Diagnosis-first headline + pTNM staging — rendered prominently at
        // the top of the report (after Clinical Information).
        diagnosisHeadline: composed['diagnosis_headline'] ?? '',
        pathologicStaging: composed['pathologic_staging'] ?? '',
        summary: composed['summary'] ?? '',
        rawTranscript: rawTranscript,
        voiceRecordings: List.of(_recordings),
        synopticAnswers: Map<String, dynamic>.from(_answers),
        templateId: _pickedTemplate!.id,
        status: ReportStatus.pending,
        reportedDate: DateTime.now(),
        pathologistName: SettingsService.getPathologistName(),
        pathologistRegistration:
            SettingsService.getPathologistRegistration(),
        pathologistName2: SettingsService.getDualSignatureEnabled()
            ? SettingsService.getPathologist2Name()
            : '',
        pathologistRegistration2: SettingsService.getDualSignatureEnabled()
            ? SettingsService.getPathologist2Registration()
            : '',
      );
      await HiveStorageService.saveReport(report);
      widget.onReportSaved?.call(report);
      if (!mounted) return;
      setState(() {
        _composing = false;
        _saved = true;
        _composedReport = report;
        _statusMessage =
            'Saved ${report.reportNumber}${_recordings.isEmpty ? '' : ' · ${_recordings.length} clip(s) attached'}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _composing = false;
        _statusMessage = 'Compose failed — $e. Your answers and recordings are kept; tap "Save report" to retry.';
      });
    }
  }

  void _setStatus(String msg) {
    if (!mounted) return;
    setState(() => _statusMessage = msg);
  }

  // ─── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _topBar(),
          // Persistent voice-unavailability banner. Collapses to nothing
          // when STT is healthy, so it costs zero pixels in the happy
          // path. When voice is down, the doctor sees the reason and a
          // Retry button up here — far more discoverable than the small
          // listening pill in the top-right.
          const VoiceUnavailableBanner(),
          Expanded(
            child: isWide
                ? Row(
                    children: [
                      Expanded(flex: 5, child: _leftPanel()),
                      const VerticalDivider(width: 1),
                      Expanded(flex: 5, child: _rightPanel()),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        _leftPanel(),
                        const Divider(height: 1),
                        _rightPanel(),
                      ],
                    ),
                  ),
          ),
          _commandHints(),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (widget.onBack != null)
            IconButton(
              tooltip: 'Back',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.fact_check_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _pickedTemplate == null
                      ? 'Guided Report — choose a template'
                      : 'Guided Report — ${_pickedTemplate!.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _pickedSchema == null
                      ? '${widget.templates.length} templates available'
                      : '${_pickedSchema!.sections.length} sections · ${_pickedSchema!.totalQuestions} questions · v${_pickedSchema!.version.isEmpty ? "—" : _pickedSchema!.version}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          _listeningPill(),
        ],
      ),
    );
  }

  Widget _listeningPill() {
    return StreamBuilder<String>(
      stream: _voice.status,
      builder: (context, snap) {
        // Three-way state — was two before, but "Idle" was misleading
        // when the recognizer had actually failed to initialise.
        final available = _voice.isAvailable;
        final initialized = _voice.isInitialized;
        final listening = _voice.isListening;

        late final Color color;
        late final String label;
        late final IconData icon;
        bool animate = false;
        if (!initialized) {
          color = AppColors.textHint;
          label = 'Starting…';
          icon = Icons.hourglass_empty_rounded;
        } else if (!available) {
          color = AppColors.warning;
          label = 'Voice off';
          icon = Icons.mic_off_rounded;
        } else if (listening) {
          color = AppColors.success;
          label = 'Listening';
          icon = Icons.graphic_eq_rounded;
          animate = true;
        } else {
          color = AppColors.textHint;
          label = 'Idle';
          icon = Icons.mic_none_rounded;
        }

        return Tooltip(
          message: !available
              ? (_voice.lastError.isEmpty
                  ? 'Speech recognition unavailable on this system'
                  : _voice.lastError)
              : (listening ? 'Listening for voice commands' : 'Mic idle'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) => Transform.scale(
                    scale: animate ? 1 + 0.15 * _pulse.value : 1,
                    child: child,
                  ),
                  child: Icon(icon, size: 11, color: color),
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _leftPanel() {
    if (_pickedTemplate == null) return _templatePickerCard();
    if (!_patientIdConfirmed) return _patientIdCard();
    if (_saved) return _savedCard();
    if (_queue.isEmpty) return _emptyCard();
    return _questionCard();
  }

  Widget _templatePickerCard() {
    final defaultTpl = widget.templates.firstWhere(
      (t) => t.id == widget.defaultTemplateId,
      orElse: () => widget.templates.first,
    );
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: const [
                Icon(Icons.fact_check_outlined,
                    size: 20, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Step 0 — Choose template',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            Text(_statusMessage,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded,
                      size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Default',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: AppColors.textHint)),
                        Text(defaultTpl.name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        if (defaultTpl.label.isNotEmpty)
                          Text(defaultTpl.label,
                              style:
                                  Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _pick(defaultTpl),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Use default'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Or pick another:',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.textHint)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.templates.map((t) {
                final isDefault = t.id == defaultTpl.id;
                return ActionChip(
                  avatar: Icon(
                    isDefault
                        ? Icons.star_rounded
                        : Icons.description_outlined,
                    size: 14,
                    color: isDefault
                        ? AppColors.warning
                        : AppColors.textSecondary,
                  ),
                  label: Text(
                      t.label.isEmpty ? t.name : '${t.name} · ${t.label}',
                      style: const TextStyle(fontSize: 12)),
                  onPressed: () => _pick(t),
                );
              }).toList(),
            ),
            if (_liveFinal.isNotEmpty || _livePartial.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Heard: "${(_liveFinal + ' ' + _livePartial).trim()}"',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _patientIdCard() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.badge_outlined,
                    size: 20, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Step 1 — Patient ID',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            Text(_statusMessage,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _patientIdCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Patient ID / MRN',
                isDense: true,
              ),
              onSubmitted: _confirmPatientId,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _confirmPatientId(_patientIdCtrl.text),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Confirm and start'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_statusMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }

  Widget _savedCard() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.success.withOpacity(0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 48),
            const SizedBox(height: 12),
            Text(_statusMessage,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (_composedReport != null)
              Text(_composedReport!.reportNumber,
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.home_rounded, size: 16),
                  label: const Text('Back to home'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _questionCard() {
    final q = _currentQuestion!;
    final sectionTitle = _questionToSection[q.id] ?? '';
    final answer = _answers[q.id];
    // Optional questions get a subtle visual cue (dashed-style left accent)
    // so the doctor immediately knows the question is safe to skip.
    final accentColor =
        q.required ? AppColors.primary : AppColors.textHint;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            top: const BorderSide(color: AppColors.border),
            right: const BorderSide(color: AppColors.border),
            bottom: const BorderSide(color: AppColors.border),
            left: BorderSide(color: accentColor, width: 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    sectionTitle.isEmpty ? 'Question' : sectionTitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppColors.primary),
                  ),
                ),
                _stepBadge(),
              ],
            ),
            const SizedBox(height: 8),
            Text(q.label,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _typeChip(q),
                if (q.required)
                  _smallChip('Required', AppColors.error)
                else
                  _smallChip('Optional · safe to skip', AppColors.textHint),
                if (q.units.isNotEmpty)
                  _smallChip('Units: ${q.units}', AppColors.info),
                if (q.freeTextAllowed)
                  _smallChip('+ free text allowed', AppColors.info),
              ],
            ),
            const SizedBox(height: 16),
            // Voice feedback ABOVE the chips — the doctor's eye lands on
            // "Listening — speak now" / "Heard: …" / "→ Picked …" before
            // scanning options, so they always know whether their voice
            // landed.
            _liveTranscriptBanner(),
            const SizedBox(height: 16),
            _answerInput(q, answer),
            const SizedBox(height: 16),
            _navRow(q),
            const SizedBox(height: 8),
            Text(_statusMessage,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _stepBadge() {
    final total = _queue.length;
    final n = (_cursor + 1).clamp(1, total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$n / $total',
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.primary)),
    );
  }

  Widget _typeChip(TemplateQuestion q) {
    return _smallChip(q.type.label, AppColors.primary);
  }

  Widget _smallChip(String s, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(s,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: c)),
    );
  }

  Widget _answerInput(TemplateQuestion q, dynamic current) {
    switch (q.type) {
      case TemplateQuestionType.singleSelect:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _prefixHint(q),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(q.answers.length, (i) {
                final a = q.answers[i];
                final selected = current == a.label;
                return ChoiceChip(
                  label: Text('${_prefixLabel(i)}  ${a.label}'),
                  selected: selected,
                  onSelected: (_) => _selectAnswer(q, a),
                  labelStyle: TextStyle(
                    color:
                        selected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12,
                  ),
                  selectedColor: AppColors.primary.withOpacity(0.18),
                );
              }),
            ),
          ],
        );
      case TemplateQuestionType.multiSelect:
        final picked = (current as List?)?.cast<String>() ?? <String>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _prefixHint(q),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(q.answers.length, (i) {
                final a = q.answers[i];
                final selected = picked.contains(a.label);
                return FilterChip(
                  label: Text('${_prefixLabel(i)}  ${a.label}'),
                  selected: selected,
                  onSelected: (s) {
                    setState(() {
                      final list = List<String>.from(picked);
                      if (s) {
                        if (!list.contains(a.label)) list.add(a.label);
                      } else {
                        list.remove(a.label);
                      }
                      _answers[q.id] = list;
                    });
                  },
                  labelStyle: TextStyle(
                    color: selected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12,
                  ),
                  selectedColor: AppColors.primary.withOpacity(0.18),
                );
              }),
            ),
          ],
        );
      case TemplateQuestionType.text:
        final ctrl = TextEditingController(text: (current ?? '').toString());
        ctrl.selection =
            TextSelection.collapsed(offset: ctrl.text.length);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: ctrl,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Type your answer or dictate it.',
                isDense: true,
              ),
              onChanged: (v) {
                _answers[q.id] = v;
                _textAnswers[q.id] = v;
              },
            ),
            const SizedBox(height: 8),
            _recordButtonRow(),
          ],
        );
      case TemplateQuestionType.integer:
      case TemplateQuestionType.decimal:
        final ctrl =
            TextEditingController(text: (current ?? '').toString());
        ctrl.selection =
            TextSelection.collapsed(offset: ctrl.text.length);
        return Row(
          children: [
            SizedBox(
              width: 200,
              child: TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: InputDecoration(
                  hintText: q.type == TemplateQuestionType.integer
                      ? 'Number (e.g. 15)'
                      : 'Number (e.g. 15.5)',
                  suffixText: q.units.isEmpty ? null : q.units,
                  isDense: true,
                ),
                onChanged: (v) {
                  final n = num.tryParse(v);
                  if (n != null) _answers[q.id] = n;
                },
              ),
            ),
            const SizedBox(width: 12),
            _recordButtonRow(),
          ],
        );
      case TemplateQuestionType.date:
        final pickedDate = current is DateTime ? current : null;
        return Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_rounded, size: 16),
              label: Text(pickedDate == null
                  ? 'Pick date'
                  : '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}'),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: pickedDate ?? now,
                  firstDate: DateTime(now.year - 100),
                  lastDate: DateTime(now.year + 5),
                );
                if (d != null) setState(() => _answers[q.id] = d);
              },
            ),
          ],
        );
    }
  }

  /// Prefix shown on each MCQ chip ("1." / "A.") for the current question.
  String _prefixLabel(int answerIndex) {
    if (_useAlphaPrefix(_cursor)) {
      // 0 → A, 1 → B, ... wraps after 26 (extremely rare in pathology
      // synoptics but kept harmless).
      final code = ('A'.codeUnitAt(0) + (answerIndex % 26));
      return '${String.fromCharCode(code)}.';
    }
    return '${answerIndex + 1}.';
  }

  /// Inline hint above the MCQ chips telling the doctor what they can say
  /// to pick by voice — alternates "say A / B / C..." vs "say one / two…"
  /// so they immediately know whether the current question is letter-keyed
  /// or number-keyed.
  Widget _prefixHint(TemplateQuestion q) {
    final useAlpha = _useAlphaPrefix(_cursor);
    final hint = useAlpha
        ? 'Say "A", "B", "C"… to pick.'
        : 'Say "one", "two", "three"… to pick.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            useAlpha
                ? Icons.abc_rounded
                : Icons.format_list_numbered_rounded,
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(hint,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _recordButtonRow() {
    // `refining` is purely a status indicator now — the button stays
    // enabled so the doctor can re-record or move on while the Whisper
    // call is in flight. The recorded clip's transcription will be
    // upgraded silently when the call returns.
    final refining = _transcribingQuestionId != null &&
        _transcribingQuestionId == _currentQuestion?.id;
    return Row(
      children: [
        FilledButton.icon(
          onPressed: _recording
              ? _stopRecordingForCurrent
              : _startRecordingForCurrent,
          style: FilledButton.styleFrom(
            backgroundColor: _recording ? AppColors.error : AppColors.primary,
          ),
          icon: Icon(
              _recording ? Icons.stop_rounded : Icons.mic_rounded,
              size: 16),
          label: Text(_recording
              ? 'Stop (${_fmtDur(_recordingDuration)})'
              : 'Dictate'),
        ),
        const SizedBox(width: 8),
        if (refining) ...[
          const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary)),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            _recording
                ? 'Recording — speak the answer, then say "stop" or "next".'
                : (refining
                    ? 'Refining transcript in background — feel free to move on.'
                    : 'Tap to dictate a free-text comment.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Always-visible voice feedback panel. Renders four rows of state so the
  /// doctor never has to wonder whether the mic is hot, what was just heard,
  /// or which option that mapped to:
  ///
  ///   1. **Mic state** — pulsing green dot + "Listening — speak now" while
  ///      the recognizer is hot, dimmed grey "Mic idle" otherwise.
  ///   2. **Live (in-progress) words** — partials stream in italic, char by
  ///      char, so the doctor watches the recognizer hear them.
  ///   3. **Last heard** — the last *finalised* utterance, in a pill, so even
  ///      if it didn't match anything the doctor can see why and try again.
  ///   4. **Match confirmation** — a green chip "→ picked B. Colon" that
  ///      fades in for ~2.5s after each successful selection.
  Widget _liveTranscriptBanner() {
    return StreamBuilder<String>(
      stream: _voice.status,
      builder: (context, _) {
        final listening = _voice.isListening;
        final partial = _livePartial.trim();
        final lastFinal = _lastFinal.trim();
        final lastMatch = _lastMatchLabel.trim();
        // Only show the green "match" chip while it's recent — otherwise it
        // misleads the doctor on the next question into thinking the previous
        // match still applies.
        final matchVisible = lastMatch.isNotEmpty &&
            DateTime.now().difference(_lastMatchAt) <
                const Duration(seconds: 4);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: listening
                  ? AppColors.success.withValues(alpha: 0.45)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: mic state with pulsing dot.
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, child) => Transform.scale(
                      scale: listening ? 1 + 0.25 * _pulse.value : 1,
                      child: child,
                    ),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: listening
                            ? AppColors.success
                            : AppColors.textHint,
                        boxShadow: listening
                            ? [
                                BoxShadow(
                                  color: AppColors.success
                                      .withValues(alpha: 0.4),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                      listening
                          ? Icons.mic_rounded
                          : Icons.mic_off_rounded,
                      size: 14,
                      color: listening
                          ? AppColors.success
                          : AppColors.textHint),
                  const SizedBox(width: 6),
                  Text(
                    listening
                        ? (partial.isNotEmpty
                            ? 'Listening — hearing you now'
                            : 'Listening — speak now')
                        : 'Mic idle — tap any chip or say "next"',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: listening
                          ? AppColors.success
                          : AppColors.textHint,
                    ),
                  ),
                ],
              ),
              // Row 2: live partial — italic, dimmed, growing in real-time.
              if (partial.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.graphic_eq_rounded,
                        size: 13, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$partial…',
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // Row 3: last finalised utterance — what the recognizer
              // committed. Stays visible even after the partial cleared,
              // so the doctor always has a record of "what you said".
              if (lastFinal.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.hearing_rounded,
                        size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: AppColors.textPrimary,
                          ),
                          children: [
                            const TextSpan(
                                text: 'Heard: ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary)),
                            TextSpan(text: '"$lastFinal"'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // Row 4: explicit match confirmation. Fades after 4s.
              if (matchVisible) ...[
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 14, color: AppColors.success),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '→ Picked: $lastMatch',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _navRow(TemplateQuestion q) {
    final isLast = _cursor >= _queue.length - 1;
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _cursor == 0 ? null : _retreat,
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text('Previous'),
        ),
        const SizedBox(width: 8),
        if (!q.required)
          OutlinedButton.icon(
            onPressed: _skip,
            icon: const Icon(Icons.skip_next_rounded, size: 16),
            label: const Text('Skip'),
          ),
        const Spacer(),
        if (_answers[q.id] != null)
          OutlinedButton.icon(
            onPressed: _clearCurrentAnswer,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Clear'),
          ),
        const SizedBox(width: 8),
        if (!isLast)
          FilledButton.icon(
            onPressed: _advance,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('Next'),
          )
        else
          FilledButton.icon(
            onPressed: _composing
                ? null
                : (_allRequiredAnswered ? _composeAndSave : null),
            icon: _composing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.task_alt_rounded, size: 16),
            label: Text(_composing ? 'Composing…' : 'Sign out report'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
          ),
      ],
    );
  }

  Widget _rightPanel() {
    // Until a template is picked, the right panel acts as a guidance card —
    // the doctor sees what each template will ask before committing.
    if (_pickedTemplate == null) return _templateOverviewPanel();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.fact_check_outlined,
                    size: 16, color: AppColors.primary),
                SizedBox(width: 6),
                Text('Synoptic preview',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            _requiredProgressBar(),
            const SizedBox(height: 8),
            Expanded(child: _previewBody()),
            if (_allRequiredAnswered) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _composing ? null : _composeAndSave,
                  icon: _composing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome, size: 16),
                  label: Text(_composing ? 'Composing…' : 'Compose & sign out'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewBody() {
    if (_answers.isEmpty) {
      return Center(
        child: Text(
          'Answers will appear here as you progress through the wizard.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final q in _queue) ...[
            if (_answers[q.id] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textPrimary),
                    children: [
                      TextSpan(
                        text: '${q.label}: ',
                        style:
                            const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: _formatAnswer(q, _answers[q.id])),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Right-side panel shown during Step 0 — gives the doctor a preview of
  /// what each template covers (sections + question/required counts) so they
  /// can choose informed.
  Widget _templateOverviewPanel() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.library_books_outlined,
                    size: 16, color: AppColors.primary),
                SizedBox(width: 6),
                Text('Available templates',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Each template has its own set of required and optional fields. Required fields must be answered to save; optional fields can be skipped.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: widget.templates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final t = widget.templates[i];
                  final s = widget.schemas[t.id]!;
                  final isDefault = t.id == widget.defaultTemplateId;
                  final required =
                      s.allQuestions.where((q) => q.required).length;
                  final optional = s.totalQuestions - required;
                  return InkWell(
                    onTap: () => _pick(t),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDefault
                              ? AppColors.primary.withOpacity(0.4)
                              : AppColors.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(t.name,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                              ),
                              if (isDefault)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.warning.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('DEFAULT',
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.warning)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _miniChip('${s.sections.length} sec',
                                  AppColors.info),
                              _miniChip('$required required',
                                  AppColors.error),
                              if (optional > 0)
                                _miniChip(
                                    '$optional optional', AppColors.textHint),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String s, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(s,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: c)),
    );
  }

  /// Required-only progress bar shown above the synoptic preview so the
  /// doctor sees how many *mandatory* fields are still outstanding —
  /// optional fields are intentionally excluded so the bar doesn't punish
  /// them for skipping safely-skippable items.
  Widget _requiredProgressBar() {
    if (_queue.isEmpty) return const SizedBox.shrink();
    final required = _queue.where((q) => q.required).toList();
    if (required.isEmpty) {
      return Text('No required fields in this branch.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    final answered = required.where((q) {
      final v = _answers[q.id];
      if (v == null) return false;
      if (v is String && v.trim().isEmpty) return false;
      if (v is List && v.isEmpty) return false;
      return true;
    }).length;
    final pct = answered / required.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Required progress',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.textHint),
              ),
            ),
            Text('$answered / ${required.length}',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(
                pct >= 1 ? AppColors.success : AppColors.primary),
          ),
        ),
      ],
    );
  }

  String _formatAnswer(TemplateQuestion q, dynamic v) {
    if (v == null) return '—';
    if (v is List) return v.join(', ');
    if (v is num && q.units.isNotEmpty) return '$v ${q.units}';
    if (v is DateTime) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    }
    return v.toString();
  }

  Widget _commandHints() {
    final phrases = SettingsService.getPhrases();
    String first(VoiceCommand c) =>
        (phrases[c.key] ?? '').split('|').first.trim();
    final hints = <String>[];
    if (_pickedTemplate == null) {
      // Step 0 — picker. Show that they can speak a template name OR confirm
      // for the default. The actual template-name match happens in
      // _maybeMatchTemplateFromTranscript.
      if (widget.templates.length > 1) {
        final t = widget.templates.firstWhere(
          (t) => t.id != widget.defaultTemplateId,
          orElse: () => widget.templates.first,
        );
        hints.add('"use ${t.name.toLowerCase()}"');
      }
      hints.add('"${first(VoiceCommand.confirm)}" (use default)');
    } else if (!_patientIdConfirmed) {
      hints.add('"${first(VoiceCommand.patientId)} 12345"');
      hints.add('"${first(VoiceCommand.confirm)}"');
    } else if (_saved) {
      hints.add('"${first(VoiceCommand.dashboard)}"');
    } else {
      hints.addAll([
        '"${first(VoiceCommand.next)}"',
        '"${first(VoiceCommand.previous)}"',
        '"${first(VoiceCommand.skip)}" (optional only)',
        '"${first(VoiceCommand.start)}"',
        '"${first(VoiceCommand.stop)}"',
        '"${first(VoiceCommand.save)}"',
      ]);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline_rounded,
              size: 14, color: AppColors.textHint),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              children: hints
                  .map((h) => Text(h,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500)))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
