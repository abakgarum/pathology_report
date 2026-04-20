import 'dart:async';
import 'package:flutter/material.dart';
import '../models/report_models.dart';
import '../services/audio_service.dart';
import '../services/gemini_service.dart';
import '../services/stt_service.dart';
import '../theme/app_theme.dart';
import '../widgets/audio_player_widget.dart';

class VoiceReportScreen extends StatefulWidget {
  final PathologyReport? existingReport;
  final ValueChanged<PathologyReport>? onReportSaved;

  const VoiceReportScreen({
    super.key,
    this.existingReport,
    this.onReportSaved,
  });

  @override
  State<VoiceReportScreen> createState() => _VoiceReportScreenState();
}

class _VoiceReportScreenState extends State<VoiceReportScreen>
    with TickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  final ScrollController _transcriptScrollCtrl = ScrollController();

  // State
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isGenerating = false;
  bool _showRawTranscript = false;
  Duration _recordingDuration = Duration.zero;
  final List<double> _waveformData = [];

  // Data
  final List<VoiceRecording> _recordings = [];
  final Set<String> _transcribingIds = {};
  String _fullTranscript = '';
  Map<String, String>? _generatedReport;
  String _generatedSummary = '';
  bool _reportGenerated = false;

  // Patient quick-fill
  final _patientNameCtrl = TextEditingController();
  final _patientAgeCtrl = TextEditingController();
  String _selectedGender = 'Male';

  // Speech-to-text provider selection
  SttProvider _sttProvider = SttProvider.whisper;

  // Streaming (live translation)
  bool _streamEnabled = false;
  static const Duration _chunkInterval = Duration(seconds: 5);
  Timer? _chunkTimer;
  final List<_LiveChunk> _liveChunks = [];
  int _liveChunksInFlight = 0;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _audioService.durationStream.listen((d) {
      if (mounted) setState(() => _recordingDuration = d);
    });

    _audioService.amplitudeStream.listen((a) {
      if (mounted) {
        setState(() {
          if (_waveformData.length > 100) _waveformData.removeAt(0);
          _waveformData.add(a);
        });
      }
    });
  }

  @override
  void dispose() {
    _chunkTimer?.cancel();
    _pulseController.dispose();
    _audioService.dispose();
    _transcriptScrollCtrl.dispose();
    _patientNameCtrl.dispose();
    _patientAgeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Top bar
          _buildTopBar(context),
          // Main content
          Expanded(
            child: isWide
                ? Row(
                    children: [
                      // Left: Recording + Transcript
                      Expanded(flex: 5, child: _buildRecordingPanel()),
                      const VerticalDivider(width: 1),
                      // Right: Generated Report
                      Expanded(flex: 5, child: _buildReportPanel()),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildRecordingPanel(),
                        const Divider(height: 1),
                        _buildReportPanel(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Voice Report',
                  style: Theme.of(context).textTheme.titleLarge),
              Text('Dictate and auto-generate pathology reports',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const Spacer(),
          _buildStreamToggle(),
          const SizedBox(width: 10),
          _buildSttProviderSelector(),
          const SizedBox(width: 12),
          if (_reportGenerated)
            ElevatedButton.icon(
              onPressed: _saveReport,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
            ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _fullTranscript.isNotEmpty ? _generateFullReport : null,
            icon: _isGenerating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(_isGenerating ? 'Generating...' : 'Generate Report'),
          ),
        ],
      ),
    );
  }

  // ─── LEFT PANEL: Recording + Live Transcript ───────────────────

  Widget _buildRecordingPanel() {
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          // Patient quick info bar
          _buildPatientQuickBar(),
          // Recording controls
          Expanded(child: _buildRecordingArea()),
          // Transcript area
          Expanded(flex: 2, child: _buildTranscriptArea()),
        ],
      ),
    );
  }

  Widget _buildPatientQuickBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _patientNameCtrl,
              decoration: const InputDecoration(
                hintText: 'Patient Name',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: TextField(
              controller: _patientAgeCtrl,
              decoration: const InputDecoration(
                hintText: 'Age',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Male', label: Text('M')),
              ButtonSegment(value: 'Female', label: Text('F')),
            ],
            selected: {_selectedGender},
            onSelectionChanged: (v) =>
                setState(() => _selectedGender = v.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle:
                  WidgetStatePropertyAll(Theme.of(context).textTheme.bodySmall),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isRecording
              ? AppColors.error.withOpacity(0.5)
              : AppColors.border,
          width: _isRecording ? 2 : 1,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          // Waveform or idle state
          if (_isRecording || _isPaused) ...[
            // Live waveform
            SizedBox(
              height: 60,
              child: CustomPaint(
                size: const Size(double.infinity, 60),
                painter: _WaveformPainter(
                  data: _waveformData,
                  color: _isPaused ? AppColors.warning : AppColors.error,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Duration
            Text(
              _formatDuration(_recordingDuration),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontFamily: 'monospace',
                    color: _isPaused ? AppColors.warning : AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              _isPaused ? 'PAUSED' : 'RECORDING',
              style: TextStyle(
                color: _isPaused ? AppColors.warning : AppColors.error,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ] else ...[
            Icon(
              Icons.mic_none_rounded,
              size: 40,
              color: AppColors.textHint.withOpacity(0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the mic to start dictating',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_recordings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_recordings.length} recording(s) captured',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.success,
                      ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isRecording || _isPaused) ...[
                // Pause/Resume
                _ControlButton(
                  icon: _isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  label: _isPaused ? 'Resume' : 'Pause',
                  color: AppColors.warning,
                  onTap: _isPaused ? _resumeRecording : _pauseRecording,
                ),
                const SizedBox(width: 20),
                // Stop
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isRecording ? _pulseAnimation.value : 1.0,
                      child: child,
                    );
                  },
                  child: _ControlButton(
                    icon: Icons.stop_rounded,
                    label: 'Stop & Save',
                    color: AppColors.error,
                    onTap: _stopRecording,
                    large: true,
                  ),
                ),
                const SizedBox(width: 20),
                // Discard
                _ControlButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Discard',
                  color: AppColors.textHint,
                  onTap: _discardRecording,
                ),
              ] else ...[
                // Start recording
                _ControlButton(
                  icon: Icons.mic_rounded,
                  label: 'Start Recording',
                  color: AppColors.primary,
                  onTap: _startRecording,
                  large: true,
                ),
              ],
            ],
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscriptArea() {
    final streaming = _streamEnabled && (_isRecording || _liveChunks.isNotEmpty);
    final liveDoneCount = _liveChunks
        .where((c) => c.status == _LiveChunkStatus.done)
        .length;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: streaming
              ? AppColors.error.withOpacity(0.35)
              : AppColors.border,
          width: streaming ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: const Border(
                  bottom: BorderSide(color: AppColors.border)),
              gradient: streaming
                  ? LinearGradient(
                      colors: [
                        AppColors.error.withOpacity(0.05),
                        AppColors.primary.withOpacity(0.02),
                      ],
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  streaming
                      ? Icons.graphic_eq_rounded
                      : Icons.text_snippet_outlined,
                  size: 18,
                  color: streaming ? AppColors.error : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  streaming ? 'Live Translation' : 'Live Transcript',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (streaming) ...[
                  const SizedBox(width: 10),
                  _LivePulseDot(animation: _pulseAnimation),
                  const SizedBox(width: 4),
                  Text('LIVE',
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      )),
                ],
                const Spacer(),
                if (streaming) ...[
                  _MiniChip(
                    icon: Icons.bolt_rounded,
                    label: '$liveDoneCount',
                    tooltip: 'Chunks transcribed',
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  if (_liveChunksInFlight > 0)
                    _MiniChip(
                      icon: Icons.sync_rounded,
                      label: '$_liveChunksInFlight',
                      tooltip: 'Chunks in flight',
                      color: AppColors.primary,
                      spinning: true,
                    ),
                ],
                if (!streaming && _fullTranscript.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: () => setState(
                        () => _showRawTranscript = !_showRawTranscript),
                    icon: Icon(
                      _showRawTranscript
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 16,
                    ),
                    label: Text(_showRawTranscript ? 'Hide Raw' : 'Show Raw'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy transcript',
                    onPressed: () {},
                  ),
                ],
              ],
            ),
          ),
          // Body
          Expanded(
            child: (_fullTranscript.isEmpty &&
                    !_isRecording &&
                    _liveChunks.isEmpty)
                ? _buildTranscriptEmptyState()
                : SingleChildScrollView(
                    controller: _transcriptScrollCtrl,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Live stream panel (top, sticky feel)
                        if (streaming) _buildLiveStreamPanel(),
                        if (streaming && _recordings.isNotEmpty)
                          const SizedBox(height: 16),

                        // Completed recordings
                        ..._recordings.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final rec = entry.value;
                          return _RecordingTranscriptTile(
                            index: idx + 1,
                            recording: rec,
                            onPlayTap: () => _playRecording(rec),
                          );
                        }),

                        // Batch-mode status tiles
                        if (!_streamEnabled && _isRecording)
                          _StatusTile(
                            color: AppColors.error,
                            label: _isPaused
                                ? 'Recording paused'
                                : 'Recording… transcript will appear after you stop',
                            showSpinner: false,
                          ),
                        if (_transcribingIds.isNotEmpty)
                          _StatusTile(
                            color: AppColors.primary,
                            label:
                                'Transcribing with ${_sttProvider.shortLabel} (${_transcribingIds.length})…',
                            showSpinner: true,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _streamEnabled
                ? Icons.graphic_eq_rounded
                : Icons.record_voice_over_outlined,
            size: 36,
            color: AppColors.textHint.withOpacity(0.4),
          ),
          const SizedBox(height: 10),
          Text(
            _streamEnabled
                ? 'Live mode is ON — transcripts appear every ${_chunkInterval.inSeconds}s while you speak'
                : 'Your dictation will appear here after you stop',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textHint,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStreamPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.error.withOpacity(0.04),
            AppColors.primary.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LivePulseDot(animation: _pulseAnimation),
              const SizedBox(width: 8),
              Text(
                'Streaming via ${_sttProvider.shortLabel}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
              ),
              const Spacer(),
              Text(
                _formatDuration(_recordingDuration),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_liveChunks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.error),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Listening — first chunk in ${_chunkInterval.inSeconds}s…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 0,
              runSpacing: 4,
              children: _liveChunks
                  .asMap()
                  .entries
                  .map((e) => _LiveChunkSpan(
                        index: e.key + 1,
                        chunk: e.value,
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  // ─── RIGHT PANEL: Generated Report ─────────────────────────────

  Widget _buildReportPanel() {
    return Container(
      color: AppColors.background,
      child: _reportGenerated && _generatedReport != null
          ? _buildGeneratedReportView()
          : _buildReportPlaceholder(),
    );
  }

  Widget _buildReportPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 48,
                color: AppColors.primary.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Report Preview',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.textHint,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Record your findings, then click "Generate Report"\nto create a structured pathology report with AI.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textHint,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 24),
            // Workflow steps
            _WorkflowStep(number: '1', text: 'Dictate your findings'),
            _WorkflowStep(number: '2', text: 'Review the live transcript'),
            _WorkflowStep(number: '3', text: 'Click Generate Report'),
            _WorkflowStep(number: '4', text: 'Review, edit & save'),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratedReportView() {
    final r = _generatedReport!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withOpacity(0.08),
                  AppColors.primary.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: AppColors.success, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'AI-Generated Summary',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.success,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  r['summary'] ?? _generatedSummary,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Patient
          _ReportSection(
            title: 'Patient Information',
            icon: Icons.person_rounded,
            fields: {
              'Name': r['patient_name'] ?? _patientNameCtrl.text,
              'Age': r['patient_age'] ?? _patientAgeCtrl.text,
              'Gender': r['patient_gender'] ?? _selectedGender,
              'Referring Doctor': r['referring_doctor'] ?? '',
              'Hospital ID': r['hospital_id'] ?? '',
            },
          ),
          const SizedBox(height: 12),

          // Specimen
          _ReportSection(
            title: 'Specimen Details',
            icon: Icons.science_rounded,
            fields: {
              'Type': r['specimen_type'] ?? '',
              'Site': r['specimen_site'] ?? '',
              'Clinical History': r['clinical_history'] ?? '',
              'Gross Description': r['gross_description'] ?? '',
            },
          ),
          const SizedBox(height: 12),

          // Findings
          _ReportSection(
            title: 'Pathology Findings',
            icon: Icons.biotech_rounded,
            fields: {
              'Microscopic Description': r['microscopic_description'] ?? '',
              'Diagnosis': r['diagnosis'] ?? '',
              'Grade': r['grade'] ?? '',
              'Stage': r['stage'] ?? '',
            },
            highlightField: 'Diagnosis',
          ),
          const SizedBox(height: 12),

          // Additional
          if ((r['immunohistochemistry'] ?? '').isNotEmpty ||
              (r['special_stains'] ?? '').isNotEmpty ||
              (r['molecular_studies'] ?? '').isNotEmpty)
            _ReportSection(
              title: 'Additional Studies',
              icon: Icons.hub_rounded,
              fields: {
                'IHC': r['immunohistochemistry'] ?? '',
                'Special Stains': r['special_stains'] ?? '',
                'Molecular Studies': r['molecular_studies'] ?? '',
              },
            ),

          if ((r['comments'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            _ReportSection(
              title: 'Comments',
              icon: Icons.comment_rounded,
              fields: {'': r['comments']!},
            ),
          ],

          const SizedBox(height: 16),

          // Raw transcript toggle
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: ExpansionTile(
              leading: const Icon(Icons.record_voice_over_outlined,
                  color: AppColors.warning, size: 20),
              title: Text('Raw Voice Transcript',
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(
                  '${_recordings.length} recording(s) — tap to review',
                  style: Theme.of(context).textTheme.bodySmall),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: _recordings.asMap().entries.map((entry) {
                      final rec = entry.value;
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.play_circle_filled,
                                    color: AppColors.primary, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Recording ${entry.key + 1} — ${_formatDuration(rec.duration)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontSize: 13),
                                ),
                                const Spacer(),
                                Text(
                                  'Tap to play',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.primary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              rec.transcription,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    height: 1.5,
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ─── Actions ───────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final path = _streamEnabled
        ? await _audioService.startStreamRecording()
        : await _audioService.startRecording();
    if (path != null) {
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _waveformData.clear();
        if (_streamEnabled) {
          _liveChunks.clear();
        }
      });
      if (_streamEnabled) {
        _chunkTimer = Timer.periodic(_chunkInterval, (_) => _rotateChunk());
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Microphone permission required. Please grant access in System Settings.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  Future<void> _rotateChunk() async {
    if (!_isRecording || _isPaused) return;
    final finishedPath = await _audioService.rotateRecording();
    if (finishedPath == null || finishedPath.isEmpty) return;
    _transcribeLiveChunk(finishedPath);
  }

  void _transcribeLiveChunk(String filePath) {
    final chunk = _LiveChunk(filePath: filePath);
    setState(() {
      _liveChunks.add(chunk);
      _liveChunksInFlight++;
    });

    () async {
      try {
        final text = await SttService.transcribe(filePath, _sttProvider);
        if (!mounted) return;
        setState(() {
          chunk.text = text.trim();
          chunk.status = _LiveChunkStatus.done;
          _liveChunksInFlight =
              (_liveChunksInFlight - 1).clamp(0, 1 << 30);
        });
        _autoScrollTranscript();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          chunk.status = _LiveChunkStatus.failed;
          chunk.text = '(failed: $e)';
          _liveChunksInFlight =
              (_liveChunksInFlight - 1).clamp(0, 1 << 30);
        });
      }
    }();
  }

  void _autoScrollTranscript() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_transcriptScrollCtrl.hasClients) {
        _transcriptScrollCtrl.animateTo(
          _transcriptScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pauseRecording() async {
    await _audioService.pauseRecording();
    setState(() {
      _isPaused = true;
      _isRecording = true;
    });
  }

  Future<void> _resumeRecording() async {
    await _audioService.resumeRecording();
    setState(() {
      _isPaused = false;
      _isRecording = true;
    });
  }

  Future<void> _stopRecording() async {
    if (_streamEnabled) {
      await _stopStreamRecording();
      return;
    }

    final path = await _audioService.stopRecording();
    final duration = _recordingDuration;

    final recording = VoiceRecording(
      filePath: path ?? '',
      transcription: '',
      duration: duration,
      label: 'Recording ${_recordings.length + 1}',
    );

    setState(() {
      _isRecording = false;
      _isPaused = false;
      _recordings.add(recording);
      _transcribingIds.add(recording.id);
      _recordingDuration = Duration.zero;
      _waveformData.clear();
    });

    _transcribeRecording(recording);
  }

  Future<void> _stopStreamRecording() async {
    _chunkTimer?.cancel();
    _chunkTimer = null;

    final finalPath = await _audioService.stopRecording();
    final duration = _recordingDuration;

    // Transcribe the trailing chunk (from last rotation to stop).
    if (finalPath != null && finalPath.isNotEmpty) {
      _transcribeLiveChunk(finalPath);
    }

    setState(() {
      _isRecording = false;
      _isPaused = false;
      _recordingDuration = Duration.zero;
      _waveformData.clear();
    });

    // Wait for remaining chunks to finish, then fold the session into a
    // single VoiceRecording entry (matches batch-mode UX).
    await _finalizeStreamSession(duration);
  }

  Future<void> _finalizeStreamSession(Duration totalDuration) async {
    // Poll briefly for in-flight chunks (capped, so UI never hangs).
    for (int i = 0; i < 60 && _liveChunksInFlight > 0; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return;

    final combined = _liveChunks
        .where((c) => c.status == _LiveChunkStatus.done && c.text.isNotEmpty)
        .map((c) => c.text)
        .join(' ')
        .trim();

    final recording = VoiceRecording(
      filePath: _liveChunks.isNotEmpty ? _liveChunks.last.filePath : '',
      transcription: combined,
      duration: totalDuration,
      label: 'Recording ${_recordings.length + 1}',
    );

    setState(() {
      _recordings.add(recording);
      _fullTranscript = _recordings
          .where((r) => r.transcription.isNotEmpty)
          .map((r) => r.transcription)
          .join('\n\n');
      _liveChunks.clear();
    });
  }

  Widget _buildStreamToggle() {
    final active = _streamEnabled;
    final enabled = !_isRecording && !_isPaused;
    return Tooltip(
      message: active
          ? 'Live streaming transcription — transcripts appear every ${_chunkInterval.inSeconds}s while you speak'
          : 'Batch mode — full transcript appears after you stop',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? AppColors.error.withOpacity(0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.error.withOpacity(0.45) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, _) {
                return Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? AppColors.error.withOpacity(
                            0.4 + 0.6 * ((_pulseAnimation.value - 1.0) / 0.3))
                        : AppColors.textHint.withOpacity(0.4),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            Text(
              active ? 'LIVE' : 'Live',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: active ? AppColors.error : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: active ? 1.2 : 0.2,
                  ),
            ),
            const SizedBox(width: 6),
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: active,
                onChanged: enabled
                    ? (v) => setState(() => _streamEnabled = v)
                    : null,
                activeColor: AppColors.error,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSttProviderSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.graphic_eq_rounded,
              size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            'STT:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<SttProvider>(
              value: _sttProvider,
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              style: Theme.of(context).textTheme.bodyMedium,
              items: SttProvider.values
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(p.label),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _sttProvider = v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _transcribeRecording(VoiceRecording recording) async {
    try {
      final text = await SttService.transcribe(recording.filePath, _sttProvider);
      if (!mounted) return;

      setState(() {
        final idx = _recordings.indexWhere((r) => r.id == recording.id);
        if (idx != -1) {
          _recordings[idx] = _recordings[idx].copyWith(transcription: text);
        }
        _transcribingIds.remove(recording.id);
        _fullTranscript = _recordings
            .where((r) => r.transcription.isNotEmpty)
            .map((r) => r.transcription)
            .join('\n\n');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _transcribingIds.remove(recording.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Transcription failed: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _discardRecording() async {
    _chunkTimer?.cancel();
    _chunkTimer = null;
    await _audioService.stopRecording();
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _recordingDuration = Duration.zero;
      _waveformData.clear();
      _liveChunks.clear();
      _liveChunksInFlight = 0;
    });
  }

  void _playRecording(VoiceRecording rec) {
    // Show audio player in a modal bottom sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: AudioPlayerWidget(
          filePath: rec.filePath,
          title: rec.label,
          onClose: () => Navigator.pop(context),
        ),
      ),
    );
  }

  Future<void> _generateFullReport() async {
    if (_fullTranscript.isEmpty) return;

    setState(() => _isGenerating = true);

    try {
      final patientContext = _patientNameCtrl.text.isNotEmpty
          ? 'Patient: ${_patientNameCtrl.text}, Age: ${_patientAgeCtrl.text}, Gender: $_selectedGender'
          : '';

      final result = await GeminiService.generateReportFromTranscript(
        _fullTranscript,
        patientContext: patientContext,
      );

      setState(() {
        _generatedReport = result;
        _generatedSummary = result['summary'] ?? '';
        _reportGenerated = true;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating report: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  void _saveReport() {
    if (_generatedReport == null) return;
    final r = _generatedReport!;

    final report = PathologyReport(
      reportNumber:
          'PATH-2026-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      patient: Patient(
        name: r['patient_name']?.isNotEmpty == true
            ? r['patient_name']!
            : _patientNameCtrl.text,
        age: int.tryParse(r['patient_age'] ?? _patientAgeCtrl.text) ?? 0,
        gender: r['patient_gender']?.isNotEmpty == true
            ? r['patient_gender']!
            : _selectedGender,
        referringDoctor: r['referring_doctor'] ?? '',
        hospitalId: r['hospital_id'] ?? '',
      ),
      specimen: Specimen(
        type: SpecimenType.biopsy,
        site: r['specimen_site'] ?? '',
        collectionDate: '',
        receivedDate: '',
        clinicalHistory: r['clinical_history'] ?? '',
        grossDescription: r['gross_description'] ?? '',
      ),
      findings: PathologyFinding(
        microscopicDescription: r['microscopic_description'] ?? '',
        diagnosis: r['diagnosis'] ?? '',
        grade: r['grade'] ?? '',
        stage: r['stage'] ?? '',
        immunohistochemistry: r['immunohistochemistry'] ?? '',
        specialStains: r['special_stains'] ?? '',
        molecularStudies: r['molecular_studies'] ?? '',
        comments: r['comments'] ?? '',
      ),
      status: ReportStatus.completed,
      pathologistName: 'Dr. Anand Patel',
      summary: _generatedSummary,
      voiceRecordings: _recordings,
      rawTranscript: _fullTranscript,
    );

    widget.onReportSaved?.call(report);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Report saved successfully!'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

// ─── Supporting Widgets ─────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool large;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color.withOpacity(0.1),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: large ? 64 : 48,
              height: large ? 64 : 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.3), width: 2),
              ),
              child: Icon(icon, color: color, size: large ? 30 : 22),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RecordingTranscriptTile extends StatelessWidget {
  final int index;
  final VoiceRecording recording;
  final VoidCallback onPlayTap;

  const _RecordingTranscriptTile({
    required this.index,
    required this.recording,
    required this.onPlayTap,
  });

  @override
  Widget build(BuildContext context) {
    final minutes =
        recording.duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        recording.duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: onPlayTap,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: AppColors.primary, size: 18),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Recording $index',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$minutes:$seconds',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.check_circle, color: AppColors.success, size: 16),
              const SizedBox(width: 4),
              Text('Transcribed',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.success,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            recording.transcription,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                  color: AppColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  final String number;
  final String text;

  const _WorkflowStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Map<String, String> fields;
  final String? highlightField;

  const _ReportSection({
    required this.title,
    required this.icon,
    required this.fields,
    this.highlightField,
  });

  @override
  Widget build(BuildContext context) {
    final nonEmptyFields =
        Map.fromEntries(fields.entries.where((e) => e.value.isNotEmpty));
    if (nonEmptyFields.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 12),
          ...nonEmptyFields.entries.map((e) {
            final isHighlight = e.key == highlightField;
            if (e.key.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(e.value,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(height: 1.5)),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      e.key,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: isHighlight
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              e.value,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                            ),
                          )
                        : Text(
                            e.value,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(height: 1.5),
                          ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
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
      ..color = color.withOpacity(0.6)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final barWidth = size.width / 60;
    final displayData =
        data.length > 60 ? data.sublist(data.length - 60) : data;

    for (int i = 0; i < displayData.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final barHeight = displayData[i] * size.height * 0.8;
      final y1 = size.height / 2 - barHeight / 2;
      final y2 = size.height / 2 + barHeight / 2;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}

class _StatusTile extends StatelessWidget {
  final Color color;
  final String label;
  final bool showSpinner;

  const _StatusTile({
    required this.color,
    required this.label,
    required this.showSpinner,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: showSpinner
                ? CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Live streaming helpers ────────────────────────────────────

enum _LiveChunkStatus { pending, done, failed }

class _LiveChunk {
  final String filePath;
  String text = '';
  _LiveChunkStatus status = _LiveChunkStatus.pending;

  _LiveChunk({required this.filePath});
}

class _LivePulseDot extends StatelessWidget {
  final Animation<double> animation;
  const _LivePulseDot({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = ((animation.value - 1.0) / 0.3).clamp(0.0, 1.0);
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 14 + 6 * t,
              height: 14 + 6 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withOpacity(0.18 * (1 - t)),
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MiniChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;
  final bool spinning;

  const _MiniChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.color,
    this.spinning = false,
  });

  @override
  State<_MiniChip> createState() => _MiniChipState();
}

class _MiniChipState extends State<_MiniChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.spinning) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _MiniChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.spinning && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: widget.color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _spin,
              child: Icon(widget.icon, size: 12, color: widget.color),
            ),
            const SizedBox(width: 4),
            Text(
              widget.label,
              style: TextStyle(
                color: widget.color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveChunkSpan extends StatelessWidget {
  final int index;
  final _LiveChunk chunk;

  const _LiveChunkSpan({required this.index, required this.chunk});

  @override
  Widget build(BuildContext context) {
    switch (chunk.status) {
      case _LiveChunkStatus.pending:
        return Container(
          margin: const EdgeInsets.only(right: 6, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'chunk $index',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      case _LiveChunkStatus.failed:
        return Container(
          margin: const EdgeInsets.only(right: 6, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 12, color: AppColors.error),
              const SizedBox(width: 4),
              Text(
                'chunk $index failed',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        );
      case _LiveChunkStatus.done:
        return _FadeInText(text: '${chunk.text} ');
    }
  }
}

class _FadeInText extends StatefulWidget {
  final String text;
  const _FadeInText({required this.text});

  @override
  State<_FadeInText> createState() => _FadeInTextState();
}

class _FadeInTextState extends State<_FadeInText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Text(
        widget.text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.55,
              color: AppColors.textPrimary,
            ),
      ),
    );
  }
}
