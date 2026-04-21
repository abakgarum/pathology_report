import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../services/voice_command_service.dart';
import '../theme/app_theme.dart';

/// In-app manual: step-by-step walkthrough of the voice + tap workflow,
/// plus a live list of the user's currently-configured trigger phrases so
/// they can see exactly what to say.
class GuideScreen extends StatelessWidget {
  final VoidCallback? onBack;
  const GuideScreen({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _heroCard(context),
                        const SizedBox(height: 20),
                        _quickStart(context),
                        const SizedBox(height: 20),
                        _workflowCard(context),
                        const SizedBox(height: 20),
                        _commandsCard(context),
                        const SizedBox(height: 20),
                        _patientIdCard(context),
                        const SizedBox(height: 20),
                        _reportViewCard(context),
                        const SizedBox(height: 20),
                        _settingsCard(context),
                        const SizedBox(height: 20),
                        _troubleshootCard(context),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          const Icon(Icons.menu_book_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Text('Guide',
              style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          Text('PathLab Pro · Voice-first',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  // ─── Hero ───────────────────────────────────────────────

  Widget _heroCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.record_voice_over_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create pathology reports by speaking',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  'Dictate to generate template-formatted reports offline. '
                  'Every action has a voice command AND a button — use whichever you prefer.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withOpacity(0.95)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Quick start ────────────────────────────────────────

  Widget _quickStart(BuildContext context) {
    final phrases = SettingsService.getPhrases();
    String first(VoiceCommand c) =>
        (phrases[c.key] ?? '').split('|').first.trim();

    return _sectionCard(
      context: context,
      icon: Icons.rocket_launch_rounded,
      title: '60-second quick start',
      children: [
        _step(1, 'Say a wake command',
            'From Home, say "${first(VoiceCommand.newReport)}" or click "New Voice Report".'),
        _step(2, 'Speak the patient ID',
            'Example: "${first(VoiceCommand.patientId)} L R zero three five six four three". Then say "${first(VoiceCommand.confirm)}". You can also type it in the top bar.'),
        _step(3, 'Dictate the report',
            'Say "${first(VoiceCommand.start)}", read your findings aloud, then "${first(VoiceCommand.stop)}".'),
        _step(4, 'Save',
            'App transcribes + formats automatically. Say "${first(VoiceCommand.save)}" or click Save.'),
      ],
    );
  }

  // ─── Full workflow ───────────────────────────────────────

  Widget _workflowCard(BuildContext context) {
    return _sectionCard(
      context: context,
      icon: Icons.account_tree_rounded,
      title: 'Full workflow — what each state expects',
      children: [
        _bullet('Awaiting patient ID',
            'Speak "patient id is <ID>" or type into the Patient ID field.'),
        _bullet('Confirming patient ID',
            'Say "confirm" to lock in, or "cancel" to re-enter.'),
        _bullet('Ready to record',
            'Say "start dictation" or click the red Start button.'),
        _bullet('Recording',
            'Say "pause" to pause, "stop dictation" to finish. Click Pause/Stop works too.'),
        _bullet('Paused',
            '"resume" or "stop dictation" — or use the toolbar buttons.'),
        _bullet('Transcribing & generating',
            'Automatic via Whisper + OpenAI. Wait ~5–15 seconds.'),
        _bullet('Report ready',
            '"save report" to persist, "discard" to throw away.'),
      ],
    );
  }

  // ─── Commands table ──────────────────────────────────────

  Widget _commandsCard(BuildContext context) {
    final phrases = SettingsService.getPhrases();
    final rows = <_CmdRow>[
      _CmdRow(VoiceCommand.dashboard, 'Go to Home'),
      _CmdRow(VoiceCommand.newReport, 'Start a new report'),
      _CmdRow(VoiceCommand.openReports, 'Open reports list'),
      _CmdRow(VoiceCommand.openSettings, 'Open voice settings'),
      _CmdRow(VoiceCommand.back, 'Go back to Home'),
      _CmdRow(VoiceCommand.patientId, 'Capture patient ID (followed by the ID)'),
      _CmdRow(VoiceCommand.confirm, 'Yes / confirm the current prompt'),
      _CmdRow(VoiceCommand.cancel, 'No / cancel the current prompt'),
      _CmdRow(VoiceCommand.start, 'Start recording dictation'),
      _CmdRow(VoiceCommand.pause, 'Pause recording'),
      _CmdRow(VoiceCommand.resume, 'Resume recording'),
      _CmdRow(VoiceCommand.stop, 'Stop recording (auto-transcribes + generates)'),
      _CmdRow(VoiceCommand.generate, 'Re-run report generation from transcript'),
      _CmdRow(VoiceCommand.save, 'Save the current report'),
      _CmdRow(VoiceCommand.discard, 'Discard the generated report'),
    ];

    return _sectionCard(
      context: context,
      icon: Icons.record_voice_over_rounded,
      title: 'Your voice commands (live — edit in Settings)',
      children: [
        const SizedBox(height: 4),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(3),
            2: FlexColumnWidth(3),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            _tableHeader(context),
            for (final r in rows)
              _tableRow(r.cmd, r.description, phrases[r.cmd.key] ?? '—'),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Tip: separate synonyms with "|". E.g. `start dictation | begin recording`.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  TableRow _tableHeader(BuildContext context) {
    TextStyle s = const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: AppColors.textHint);
    return TableRow(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text('COMMAND', style: s),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text('DOES', style: s),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text('SAY', style: s),
        ),
      ],
    );
  }

  TableRow _tableRow(VoiceCommand cmd, String description, String phrases) {
    final examples = phrases
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return TableRow(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Text(cmd.label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Text(description,
              style: const TextStyle(fontSize: 12)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final e in examples)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('"$e"',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Patient ID tips ─────────────────────────────────────

  Widget _patientIdCard(BuildContext context) {
    return _sectionCard(
      context: context,
      icon: Icons.badge_outlined,
      title: 'Speaking the patient ID accurately',
      children: [
        _bullet('Spell letters one-by-one',
            'Say each letter individually: "L R zero three five six four three", not "LR035643".'),
        _bullet('Number words → digits',
            'Zero, one, two, three, four, five, six, seven, eight, nine are converted automatically. "Oh" also maps to 0.'),
        _bullet('Separators',
            'Say "dash" or "hyphen" for "-", "slash" for "/".'),
        _bullet('Fallback',
            'If the recognizer misheard the ID, say "cancel", then type it in the Patient ID field and press ✓.'),
      ],
    );
  }

  // ─── Report view ────────────────────────────────────────

  Widget _reportViewCard(BuildContext context) {
    return _sectionCard(
      context: context,
      icon: Icons.description_outlined,
      title: 'Viewing, exporting, and managing reports',
      children: [
        _bullet('Open a report',
            'Go to Reports (sidebar or say "show reports"), tap a card, or say "open report".'),
        _bullet('Export PDF',
            'Tap the PDF icon in the report header. The PDF matches the department template.'),
        _bullet('Share',
            'Tap the share icon to send the PDF via macOS share sheet.'),
        _bullet('Delete',
            'Tap the trash icon in the report header — a confirm dialog appears. Audio files are removed too.'),
        _bullet('Search / filter',
            'In the Reports list: type in the search bar, or tap the status chips (Draft / Pending / Completed).'),
      ],
    );
  }

  // ─── Settings ───────────────────────────────────────────

  Widget _settingsCard(BuildContext context) {
    return _sectionCard(
      context: context,
      icon: Icons.settings_rounded,
      title: 'Customizing voice commands',
      children: [
        _bullet('Tap-edit',
            'In Settings, tap the pencil icon next to a command. Enter the phrase (or pipe-separated synonyms). Save.'),
        _bullet('Voice-edit',
            'Say "change <command>" (e.g. "change start"). Speak the new phrase. Say "confirm" twice to save.'),
        _bullet('Reset',
            'Use the "Reset defaults" button at the top of Settings to restore the original phrases.'),
        _bullet('Test microphone',
            'In the Debug panel at the bottom of Settings, click "Test microphone" to verify the recognizer end-to-end.'),
      ],
    );
  }

  // ─── Troubleshooting ────────────────────────────────────

  Widget _troubleshootCard(BuildContext context) {
    return _sectionCard(
      context: context,
      icon: Icons.healing_rounded,
      title: 'Troubleshooting',
      children: [
        _bullet('No reaction to speech',
            'Open 🐞 Debug log (Home or Voice Report header). The status pill at top-left tells you exactly which stage failed.'),
        _bullet('"Cannot start — recognizer unavailable"',
            'macOS never granted Speech Recognition / Microphone. Click the Retry button in the debug banner, or follow the steps below.'),
        const SizedBox(height: 4),
        _macOsSteps(),
        const SizedBox(height: 12),
        _bullet('Recognizer drops out',
            'The service auto-restarts after each "done" status. If it stays idle, toggle the mic button in the sidebar footer.'),
        _bullet('Transcript wrong',
            'Regenerate: say "generate report" or click Generate. You can also re-dictate by starting a new recording — the transcript accumulates.'),
        _bullet('Saved report missing',
            'All reports live in the local Hive database. Go to Reports tab to see them. Nothing is uploaded beyond transcription / report generation API calls.'),
      ],
    );
  }

  Widget _macOsSteps() {
    final voice = VoiceCommandService.instance;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'Grant macOS permissions (step-by-step)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          _numbered(1,
              'Open System Settings → Privacy & Security → Speech Recognition. Enable the toggle next to pathology_report.'),
          _numbered(2,
              'Open Privacy & Security → Microphone. Enable pathology_report here too.'),
          _numbered(3,
              'Open Keyboard → Dictation and turn Dictation on once (macOS installs the offline speech model the first time Dictation is used).'),
          _numbered(4,
              'Fully quit the app (Cmd+Q) and relaunch. Use `flutter run -d macos` for debug builds — unsigned .app copies do not retain permission.'),
          _numbered(5,
              'If nothing works, reset TCC from Terminal (one-shot), then relaunch: `tccutil reset SpeechRecognition && tccutil reset Microphone`.'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _settingsBtn('Open Speech Recognition',
                  () => voice.openMacSystemSettings(pane: 'speech')),
              _settingsBtn('Open Microphone',
                  () => voice.openMacSystemSettings(pane: 'microphone')),
              _settingsBtn('Open Dictation',
                  () => voice.openMacSystemSettings(pane: 'dictation')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numbered(int n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text('$n.',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _settingsBtn(String label, VoidCallback onTap) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_new_rounded,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── helpers ────────────────────────────────────────────

  Widget _sectionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(title,
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _step(int n, String heading, String detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$n',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(heading,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(detail,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String heading, String detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 7, right: 10),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.45),
                children: [
                  TextSpan(
                      text: '$heading — ',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(
                      text: detail,
                      style:
                          const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CmdRow {
  final VoiceCommand cmd;
  final String description;
  _CmdRow(this.cmd, this.description);
}
