import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/report_models.dart';
import '../services/audio_service.dart';
import '../services/hive_storage_service.dart';
import '../services/openai_service.dart';
import '../services/settings_service.dart';
import '../services/voice_command_service.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_debug_panel.dart';
import '../widgets/voice_unavailable_banner.dart';

/// Fully voice-driven report creation.
///
/// State machine:
///   awaitingPatientId  → user says "patient id is <X>"            → confirmingPatientId
///   confirmingPatientId → "confirm" / "cancel"
///   readyToRecord      → "start dictation"                        → recording
///   recording           → "pause" → paused ; "stop dictation"     → transcribing
///   paused              → "resume"                                 → recording
///   transcribing        → (auto)                                   → generating
///   generating          → (auto)                                   → reportReady
///   reportReady         → "save report" / "discard"
enum _VoiceState {
  awaitingPatientId,
  confirmingPatientId,
  readyToRecord,
  recording,
  paused,
  transcribing,
  generating,
  reportReady,
  saved,
}

class VoiceReportScreen extends StatefulWidget {
  final PathologyReport? existingReport;
  final ValueChanged<PathologyReport>? onReportSaved;
  final VoidCallback? onBack;

  const VoiceReportScreen({
    super.key,
    this.existingReport,
    this.onReportSaved,
    this.onBack,
  });

  @override
  State<VoiceReportScreen> createState() => _VoiceReportScreenState();
}

class _VoiceReportScreenState extends State<VoiceReportScreen>
    with TickerProviderStateMixin {
  final AudioService _audio = AudioService();
  final VoiceCommandService _voice = VoiceCommandService.instance;

  _VoiceState _state = _VoiceState.awaitingPatientId;
  String _candidatePatientId = '';
  String _confirmedPatientId = '';
  String _statusMessage = 'Say your patient ID — or type it below';

  // Live recognizer output. `_liveFinal` accumulates finalized chunks; the
  // still-growing current utterance is kept separately in `_livePartial` so
  // the display doesn't flicker when a new partial replaces the old one.
  String _liveFinal = '';
  String _livePartial = '';

  final TextEditingController _patientIdCtrl = TextEditingController();

  String get _liveTranscript {
    final buf = _liveFinal.trim();
    final p = _livePartial.trim();
    if (buf.isEmpty) return p;
    if (p.isEmpty) return buf;
    return '$buf $p';
  }

  Duration _recordingDuration = Duration.zero;
  final List<double> _waveform = [];
  final List<VoiceRecording> _recordings = [];
  String _dictationText = '';
  bool _showDebugLog = false;

  PathologyReport? _workingReport;

  StreamSubscription<VoiceCommandEvent>? _cmdSub;
  StreamSubscription<TranscriptUpdate>? _transcriptSub;

  late final AnimationController _pulse;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1, end: 1.18)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    _audio.durationStream.listen((d) {
      if (mounted) setState(() => _recordingDuration = d);
    });
    _audio.amplitudeStream.listen((a) {
      if (mounted) {
        setState(() {
          if (_waveform.length > 100) _waveform.removeAt(0);
          _waveform.add(a);
        });
      }
    });

    if (widget.existingReport != null) {
      final r = widget.existingReport!;
      _confirmedPatientId = r.patientId;
      _candidatePatientId = r.patientId;
      _patientIdCtrl.text = r.patientId;
      _workingReport = r;
      _recordings.addAll(r.voiceRecordings);
      _dictationText = r.rawTranscript;
      _state = _VoiceState.readyToRecord;
      _statusMessage = 'Say "start dictation" to add to this report';
    }

    _cmdSub = _voice.commands.listen(_handleCommand);
    _transcriptSub = _voice.transcript.listen(_handleTranscript);
    _voice.start();
  }

  @override
  void dispose() {
    _cmdSub?.cancel();
    _transcriptSub?.cancel();
    _pulse.dispose();
    _audio.dispose();
    _patientIdCtrl.dispose();
    super.dispose();
  }

  // Manual (tap) patient ID entry. Mirrors what _confirmPatientId does for voice.
  void _setPatientIdManually(String value) {
    final id = value.trim().toUpperCase();
    if (id.isEmpty) return;
    setState(() {
      _candidatePatientId = id;
      _confirmedPatientId = id;
      _state = _VoiceState.readyToRecord;
      _statusMessage = 'Patient $id ready — dictate or tap record';
    });
  }

  // ─── Transcript stream ────────────────────────────────────

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
  }

  // ─── Command dispatch ─────────────────────────────────────

  Future<void> _handleCommand(VoiceCommandEvent e) async {
    if (!mounted) return;
    debugPrint('voice command: ${e.command} payload=${e.payload}');

    // Global: back/home works from any state.
    if (e.command == VoiceCommand.back ||
        e.command == VoiceCommand.dashboard) {
      widget.onBack?.call();
      return;
    }

    switch (_state) {
      case _VoiceState.awaitingPatientId:
        if (e.command == VoiceCommand.patientId && e.payload.isNotEmpty) {
          setState(() {
            _candidatePatientId = e.payload;
            _state = _VoiceState.confirmingPatientId;
            _statusMessage =
                'Patient ID: $_candidatePatientId — say "confirm" or "cancel"';
          });
        }
        break;

      case _VoiceState.confirmingPatientId:
        if (e.command == VoiceCommand.confirm) {
          _confirmPatientId();
        } else if (e.command == VoiceCommand.cancel ||
            e.command == VoiceCommand.discard) {
          setState(() {
            _candidatePatientId = '';
            _state = _VoiceState.awaitingPatientId;
            _statusMessage = 'Say your patient ID';
          });
        } else if (e.command == VoiceCommand.patientId &&
            e.payload.isNotEmpty) {
          setState(() {
            _candidatePatientId = e.payload;
            _statusMessage =
                'Patient ID: $_candidatePatientId — say "confirm" or "cancel"';
          });
        }
        break;

      case _VoiceState.readyToRecord:
        if (e.command == VoiceCommand.start) await _startRecording();
        break;

      case _VoiceState.recording:
        if (e.command == VoiceCommand.pause) await _pauseRecording();
        if (e.command == VoiceCommand.stop) await _stopRecording();
        break;

      case _VoiceState.paused:
        if (e.command == VoiceCommand.resume) await _resumeRecording();
        if (e.command == VoiceCommand.stop) await _stopRecording();
        break;

      case _VoiceState.reportReady:
        if (e.command == VoiceCommand.save) await _saveReport();
        if (e.command == VoiceCommand.discard) _reset();
        if (e.command == VoiceCommand.generate) await _generateReport();
        break;

      case _VoiceState.transcribing:
      case _VoiceState.generating:
      case _VoiceState.saved:
        break;
    }
  }

  void _confirmPatientId() {
    setState(() {
      _confirmedPatientId = _candidatePatientId;
      _state = _VoiceState.readyToRecord;
      _statusMessage =
          'Patient $_confirmedPatientId ready — say "start dictation"';
    });
  }

  // ─── Recording ───────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!await _audio.hasPermission()) {
      _setStatus('Microphone permission denied');
      return;
    }
    final path = await _audio.startRecording();
    if (path == null) {
      _setStatus('Could not start recording');
      return;
    }
    setState(() {
      _state = _VoiceState.recording;
      _recordingDuration = Duration.zero;
      _waveform.clear();
      _liveFinal = '';
      _livePartial = '';
      _statusMessage = 'Recording — say "pause" or "stop dictation"';
    });
  }

  Future<void> _pauseRecording() async {
    await _audio.pauseRecording();
    setState(() {
      _state = _VoiceState.paused;
      _statusMessage = 'Paused — say "resume" or "stop dictation"';
    });
  }

  Future<void> _resumeRecording() async {
    await _audio.resumeRecording();
    setState(() {
      _state = _VoiceState.recording;
      _statusMessage = 'Recording — say "pause" or "stop dictation"';
    });
  }

  Future<void> _stopRecording() async {
    final path = await _audio.stopRecording();
    if (path == null) {
      setState(() => _state = _VoiceState.readyToRecord);
      return;
    }
    // Seed the recording with the live on-device STT text so a raw transcript
    // is always available even if Whisper fails or returns nothing.
    final liveSeed = _liveTranscript.trim();
    final rec = VoiceRecording(
      filePath: path,
      duration: _recordingDuration,
      label: 'Dictation ${_recordings.length + 1}',
      transcription: liveSeed,
    );
    setState(() {
      _recordings.add(rec);
      _dictationText = _joinedTranscripts();
      _state = _VoiceState.transcribing;
      _statusMessage = 'Transcribing dictation…';
    });
    _autosaveDraft();
    await _transcribe(rec);
    await _generateReport();
  }

  String _joinedTranscripts() => _recordings
      .map((r) => r.transcription.trim())
      .where((t) => t.isNotEmpty)
      .join('\n\n');

  Future<void> _transcribe(VoiceRecording rec) async {
    try {
      final text = await OpenAIService.transcribeAudio(
        rec.filePath,
        prompt:
            'Medical histopathology dictation. Proper terminology expected.',
      );
      final idx = _recordings.indexWhere((r) => r.id == rec.id);
      if (idx != -1 && text.trim().isNotEmpty) {
        _recordings[idx] = _recordings[idx].copyWith(transcription: text);
      }
      setState(() => _dictationText = _joinedTranscripts());
      _autosaveDraft();
    } catch (e) {
      // Keep the live-STT fallback that was seeded at stop time.
      _setStatus('Whisper failed — using live transcript · $e');
      setState(() => _dictationText = _joinedTranscripts());
      _autosaveDraft();
    }
  }

  // ─── Report generation ─────────────────────────────────────

  Future<void> _generateReport() async {
    final rawSource = _dictationText.trim().isNotEmpty
        ? _dictationText
        : _liveTranscript;
    if (rawSource.trim().isEmpty) {
      _setStatus('Nothing to generate from');
      return;
    }
    setState(() {
      _state = _VoiceState.generating;
      _statusMessage = 'Generating report…';
    });
    try {
      final existingPatient =
          HiveStorageService.getPatient(_confirmedPatientId);
      final patientContext = existingPatient == null
          ? 'patient_id: $_confirmedPatientId'
          : 'patient_id: $_confirmedPatientId\n'
              'known_name: ${existingPatient.name}\n'
              'known_age: ${existingPatient.age}\n'
              'known_gender: ${existingPatient.gender}';

      final fields = await OpenAIService.generateReportFromTranscript(
        rawSource,
        patientContext: patientContext,
      );

      final reportNumber = widget.existingReport?.reportNumber ??
          HiveStorageService.nextReportNumber();

      final report = (widget.existingReport ??
              PathologyReport(
                reportNumber: reportNumber,
                patientId: _confirmedPatientId,
              ))
          .copyWith(
        patientId: _confirmedPatientId,
        patientName: _nonEmpty(fields['patient_name'], existingPatient?.name),
        patientAge: int.tryParse(fields['patient_age'] ?? '') ??
            existingPatient?.age ??
            0,
        patientGender:
            _nonEmpty(fields['patient_gender'], existingPatient?.gender),
        mrn: _nonEmpty(fields['patient_id'], _confirmedPatientId),
        labNo: _nonEmpty(fields['lab_no'], existingPatient?.labNumber),
        visitNo: _nonEmpty(fields['visit_no'], existingPatient?.visitNumber),
        orderedBy: _nonEmpty(fields['ordered_by'], existingPatient?.orderedBy),
        referredBy: _nonEmpty(
            fields['referred_by'], existingPatient?.referringDoctor),
        clinicalInformation: fields['clinical_information'] ?? '',
        specimen: fields['specimen'] ?? '',
        grossExamination: fields['gross_examination'] ?? '',
        microscopyImpression: fields['microscopy_impression'] ?? '',
        summary: fields['summary'] ?? '',
        rawTranscript: rawSource,
        voiceRecordings: List.of(_recordings),
        status: ReportStatus.pending,
        reportedDate: DateTime.now(),
        pathologistName: SettingsService.getPathologistName(),
        pathologistRegistration: SettingsService.getPathologistRegistration(),
        pathologistName2: SettingsService.getDualSignatureEnabled()
            ? SettingsService.getPathologist2Name()
            : '',
        pathologistRegistration2: SettingsService.getDualSignatureEnabled()
            ? SettingsService.getPathologist2Registration()
            : '',
      );

      setState(() {
        _workingReport = report;
        _state = _VoiceState.reportReady;
        _statusMessage = 'Report ready — say "save report" or "discard"';
      });
    } catch (e) {
      _setStatus('Generation failed — $e');
      setState(() => _state = _VoiceState.readyToRecord);
    }
  }

  String _nonEmpty(String? a, String? b) {
    if (a != null && a.trim().isNotEmpty) return a.trim();
    return b ?? '';
  }

  Future<void> _saveReport() async {
    final r = _workingReport;
    if (r == null) return;
    await HiveStorageService.saveReport(r);
    await HiveStorageService.clearDraft(r.patientId);
    widget.onReportSaved?.call(r);
    setState(() {
      _state = _VoiceState.saved;
      _statusMessage =
          'Saved ${r.reportNumber}. Say "new report" or "go back".';
    });
  }

  void _reset() {
    setState(() {
      _workingReport = null;
      _dictationText = '';
      _recordings.clear();
      _state = _VoiceState.readyToRecord;
      _statusMessage = 'Discarded. Say "start dictation" to retry.';
    });
  }

  void _autosaveDraft() {
    if (_confirmedPatientId.isEmpty) return;
    final raw = _dictationText.trim().isNotEmpty
        ? _dictationText
        : _liveTranscript;
    HiveStorageService.saveDraft(_confirmedPatientId, {
      'raw_transcript': raw,
      'recording_paths': _recordings.map((r) => r.filePath).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  void _setStatus(String msg) {
    if (!mounted) return;
    setState(() => _statusMessage = msg);
  }

  // ─── UI (display-only; no input controls) ─────────────────

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _topBar(),
          // Persistent voice-unavailability banner — collapses when STT
          // is healthy. Lets the doctor see the reason and recover with
          // Retry / Open Settings without leaving the screen.
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
          if (_showDebugLog)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: VoiceDebugPanel(height: 200),
            ),
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
      child: Column(
        children: [
          Row(
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
                child: const Icon(Icons.mic_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Voice Report',
                      style: Theme.of(context).textTheme.titleLarge),
                  Text('Speak or tap — both work',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const Spacer(),
              IconButton(
                tooltip: _showDebugLog ? 'Hide debug log' : 'Show debug log',
                icon: Icon(_showDebugLog
                    ? Icons.bug_report_rounded
                    : Icons.bug_report_outlined),
                onPressed: () =>
                    setState(() => _showDebugLog = !_showDebugLog),
              ),
              const SizedBox(width: 4),
              _listeningIndicator(),
            ],
          ),
          const SizedBox(height: 10),
          _manualControls(),
        ],
      ),
    );
  }


  Widget _manualControls() {
    final canStart = _confirmedPatientId.isNotEmpty &&
        (_state == _VoiceState.readyToRecord ||
            _state == _VoiceState.saved);
    final isRecording = _state == _VoiceState.recording;
    final isPaused = _state == _VoiceState.paused;
    final canGenerate = _dictationText.trim().isNotEmpty &&
        _state != _VoiceState.generating &&
        _state != _VoiceState.transcribing;
    final canSave = _state == _VoiceState.reportReady;

    return Row(
      children: [
        // Patient ID input
        SizedBox(
          width: 240,
          child: TextField(
            controller: _patientIdCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Patient ID / MRN',
              isDense: true,
              prefixIcon: const Icon(Icons.badge_outlined, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 10),
              suffixIcon: IconButton(
                tooltip: 'Confirm patient ID',
                icon: const Icon(Icons.check_rounded, size: 18),
                onPressed: () => _setPatientIdManually(_patientIdCtrl.text),
              ),
            ),
            style: const TextStyle(fontSize: 13),
            onSubmitted: _setPatientIdManually,
          ),
        ),
        const SizedBox(width: 12),
        // Record controls
        _btn(
          icon: Icons.fiber_manual_record_rounded,
          label: 'Start',
          color: AppColors.error,
          onTap: canStart ? _startRecording : null,
          filled: true,
        ),
        const SizedBox(width: 6),
        _btn(
          icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          label: isPaused ? 'Resume' : 'Pause',
          color: AppColors.warning,
          onTap: isRecording
              ? _pauseRecording
              : (isPaused ? _resumeRecording : null),
        ),
        const SizedBox(width: 6),
        _btn(
          icon: Icons.stop_rounded,
          label: 'Stop',
          color: AppColors.primary,
          onTap: (isRecording || isPaused) ? _stopRecording : null,
        ),
        const SizedBox(width: 6),
        _btn(
          icon: Icons.auto_awesome,
          label: 'Generate',
          color: AppColors.info,
          onTap: canGenerate ? _generateReport : null,
        ),
        const Spacer(),
        _btn(
          icon: Icons.delete_outline_rounded,
          label: 'Discard',
          color: AppColors.textHint,
          onTap: _state == _VoiceState.reportReady ||
                  _state == _VoiceState.saved
              ? _reset
              : null,
        ),
        const SizedBox(width: 6),
        _btn(
          icon: Icons.save_rounded,
          label: 'Save',
          color: AppColors.success,
          onTap: canSave ? _saveReport : null,
          filled: true,
        ),
      ],
    );
  }

  Widget _btn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    final disabled = onTap == null;
    final bg = filled
        ? (disabled ? AppColors.textHint.withOpacity(0.2) : color)
        : Colors.transparent;
    final fg = filled
        ? Colors.white
        : (disabled ? AppColors.textHint : color);
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: filled
                  ? null
                  : Border.all(
                      color: disabled ? AppColors.border : color, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _listeningIndicator() {
    return StreamBuilder<String>(
      stream: _voice.status,
      builder: (context, snap) {
        final listening = _voice.isListening;
        return Row(
          children: [
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) => Transform.scale(
                scale: listening ? _pulseAnim.value : 1,
                child: child,
              ),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: listening ? AppColors.success : AppColors.textHint,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(listening ? 'Listening' : 'Idle',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }

  // left panel: big state visual + status
  Widget _leftPanel() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stateCard(),
          const SizedBox(height: 20),
          Expanded(child: _recordingsList()),
        ],
      ),
    );
  }

  Widget _stateCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _stateVisual(),
          const SizedBox(height: 16),
          Text(_statusMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_state == _VoiceState.recording ||
              _state == _VoiceState.paused)
            _liveTranscriptPanel()
          else if (_liveTranscript.isNotEmpty)
            Text('"${_liveTranscript.toLowerCase()}"',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          if (_state == _VoiceState.confirmingPatientId) ...[
            const SizedBox(height: 12),
            _idChip(_candidatePatientId),
          ],
          if (_confirmedPatientId.isNotEmpty &&
              _state != _VoiceState.awaitingPatientId &&
              _state != _VoiceState.confirmingPatientId) ...[
            const SizedBox(height: 8),
            _idChip(_confirmedPatientId, confirmed: true),
          ],
        ],
      ),
    );
  }

  Widget _liveTranscriptPanel() {
    final finalText = _liveFinal.trim();
    final partial = _livePartial.trim();
    final hasAny = finalText.isNotEmpty || partial.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 56, maxHeight: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: hasAny
            ? RichText(
                textAlign: TextAlign.left,
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textPrimary,
                  ),
                  children: [
                    if (finalText.isNotEmpty)
                      TextSpan(text: finalText),
                    if (finalText.isNotEmpty && partial.isNotEmpty)
                      const TextSpan(text: ' '),
                    if (partial.isNotEmpty)
                      TextSpan(
                        text: partial,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              )
            : Text(
                _state == _VoiceState.paused
                    ? 'Paused — speech not captured while paused.'
                    : 'Listening… start speaking.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
      ),
    );
  }

  Widget _stateVisual() {
    switch (_state) {
      case _VoiceState.recording:
      case _VoiceState.paused:
        return SizedBox(
          height: 60,
          child: CustomPaint(
            painter: _WaveformPainter(
              data: _waveform,
              color: _state == _VoiceState.paused
                  ? AppColors.warning
                  : AppColors.error,
            ),
            size: const Size(double.infinity, 60),
          ),
        );
      case _VoiceState.transcribing:
      case _VoiceState.generating:
        return const SizedBox(
          height: 60,
          child: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        );
      default:
        return AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Transform.scale(
            scale: _pulseAnim.value,
            child: child,
          ),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _stateColor().withOpacity(0.15),
            ),
            child: Icon(_stateIcon(), size: 30, color: _stateColor()),
          ),
        );
    }
  }

  Color _stateColor() {
    switch (_state) {
      case _VoiceState.awaitingPatientId:
      case _VoiceState.confirmingPatientId:
        return AppColors.info;
      case _VoiceState.readyToRecord:
        return AppColors.primary;
      case _VoiceState.reportReady:
        return AppColors.success;
      case _VoiceState.saved:
        return AppColors.completed;
      default:
        return AppColors.primary;
    }
  }

  IconData _stateIcon() {
    switch (_state) {
      case _VoiceState.awaitingPatientId:
        return Icons.badge_outlined;
      case _VoiceState.confirmingPatientId:
        return Icons.check_circle_outline;
      case _VoiceState.readyToRecord:
        return Icons.mic_none_rounded;
      case _VoiceState.reportReady:
        return Icons.description_outlined;
      case _VoiceState.saved:
        return Icons.check_circle_rounded;
      default:
        return Icons.mic_rounded;
    }
  }

  Widget _idChip(String id, {bool confirmed = false}) {
    final color = confirmed ? AppColors.success : AppColors.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(confirmed ? Icons.check_rounded : Icons.badge_outlined,
              size: 16, color: color),
          const SizedBox(width: 6),
          Text(id,
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
        ],
      ),
    );
  }

  Widget _recordingsList() {
    if (_recordings.isEmpty && _dictationText.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq_rounded,
                size: 40, color: AppColors.textHint.withOpacity(0.5)),
            const SizedBox(height: 8),
            Text('Dictation transcript will appear here',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.text_snippet_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text('Transcript',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 6),
                if (_recordings.isNotEmpty)
                  Text('· ${_recordings.length} clip(s)',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 10),
            Text(_dictationText.isEmpty ? '…' : _dictationText,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  // right panel: generated report preview
  Widget _rightPanel() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(24),
      child: _workingReport == null
          ? _emptyReport()
          : _reportPreview(_workingReport!),
    );
  }

  Widget _emptyReport() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined,
              size: 48, color: AppColors.textHint.withOpacity(0.5)),
          const SizedBox(height: 8),
          Text('Generated report will appear here',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _reportPreview(PathologyReport r) {
    final fmt = DateFormat('dd-MM-yyyy hh:mm a');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text('DEPARTMENT OF LABORATORY MEDICINE',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4)),
            ),
            const SizedBox(height: 12),
            _infoGrid(r, fmt),
            const Divider(height: 24),
            const Center(
              child: Text('HISTOPATHOLOGY REPORT',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.underline)),
            ),
            const SizedBox(height: 10),
            _line('LAB NUMBER', r.reportNumber),
            _section('CLINICAL INFORMATION', r.clinicalInformation),
            _section('SPECIMEN', r.specimen),
            _section('GROSS EXAMINATION', r.grossExamination),
            _section('MICROSCOPY AND IMPRESSION', r.microscopyImpression),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(r.pathologistName,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(r.pathologistRegistration,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoGrid(PathologyReport r, DateFormat fmt) {
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(l,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const Text(': '),
              Expanded(
                child: Text(v, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('Name', r.patientName.isEmpty ? '—' : r.patientName),
              row('MRN', r.mrn.isEmpty ? r.patientId : r.mrn),
              row('Age', r.patientAge > 0 ? 'Y ${r.patientAge} Y' : '—'),
              row('Ordered by', r.orderedBy.isEmpty ? '—' : r.orderedBy),
              row('Referred by', r.referredBy.isEmpty ? '—' : r.referredBy),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('Lab No', r.labNo.isEmpty ? '—' : r.labNo),
              row('Visit No', r.visitNo.isEmpty ? '—' : r.visitNo),
              row('Gender', r.patientGender.isEmpty ? '—' : r.patientGender),
              row('Sample Receipt', fmt.format(r.sampleReceiptDate)),
              row('Reported', fmt.format(r.reportedDate)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const Text(': '),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _section(String label, String body) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body, style: const TextStyle(fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }

  // bottom command hints (contextual)
  Widget _commandHints() {
    final phrases = SettingsService.getPhrases();
    final hints = <String>[];
    switch (_state) {
      case _VoiceState.awaitingPatientId:
        hints.add('"${_first(phrases[VoiceCommand.patientId.key])} LR 035643"');
        break;
      case _VoiceState.confirmingPatientId:
        hints.add('"${_first(phrases[VoiceCommand.confirm.key])}"');
        hints.add('"${_first(phrases[VoiceCommand.cancel.key])}"');
        break;
      case _VoiceState.readyToRecord:
        hints.add('"${_first(phrases[VoiceCommand.start.key])}"');
        break;
      case _VoiceState.recording:
        hints.add('"${_first(phrases[VoiceCommand.pause.key])}"');
        hints.add('"${_first(phrases[VoiceCommand.stop.key])}"');
        break;
      case _VoiceState.paused:
        hints.add('"${_first(phrases[VoiceCommand.resume.key])}"');
        hints.add('"${_first(phrases[VoiceCommand.stop.key])}"');
        break;
      case _VoiceState.reportReady:
        hints.add('"${_first(phrases[VoiceCommand.save.key])}"');
        hints.add('"${_first(phrases[VoiceCommand.discard.key])}"');
        break;
      case _VoiceState.saved:
        hints.add('"${_first(phrases[VoiceCommand.newReport.key])}"');
        hints.add('"${_first(phrases[VoiceCommand.dashboard.key])}"');
        break;
      case _VoiceState.transcribing:
      case _VoiceState.generating:
        hints.add('processing…');
        break;
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

  String _first(String? phrases) {
    if (phrases == null || phrases.isEmpty) return '';
    return phrases.split('|').first.trim();
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  _WaveformPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final w = size.width / data.length;
    for (var i = 0; i < data.length; i++) {
      final x = i * w + w / 2;
      final h = data[i] * size.height;
      canvas.drawLine(Offset(x, (size.height - h) / 2),
          Offset(x, (size.height + h) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.data != data || old.color != color;
}

// Silence analyzer unused; keep a reference so dart:io import is needed
// when the file is trimmed.
// ignore: unused_element
File _unused(String p) => File(p);
