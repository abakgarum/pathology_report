import 'dart:async';

import 'package:flutter/material.dart';

import '../services/voice_command_service.dart';
import '../theme/app_theme.dart';

/// Live, colored tail of the voice-service log. Drop this into any screen
/// to see in real time: init result, permission status, every partial/final
/// result, every matched command, and every error.
class VoiceDebugPanel extends StatefulWidget {
  final double height;
  const VoiceDebugPanel({super.key, this.height = 240});

  @override
  State<VoiceDebugPanel> createState() => _VoiceDebugPanelState();
}

class _VoiceDebugPanelState extends State<VoiceDebugPanel> {
  final _voice = VoiceCommandService.instance;
  final _scroll = ScrollController();
  StreamSubscription<VoiceLogLine>? _sub;
  List<VoiceLogLine> _lines = [];
  String _lastTestResult = '';
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _lines = List.of(_voice.log);
    _sub = _voice.logStream.listen((line) {
      if (!mounted) return;
      setState(() => _lines = List.of(_voice.log));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Color _colorFor(String level) {
    switch (level) {
      case 'error':
        return AppColors.error;
      case 'warn':
        return AppColors.warning;
      case 'match':
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1419),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _header(),
          if (_voice.isInitialized && !_voice.isAvailable) _unavailableBanner(),
          const Divider(height: 1, color: Color(0xFF1F2833)),
          SizedBox(
            height: widget.height,
            child: _lines.isEmpty
                ? Center(
                    child: Text(
                      'No voice events yet. Speak or press "Test microphone".',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: _lines.length,
                    itemBuilder: (_, i) {
                      final l = _lines[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: SelectableText(
                          l.toString(),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: _colorFor(l.level),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.terminal_rounded,
              size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          const Text('Voice debug log',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          _statusPill(),
          const Spacer(),
          if (_lastTestResult.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('heard: "$_lastTestResult"',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11)),
              ),
            ),
          TextButton.icon(
            onPressed: _testing ? null : _runTest,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor:
                  _testing ? Colors.white10 : AppColors.primary.withOpacity(0.8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: _testing
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.mic_rounded, size: 14),
            label: Text(_testing ? 'Listening…' : 'Test microphone',
                style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Copy log',
            iconSize: 18,
            color: Colors.white70,
            icon: const Icon(Icons.copy_rounded),
            onPressed: _copyLog,
          ),
          IconButton(
            tooltip: 'Clear',
            iconSize: 18,
            color: Colors.white70,
            icon: const Icon(Icons.clear_all_rounded),
            onPressed: () => setState(() => _lines = []),
          ),
        ],
      ),
    );
  }

  Widget _statusPill() {
    final init = _voice.isInitialized;
    final avail = _voice.isAvailable;
    final listening = _voice.isListening;
    String label;
    Color color;
    if (!init) {
      label = 'not initialized';
      color = AppColors.warning;
    } else if (!avail) {
      label = 'unavailable';
      color = AppColors.error;
    } else if (listening) {
      label = 'listening';
      color = AppColors.success;
    } else {
      label = 'idle';
      color = AppColors.textHint;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _unavailableBanner() {
    final err = _voice.lastError.isEmpty
        ? 'Speech recognizer unavailable.'
        : _voice.lastError;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.18),
        border: Border(
          top: BorderSide(color: AppColors.error.withOpacity(0.3)),
          bottom: BorderSide(color: AppColors.error.withOpacity(0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.error, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(err,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.4)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _smallBtn('Open Speech Recognition',
                  () => _voice.openMacSystemSettings(pane: 'speech')),
              _smallBtn('Open Microphone',
                  () => _voice.openMacSystemSettings(pane: 'microphone')),
              _smallBtn('Open Dictation',
                  () => _voice.openMacSystemSettings(pane: 'dictation')),
              _smallBtn('Retry', () async {
                await _voice.reinit();
                if (mounted) setState(() {});
              }, filled: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallBtn(String label, VoidCallback onTap, {bool filled = false}) {
    final bg = filled ? AppColors.primary : Colors.white.withOpacity(0.08);
    final fg = filled ? Colors.white : Colors.white;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ),
      ),
    );
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _lastTestResult = '';
    });
    final result = await _voice.testOnce(
      duration: const Duration(seconds: 5),
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _lastTestResult = result;
    });
  }

  void _copyLog() {
    // Put it on the clipboard via share menu trick — skipped to avoid extra deps.
    // SelectableText entries already allow manual copy.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Long-press a line to copy.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
