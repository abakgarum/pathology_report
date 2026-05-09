import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../services/voice_command_service.dart';
import '../theme/app_theme.dart';

/// A persistent banner that appears at the top of any voice-driven screen
/// when speech recognition is **not available** on the host system.
///
/// Why this exists: the app gracefully degrades to tap-only operation when
/// the recognizer can't be initialised (older macOS, missing speech model,
/// permission denied, no STT engine on Linux, etc). Without a clear,
/// always-visible explanation the doctor sees a silent listening pill and
/// thinks the app is broken. This banner replaces that confusion with a
/// concrete reason and two recovery actions:
///
///   • **Retry**         — re-runs `init()`, useful after the user grants
///                         permission or installs the speech model.
///   • **Open Settings** — jumps directly to the right macOS pane (only
///                         shown on macOS where the URL scheme works).
///
/// The widget collapses to nothing when STT is healthy, so screens can
/// drop it in unconditionally without conditional rendering.
class VoiceUnavailableBanner extends StatefulWidget {
  /// Optional override message — by default we use the platform-specific
  /// hint that `VoiceCommandService.init()` already composes.
  final String? customMessage;

  const VoiceUnavailableBanner({super.key, this.customMessage});

  @override
  State<VoiceUnavailableBanner> createState() => _VoiceUnavailableBannerState();
}

class _VoiceUnavailableBannerState extends State<VoiceUnavailableBanner> {
  final VoiceCommandService _voice = VoiceCommandService.instance;
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await _voice.reinit();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: _voice.status,
      builder: (context, _) {
        // Voice is healthy — render nothing, take no space.
        if (_voice.isAvailable) return const SizedBox.shrink();

        // Still initializing for the first time — show a thin placeholder
        // rather than the alarming red banner, so the screen doesn't
        // flash a scary error in the first ~200ms before init returns.
        if (!_voice.isInitialized) {
          return _initializing(context);
        }

        return _unavailable(context);
      },
    );
  }

  Widget _initializing(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Text('Initializing voice recognition…',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _unavailable(BuildContext context) {
    final reason = (widget.customMessage ?? _voice.lastError).trim();
    final canOpenSettings = Platform.isMacOS;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        // Warning amber — strong enough to read past the listening pill,
        // soft enough to live above the question card without screaming.
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: AppColors.warning, width: 4),
          top: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
          right: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
          bottom: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.mic_off_rounded,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Voice features are unavailable on this system',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Reassurance up front — the app is fully usable.
                      'You can still complete reports normally — just tap '
                      'options and use the on-screen keyboard. Voice will '
                      'reconnect automatically once the issue below is fixed.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.25)),
              ),
              child: Text(
                reason,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _retrying ? null : _retry,
                icon: _retrying
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.warning))
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: Text(_retrying ? 'Retrying…' : 'Retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.warning.withValues(alpha: 0.18),
                  foregroundColor: AppColors.warning,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                ),
              ),
              if (canOpenSettings) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _voice.openMacSystemSettings(
                      pane: 'speech'),
                  icon: const Icon(Icons.settings_rounded, size: 16),
                  label: const Text('Open System Settings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(
                        color: AppColors.warning.withValues(alpha: 0.4)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
