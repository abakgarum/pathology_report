import 'package:flutter/material.dart';
import '../services/playback_service.dart';
import '../theme/app_theme.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String filePath;
  final String title;
  final VoidCallback? onClose;

  const AudioPlayerWidget({
    super.key,
    required this.filePath,
    required this.title,
    this.onClose,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late final PlaybackService _playbackService;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _playbackService = PlaybackService();
  }

  @override
  void dispose() {
    _playbackService.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: _playbackService.onPositionChanged,
      builder: (context, _) {
        return StreamBuilder<Duration>(
          stream: _playbackService.onDurationChanged,
          builder: (context, __) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with title and close button
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.play_circle_fill,
                                color: AppColors.primary, size: 18),
                            const SizedBox(height: 4),
                            Text(widget.title,
                                style: Theme.of(context).textTheme.titleMedium),
                            Text('Raw Recording Playback',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.textHint)),
                          ],
                        ),
                      ),
                      if (widget.onClose != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: widget.onClose,
                          tooltip: 'Close',
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Progress bar
                  Column(
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                        ),
                        child: Slider(
                          value: _playbackService.currentPosition.inMilliseconds
                              .toDouble(),
                          max: _playbackService.duration.inMilliseconds
                              .toDouble(),
                          activeColor: AppColors.primary,
                          inactiveColor: AppColors.border,
                          onChanged: (value) {
                            _playbackService
                                .seek(Duration(milliseconds: value.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(_playbackService.currentPosition),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      fontFamily: 'monospace',
                                      color: AppColors.textSecondary),
                            ),
                            Text(
                              _formatDuration(_playbackService.duration),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      fontFamily: 'monospace',
                                      color: AppColors.textHint),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Playback controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Backward button
                      _ControlButton(
                        icon: Icons.replay,
                        label: '-15s',
                        onTap: () => _playbackService.backward(),
                      ),
                      const SizedBox(width: 16),

                      // Play/Pause button (large)
                      _ControlButton(
                        icon: _playbackService.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        label: _playbackService.isPlaying ? 'Pause' : 'Play',
                        onTap: () {
                          if (_playbackService.isPlaying) {
                            _playbackService.pause();
                          } else if (_playbackService.state ==
                              PlaybackState.paused) {
                            _playbackService.resume();
                          } else {
                            _playbackService.play(widget.filePath);
                          }
                          setState(() {});
                        },
                        large: true,
                      ),
                      const SizedBox(width: 16),

                      // Forward button
                      _ControlButton(
                        icon: Icons.forward,
                        label: '+15s',
                        onTap: () => _playbackService.forward(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Playback speed selector
                  Row(
                    children: [
                      Text('Speed:',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
                              final isSelected =
                                  (_playbackSpeed - speed).abs() < 0.01;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: FilterChip(
                                  label: Text('${speed}x'),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (selected) {
                                      _playbackService.setPlaybackRate(speed);
                                      setState(() => _playbackSpeed = speed);
                                    }
                                  },
                                  selectedColor:
                                      AppColors.primary.withOpacity(0.12),
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Stop button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _playbackService.stop(),
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('Stop'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool large;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AppColors.primary.withOpacity(0.1),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: large ? 56 : 44,
              height: large ? 56 : 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.3), width: 1.5),
              ),
              child:
                  Icon(icon, color: AppColors.primary, size: large ? 26 : 20),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
