import 'dart:async';

import 'package:flutter/material.dart';

import '../models/report_models.dart';
import '../services/audio_service.dart';
import '../services/hive_storage_service.dart';
import '../services/openai_service.dart';
import '../services/settings_service.dart';
import '../services/voice_command_service.dart';
import '../theme/app_theme.dart';

/// Voice-driven guided wizard backed by a parsed `TemplateSchema`.
///
/// Flow per question:
///   1. Wizard shows the current question + answer choices.
///   2. The doctor either taps an answer OR says it.
///       - For singleSelect / multiSelect, the live transcript is fuzzy-matched
///         against the answer labels.
///       - For free-text, the running transcript becomes the answer (refined
///         by Whisper when the doctor advances).
///       - For integer/decimal, digits/number-words are extracted via
///         `VoiceCommandService.normalizeSpokenId`.
///   3. Saying "next" / tapping Next advances. Branching: if the picked
///      answer triggers child questions, those are inserted into the queue
///      after the current position.
///   4. Saying "previous" / tapping Back walks the queue backwards.
///   5. After the last required question is answered, "save" triggers the
///      LLM compose pass and saves the resulting PathologyReport.
class GuidedReportScreen extends StatefulWidget {
  final TemplateDocument template;
  final TemplateSchema schema;
  final ValueChanged<PathologyReport>? onReportSaved;
  final VoidCallback? onBack;

  const GuidedReportScreen({
    super.key,
    required this.template,
    required this.schema,
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

  // Patient context
  String _confirmedPatientId = '';
  final TextEditingController _patientIdCtrl = TextEditingController();
  bool _patientIdConfirmed = false;

  // Question queue (flat across sections, in order, with branched children
  // inserted just-in-time when an answer with triggers is picked).
  late List<TemplateQuestion> _queue;
  int _cursor = 0;
  // Section title shown above the question — derived from where the question
  // originally sat in the schema.
  late Map<String, String> _questionToSection;

  // Captured answers: questionId -> dynamic (String, List<String>, num).
  final Map<String, dynamic> _answers = <String, dynamic>{};
  // Free-text dictation captured per question (for text type).
  final Map<String, String> _textAnswers = <String, String>{};

  // Live transcript pieces.
  String _liveFinal = '';
  String _livePartial = '';

  // Recording state for the current question (used for text/numeric answers
  // so we can transcribe with Whisper).
  bool _recording = false;
  Duration _recordingDuration = Duration.zero;

  String _statusMessage =
      'Say or type your patient ID to begin the guided wizard.';
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

    // Build the linear queue (top-level questions in document order). Branched
    // children are inserted on demand as answers are picked.
    _queue = [];
    _questionToSection = {};
    for (final s in widget.schema.sections) {
      for (final q in s.questions) {
        if (q.parentAnswerId.isEmpty) {
          _queue.add(q);
        }
        _questionToSection[q.id] = s.title;
      }
    }
    if (_queue.isEmpty) {
      _statusMessage =
          'Template has no top-level questions. Re-parse it from the Templates screen.';
    }

    _cmdSub = _voice.commands.listen(_handleCommand);
    _transcriptSub = _voice.transcript.listen(_handleTranscript);
    _durationSub = _audio.durationStream.listen((d) {
      if (mounted) setState(() => _recordingDuration = d);
    });
    _voice.start();
  }

  @override
  void dispose() {
    _cmdSub?.cancel();
    _transcriptSub?.cancel();
    _durationSub?.cancel();
    _pulse.dispose();
    _audio.dispose();
    _patientIdCtrl.dispose();
    super.dispose();
  }

  TemplateQuestion? get _currentQuestion {
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
      } else {
        _livePartial = u.text;
      }
    });
    // Try to match select answers from the latest transcript chunk.
    if (u.isFinal) _maybeMatchAnswerFromTranscript(u.text);
  }

  void _maybeMatchAnswerFromTranscript(String text) {
    final q = _currentQuestion;
    if (q == null) return;
    if (q.type == TemplateQuestionType.singleSelect ||
        q.type == TemplateQuestionType.multiSelect) {
      final matched = _fuzzyMatchAnswer(text, q.answers);
      if (matched != null) _selectAnswer(q, matched);
    } else if (q.type == TemplateQuestionType.integer ||
        q.type == TemplateQuestionType.decimal) {
      final n = _extractNumber(text);
      if (n != null) {
        setState(() => _answers[q.id] = n);
      }
    } else if (q.type == TemplateQuestionType.text) {
      // Accumulate the live transcript as the free-text answer; refined by
      // Whisper when advancing if a recording was made.
      _textAnswers[q.id] = (_textAnswers[q.id] ?? '').isEmpty
          ? text
          : '${_textAnswers[q.id]} $text';
      _answers[q.id] = _textAnswers[q.id];
    }
  }

  TemplateAnswer? _fuzzyMatchAnswer(
      String spoken, List<TemplateAnswer> answers) {
    if (answers.isEmpty) return null;
    final tokens = _tokens(spoken);
    if (tokens.isEmpty) return null;

    TemplateAnswer? best;
    double bestScore = 0;
    for (final a in answers) {
      final answerTokens = _tokens(a.label);
      if (answerTokens.isEmpty) continue;
      // Substring shortcut: speaker said the answer label as-is.
      if (spoken.toLowerCase().contains(a.label.toLowerCase())) {
        return a;
      }
      // Token overlap score (Jaccard-style).
      final inter = answerTokens.where(tokens.contains).length;
      final union = ({...answerTokens, ...tokens}).length;
      final score = union == 0 ? 0.0 : inter / union;
      if (score > bestScore) {
        bestScore = score;
        best = a;
      }
    }
    // Require a meaningful overlap to avoid false matches.
    if (bestScore >= 0.6) return best;
    return null;
  }

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

    if (e.command == VoiceCommand.back ||
        e.command == VoiceCommand.dashboard) {
      widget.onBack?.call();
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
      _maybeReshapeQueue(q, a);
    });
  }

  /// When an answer with `triggersQuestionIds` is picked, splice the child
  /// questions into the queue right after the current position. Conversely,
  /// if an answer that previously triggered children is replaced (single-
  /// select), drop those children from the queue (and their answers) so the
  /// wizard reflects the new branch.
  void _maybeReshapeQueue(TemplateQuestion q, TemplateAnswer picked) {
    final allQs = widget.schema.allQuestions;

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
    final path = await _audio.stopRecording();
    setState(() => _recording = false);
    if (path == null || q == null) return;
    // Whisper-correct the captured audio so the answer is high-accuracy.
    try {
      final text = await OpenAIService.transcribeAudio(
        path,
        prompt: 'Histopathology answer to: ${q.label}',
      );
      if (text.trim().isEmpty) return;
      if (q.type == TemplateQuestionType.text) {
        setState(() {
          _textAnswers[q.id] = text;
          _answers[q.id] = text;
        });
      } else if (q.type == TemplateQuestionType.integer ||
          q.type == TemplateQuestionType.decimal) {
        final n = _extractNumber(text);
        if (n != null) setState(() => _answers[q.id] = n);
      } else if (q.type == TemplateQuestionType.singleSelect ||
          q.type == TemplateQuestionType.multiSelect) {
        final matched = _fuzzyMatchAnswer(text, q.answers);
        if (matched != null) _selectAnswer(q, matched);
      }
    } catch (e) {
      _setStatus('Whisper failed — using live transcript · $e');
    }
  }

  // ─── Compose & save ───────────────────────────────────────────────────

  Future<void> _composeAndSave() async {
    setState(() {
      _composing = true;
      _statusMessage = 'Composing synoptic report…';
    });
    try {
      final labels = <String, String>{};
      for (final q in widget.schema.allQuestions) {
        labels[q.id] = q.label;
      }
      final composed = await OpenAIService.composeSynopticReport(
        answers: _answers,
        questionLabels: labels,
        templateName: widget.template.name,
      );
      final reportNumber = HiveStorageService.nextReportNumber();
      final existing = HiveStorageService.getPatient(_confirmedPatientId);
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
        summary: composed['summary'] ?? '',
        rawTranscript: '',
        synopticAnswers: Map<String, dynamic>.from(_answers),
        templateId: widget.template.id,
        status: ReportStatus.pending,
        reportedDate: DateTime.now(),
        pathologistName: SettingsService.getPathologistName(),
        pathologistRegistration:
            SettingsService.getPathologistRegistration(),
      );
      await HiveStorageService.saveReport(report);
      widget.onReportSaved?.call(report);
      setState(() {
        _composing = false;
        _saved = true;
        _composedReport = report;
        _statusMessage = 'Saved ${report.reportNumber}.';
      });
    } catch (e) {
      setState(() {
        _composing = false;
        _statusMessage = 'Compose failed — $e';
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
                Text('Guided Report — ${widget.template.name}',
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${widget.schema.sections.length} sections · ${widget.schema.totalQuestions} questions · v${widget.schema.version.isEmpty ? "—" : widget.schema.version}',
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
        final listening = _voice.isListening;
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (listening ? AppColors.success : AppColors.textHint)
                .withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) => Transform.scale(
                  scale: listening ? 1 + 0.15 * _pulse.value : 1,
                  child: child,
                ),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: listening ? AppColors.success : AppColors.textHint,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(listening ? 'Listening' : 'Idle',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: listening
                          ? AppColors.success
                          : AppColors.textHint)),
            ],
          ),
        );
      },
    );
  }

  Widget _leftPanel() {
    if (!_patientIdConfirmed) return _patientIdCard();
    if (_saved) return _savedCard();
    if (_queue.isEmpty) return _emptyCard();
    return _questionCard();
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
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
                if (!q.required) _smallChip('Optional', AppColors.textHint),
                if (q.units.isNotEmpty)
                  _smallChip('Units: ${q.units}', AppColors.info),
              ],
            ),
            const SizedBox(height: 16),
            _answerInput(q, answer),
            const SizedBox(height: 16),
            _liveTranscriptBanner(),
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
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: q.answers.map((a) {
            final selected = current == a.label;
            return ChoiceChip(
              label: Text(a.label),
              selected: selected,
              onSelected: (_) => _selectAnswer(q, a),
              labelStyle: TextStyle(
                color: selected ? AppColors.primary : AppColors.textPrimary,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
              selectedColor: AppColors.primary.withOpacity(0.18),
            );
          }).toList(),
        );
      case TemplateQuestionType.multiSelect:
        final picked = (current as List?)?.cast<String>() ?? <String>[];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: q.answers.map((a) {
            final selected = picked.contains(a.label);
            return FilterChip(
              label: Text(a.label),
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
                color:
                    selected ? AppColors.primary : AppColors.textPrimary,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
              selectedColor: AppColors.primary.withOpacity(0.18),
            );
          }).toList(),
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

  Widget _recordButtonRow() {
    return Row(
      children: [
        FilledButton.icon(
          onPressed: _recording
              ? _stopRecordingForCurrent
              : _startRecordingForCurrent,
          style: FilledButton.styleFrom(
            backgroundColor:
                _recording ? AppColors.error : AppColors.primary,
          ),
          icon: Icon(
              _recording ? Icons.stop_rounded : Icons.mic_rounded,
              size: 16),
          label: Text(_recording
              ? 'Stop (${_fmtDur(_recordingDuration)})'
              : 'Dictate'),
        ),
        const SizedBox(width: 8),
        Text(
          _recording
              ? 'Recording — speak the answer.'
              : 'Tap to capture a high-accuracy Whisper answer.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _liveTranscriptBanner() {
    final f = _liveFinal.trim();
    final p = _livePartial.trim();
    if (f.isEmpty && p.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.graphic_eq_rounded,
              size: 14, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textPrimary),
                children: [
                  if (f.isNotEmpty) TextSpan(text: f),
                  if (f.isNotEmpty && p.isNotEmpty) const TextSpan(text: ' '),
                  if (p.isNotEmpty)
                    TextSpan(
                      text: p,
                      style: const TextStyle(
                          color: AppColors.textHint,
                          fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
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
                : const Icon(Icons.save_rounded, size: 16),
            label: Text(_composing ? 'Composing…' : 'Save report'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
          ),
      ],
    );
  }

  Widget _rightPanel() {
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
                  label: Text(_composing ? 'Composing…' : 'Compose & save'),
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
    if (!_patientIdConfirmed) {
      hints.add('"${first(VoiceCommand.patientId)} 12345"');
      hints.add('"${first(VoiceCommand.confirm)}"');
    } else if (_saved) {
      hints.add('"${first(VoiceCommand.dashboard)}"');
    } else {
      hints.addAll([
        '"${first(VoiceCommand.next)}"',
        '"${first(VoiceCommand.previous)}"',
        '"${first(VoiceCommand.skip)}"',
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
