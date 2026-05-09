import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/report_models.dart';
import '../services/hive_storage_service.dart';
import '../services/settings_service.dart';
import '../services/voice_command_service.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_debug_panel.dart';
import '../widgets/voice_unavailable_banner.dart';

/// Always-listening landing screen. Spoken commands navigate to:
///   - "new report"  → [onNewReport]
///   - "show reports" → [onShowReports]
///   - "open settings" → [onOpenSettings]
class HomeVoiceScreen extends StatefulWidget {
  final VoidCallback onNewReport;
  final VoidCallback onShowReports;
  final VoidCallback onOpenSettings;

  const HomeVoiceScreen({
    super.key,
    required this.onNewReport,
    required this.onShowReports,
    required this.onOpenSettings,
  });

  @override
  State<HomeVoiceScreen> createState() => _HomeVoiceScreenState();
}

class _HomeVoiceScreenState extends State<HomeVoiceScreen>
    with TickerProviderStateMixin {
  final VoiceCommandService _voice = VoiceCommandService.instance;
  StreamSubscription<VoiceCommandEvent>? _cmdSub;
  StreamSubscription<TranscriptUpdate>? _transcriptSub;
  String _liveTranscript = '';
  bool _showDebug = false;

  late final AnimationController _pulse;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1, end: 1.25)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    // Voice is best-effort. On platforms without a working speech recognizer
    // (Linux, Windows machines without the en_US speech pack) the service
    // surfaces an unavailable state instead of throwing, so the home page
    // stays usable via taps and the side nav.
    try {
      _cmdSub = _voice.commands.listen(_onCommand);
      _transcriptSub = _voice.transcript.listen((u) {
        if (mounted) setState(() => _liveTranscript = u.text);
      });
    } catch (e) {
      debugPrint('home_voice_screen: voice stream subscribe failed: $e');
    }
    unawaited(_voice.start());
  }

  @override
  void dispose() {
    _cmdSub?.cancel();
    _transcriptSub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _onCommand(VoiceCommandEvent e) {
    if (!mounted) return;
    switch (e.command) {
      case VoiceCommand.newReport:
        widget.onNewReport();
        break;
      case VoiceCommand.openReports:
        widget.onShowReports();
        break;
      case VoiceCommand.openSettings:
        widget.onOpenSettings();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final phrases = SettingsService.getPhrases();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            // When STT is unavailable on this Mac, the central mic
            // animation would otherwise pulse forever waiting for input
            // that can't arrive. The banner gives the doctor a clear
            // reason + Retry, and the rest of the home page (stats, side
            // nav, tap-to-open buttons) keeps working as a normal app.
            const VoiceUnavailableBanner(),
            const SizedBox(height: 16),
            _stats(),
            const SizedBox(height: 20),
            Expanded(child: _centerMic()),
            _commandMenu(phrases),
            if (_showDebug)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: VoiceDebugPanel(height: 220),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.biotech_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PathLab Pro',
                  style: Theme.of(context).textTheme.headlineMedium),
              Text('Voice-only pathology suite',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: _showDebug ? 'Hide debug log' : 'Show debug log',
            icon: Icon(_showDebug
                ? Icons.bug_report_rounded
                : Icons.bug_report_outlined),
            onPressed: () => setState(() => _showDebug = !_showDebug),
          ),
          const SizedBox(width: 4),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: (listening ? AppColors.success : AppColors.textHint)
                .withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) => Transform.scale(
                  scale: listening ? _pulseAnim.value : 1,
                  child: child,
                ),
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: listening ? AppColors.success : AppColors.textHint,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(listening ? 'Listening' : 'Idle',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: listening
                          ? AppColors.success
                          : AppColors.textHint)),
            ],
          ),
        );
      },
    );
  }

  Widget _stats() {
    return ValueListenableBuilder(
      valueListenable: HiveStorageService.reportsListenable(),
      builder: (context, Box<PathologyReport> box, _) {
        final reports = HiveStorageService.allReports();
        final done = reports
            .where((r) => r.status == ReportStatus.completed)
            .length;
        final pending =
            reports.where((r) => r.status == ReportStatus.pending).length;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              _stat('Total', '${reports.length}', AppColors.primary),
              const SizedBox(width: 12),
              _stat('Completed', '$done', AppColors.completed),
              const SizedBox(width: 12),
              _stat('Pending', '$pending', AppColors.pending),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.description_rounded, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(label,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _centerMic() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, child) => Transform.scale(
              scale: _pulseAnim.value,
              child: child,
            ),
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.mic_rounded,
                  color: Colors.white, size: 72),
            ),
          ),
          const SizedBox(height: 24),
          Text('Speak a command',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          SizedBox(
            width: 440,
            child: Text(
              _liveTranscript.isEmpty
                  ? 'Try "new report", "show reports", or "open settings".'
                  : '"${_liveTranscript.toLowerCase()}"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _commandMenu(Map<String, String> phrases) {
    String first(VoiceCommand c) =>
        (phrases[c.key] ?? '').split('|').first.trim();

    Widget action({
      required IconData icon,
      required String label,
      required String phrase,
      required Color color,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        width: 180,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
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
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: color, size: 18),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textHint, size: 18),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(label,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.record_voice_over_rounded,
                          size: 12, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('"$phrase"',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontStyle: FontStyle.italic)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          action(
            icon: Icons.mic_rounded,
            label: 'New Voice Report',
            phrase: first(VoiceCommand.newReport),
            color: AppColors.primary,
            onTap: widget.onNewReport,
          ),
          action(
            icon: Icons.folder_rounded,
            label: 'Open Reports',
            phrase: first(VoiceCommand.openReports),
            color: AppColors.info,
            onTap: widget.onShowReports,
          ),
          action(
            icon: Icons.settings_rounded,
            label: 'Voice Settings',
            phrase: first(VoiceCommand.openSettings),
            color: AppColors.warning,
            onTap: widget.onOpenSettings,
          ),
        ],
      ),
    );
  }
}
