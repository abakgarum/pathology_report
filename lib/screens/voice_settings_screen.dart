import 'dart:async';

import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../services/voice_command_service.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_debug_panel.dart';

/// Voice-configurable command phrases.
///
/// Workflow (hands-free):
///   1. Say "change <command name>" (e.g. "change start") to pick a slot.
///   2. Say the new trigger phrase aloud.
///   3. Say "confirm" to save, "cancel" to abort.
///   4. Say "go back" to leave.
class VoiceSettingsScreen extends StatefulWidget {
  final VoidCallback onBack;
  const VoiceSettingsScreen({super.key, required this.onBack});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

enum _EditState { idle, pickingSlot, capturingPhrase, confirming }

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  final VoiceCommandService _voice = VoiceCommandService.instance;
  StreamSubscription<VoiceCommandEvent>? _cmdSub;
  StreamSubscription<String>? _transcriptSub;

  _EditState _editState = _EditState.idle;
  VoiceCommand? _selectedCommand;
  String _pendingPhrase = '';
  String _liveTranscript = '';
  String _statusMessage = 'Say "change <command>" to edit — e.g. "change start"';

  @override
  void initState() {
    super.initState();
    _cmdSub = _voice.commands.listen(_onCommand);
    _transcriptSub = _voice.transcript.listen((t) {
      if (!mounted) return;
      setState(() {
        _liveTranscript = t;
        if (_editState == _EditState.capturingPhrase) {
          _pendingPhrase = t.toLowerCase();
        } else if (_editState == _EditState.idle) {
          _maybePickSlotFromTranscript(t);
        }
      });
    });
    _voice.start();
  }

  @override
  void dispose() {
    _cmdSub?.cancel();
    _transcriptSub?.cancel();
    super.dispose();
  }

  Future<void> _onCommand(VoiceCommandEvent e) async {
    if (!mounted) return;
    if (e.command == VoiceCommand.back) {
      widget.onBack();
      return;
    }
    if (e.command == VoiceCommand.confirm) {
      if (_editState == _EditState.capturingPhrase &&
          _pendingPhrase.isNotEmpty) {
        setState(() => _editState = _EditState.confirming);
      } else if (_editState == _EditState.confirming &&
          _selectedCommand != null &&
          _pendingPhrase.isNotEmpty) {
        await SettingsService.setPhrase(_selectedCommand!, _pendingPhrase);
        setState(() {
          _statusMessage =
              'Saved: ${_selectedCommand!.label} → "$_pendingPhrase"';
          _editState = _EditState.idle;
          _selectedCommand = null;
          _pendingPhrase = '';
        });
      }
    } else if (e.command == VoiceCommand.cancel) {
      setState(() {
        _editState = _EditState.idle;
        _selectedCommand = null;
        _pendingPhrase = '';
        _statusMessage = 'Cancelled.';
      });
    }
  }

  /// Parse "change <command>" from the live transcript to pick a slot.
  void _maybePickSlotFromTranscript(String text) {
    final lower = text.toLowerCase();
    final idx = lower.lastIndexOf('change ');
    if (idx == -1) return;
    final rest = lower.substring(idx + 'change '.length).trim();
    for (final c in VoiceCommand.values) {
      final name = c.key.toLowerCase();
      if (rest.contains(name) ||
          rest.contains(_humanName(c).toLowerCase())) {
        setState(() {
          _selectedCommand = c;
          _editState = _EditState.capturingPhrase;
          _pendingPhrase = '';
          _statusMessage =
              'Now say the new phrase for "${_humanName(c)}", then say "confirm".';
        });
        return;
      }
    }
  }

  String _humanName(VoiceCommand c) {
    switch (c) {
      case VoiceCommand.start:
        return 'start';
      case VoiceCommand.stop:
        return 'stop';
      case VoiceCommand.pause:
        return 'pause';
      case VoiceCommand.resume:
        return 'resume';
      case VoiceCommand.save:
        return 'save';
      case VoiceCommand.discard:
        return 'discard';
      case VoiceCommand.generate:
        return 'generate';
      case VoiceCommand.newReport:
        return 'new report';
      case VoiceCommand.openReports:
        return 'show reports';
      case VoiceCommand.openSettings:
        return 'settings';
      case VoiceCommand.dashboard:
        return 'home';
      case VoiceCommand.back:
        return 'back';
      case VoiceCommand.patientId:
        return 'patient id';
      case VoiceCommand.confirm:
        return 'confirm';
      case VoiceCommand.cancel:
        return 'cancel';
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
            _topBar(),
            _statusCard(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  for (final c in VoiceCommand.values)
                    _commandRow(c, phrases[c.key] ?? ''),
                  const SizedBox(height: 16),
                  const VoiceDebugPanel(height: 260),
                ],
              ),
            ),
            _commandHints(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const Icon(Icons.settings_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Text('Voice Commands',
              style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          TextButton.icon(
            onPressed: () async {
              await SettingsService.resetDefaults();
              setState(() => _statusMessage = 'Reset to defaults.');
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Reset defaults'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditDialog(VoiceCommand cmd, String current) async {
    final ctrl = TextEditingController(text: current);
    final newPhrase = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit "${cmd.label}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Trigger phrases. Separate multiple synonyms with " | ".',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'e.g. start dictation | begin recording',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newPhrase != null && newPhrase.isNotEmpty) {
      await SettingsService.setPhrase(cmd, newPhrase);
      setState(() => _statusMessage = 'Saved: ${cmd.label} → "$newPhrase"');
    }
  }

  Widget _statusCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.record_voice_over_rounded,
                    size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_statusMessage,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ],
          ),
          if (_liveTranscript.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Heard: "$_liveTranscript"',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_editState == _EditState.confirming &&
              _pendingPhrase.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                  'New phrase: "$_pendingPhrase" — say "confirm" again to save',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ],
      ),
    );
  }

  Widget _commandRow(VoiceCommand c, String phrase) {
    final isSelected = _selectedCommand == c;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isSelected ? AppColors.primary : AppColors.border,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _humanName(c),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.label,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  phrase.isEmpty ? '—' : phrase,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          if (isSelected)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.record_voice_over_rounded,
                  size: 16, color: AppColors.primary),
            ),
          IconButton(
            tooltip: 'Edit phrase',
            iconSize: 18,
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => _openEditDialog(c, phrase),
          ),
        ],
      ),
    );
  }

  Widget _commandHints() {
    final hints = <String>[];
    switch (_editState) {
      case _EditState.idle:
        hints.addAll([
          '"change start"',
          '"change stop"',
          '"change new report"',
          '"go back"',
        ]);
        break;
      case _EditState.capturingPhrase:
        hints.add('(speak the new phrase, then "confirm")');
        break;
      case _EditState.confirming:
        hints.addAll(['"confirm"', '"cancel"']);
        break;
      case _EditState.pickingSlot:
        hints.add('(say which command to change)');
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
}
