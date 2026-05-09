import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/settings_service.dart';
import '../services/voice_command_service.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_debug_panel.dart';

/// Settings hub: a Branding tab (clinic info, logo, watermark, pathologist
/// info, barcode toggle) and a Voice Commands tab (the original
/// configurable phrase editor). Hands-free phrase editing still works in
/// the Voice tab.
class VoiceSettingsScreen extends StatefulWidget {
  final VoidCallback onBack;
  const VoiceSettingsScreen({super.key, required this.onBack});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            TabBar(
              controller: _tab,
              tabs: const [
                Tab(
                    icon: Icon(Icons.business_rounded, size: 16),
                    text: 'Branding'),
                Tab(
                    icon: Icon(Icons.record_voice_over_rounded, size: 16),
                    text: 'Voice Commands'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: const [
                  _BrandingTab(),
                  _VoiceCommandsTab(),
                ],
              ),
            ),
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
          Text('Settings',
              style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

// ─── Branding tab ───────────────────────────────────────────────────────

class _BrandingTab extends StatefulWidget {
  const _BrandingTab();

  @override
  State<_BrandingTab> createState() => _BrandingTabState();
}

class _BrandingTabState extends State<_BrandingTab> {
  late TextEditingController _clinicName;
  late TextEditingController _clinicAddress;
  late TextEditingController _clinicPhone;
  late TextEditingController _clinicEmail;
  late TextEditingController _clinicWebsite;
  late TextEditingController _pathologistName;
  late TextEditingController _pathologistReg;
  late TextEditingController _pathologistTitle;
  late TextEditingController _pathologist2Name;
  late TextEditingController _pathologist2Reg;
  late TextEditingController _pathologist2Title;
  late TextEditingController _watermarkText;
  bool _printBarcode = false;
  bool _dualSignature = false;
  String _logoPath = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _clinicName = TextEditingController(text: SettingsService.getClinicName());
    _clinicAddress =
        TextEditingController(text: SettingsService.getClinicAddress());
    _clinicPhone =
        TextEditingController(text: SettingsService.getClinicPhone());
    _clinicEmail =
        TextEditingController(text: SettingsService.getClinicEmail());
    _clinicWebsite =
        TextEditingController(text: SettingsService.getClinicWebsite());
    _pathologistName =
        TextEditingController(text: SettingsService.getPathologistName());
    _pathologistReg = TextEditingController(
        text: SettingsService.getPathologistRegistration());
    _pathologistTitle =
        TextEditingController(text: SettingsService.getPathologistTitle());
    _pathologist2Name =
        TextEditingController(text: SettingsService.getPathologist2Name());
    _pathologist2Reg = TextEditingController(
        text: SettingsService.getPathologist2Registration());
    _pathologist2Title =
        TextEditingController(text: SettingsService.getPathologist2Title());
    _watermarkText =
        TextEditingController(text: SettingsService.getPdfWatermarkText());
    _printBarcode = SettingsService.getPrintLinearBarcode();
    _dualSignature = SettingsService.getDualSignatureEnabled();
    _logoPath = SettingsService.getClinicLogoPath();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _clinicName.dispose();
    _clinicAddress.dispose();
    _clinicPhone.dispose();
    _clinicEmail.dispose();
    _clinicWebsite.dispose();
    _pathologistName.dispose();
    _pathologistReg.dispose();
    _pathologistTitle.dispose();
    _pathologist2Name.dispose();
    _pathologist2Reg.dispose();
    _pathologist2Title.dispose();
    _watermarkText.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _saveAll);
  }

  Future<void> _saveAll() async {
    await SettingsService.setClinicName(_clinicName.text.trim());
    await SettingsService.setClinicAddress(_clinicAddress.text.trim());
    await SettingsService.setClinicPhone(_clinicPhone.text.trim());
    await SettingsService.setClinicEmail(_clinicEmail.text.trim());
    await SettingsService.setClinicWebsite(_clinicWebsite.text.trim());
    await SettingsService.setPathologistName(_pathologistName.text.trim());
    await SettingsService.setPathologistRegistration(
        _pathologistReg.text.trim());
    await SettingsService.setPathologistTitle(_pathologistTitle.text.trim());
    await SettingsService.setPathologist2Name(_pathologist2Name.text.trim());
    await SettingsService.setPathologist2Registration(
        _pathologist2Reg.text.trim());
    await SettingsService.setPathologist2Title(_pathologist2Title.text.trim());
    await SettingsService.setDualSignatureEnabled(_dualSignature);
    await SettingsService.setPdfWatermarkText(_watermarkText.text.trim());
    await SettingsService.setPrintLinearBarcode(_printBarcode);
  }

  Future<void> _pickLogo() async {
    const png = XTypeGroup(label: 'PNG image', extensions: ['png']);
    final picked = await openFile(acceptedTypeGroups: [png]);
    if (picked == null) return;
    final supportDir = await getApplicationSupportDirectory();
    final brandingDir = Directory(p.join(supportDir.path, 'branding'));
    if (!await brandingDir.exists()) await brandingDir.create(recursive: true);
    final dest = p.join(brandingDir.path, 'logo.png');
    await File(picked.path).copy(dest);
    await SettingsService.setClinicLogoPath(dest);
    if (!mounted) return;
    setState(() => _logoPath = dest);
  }

  Future<void> _clearLogo() async {
    if (_logoPath.isNotEmpty) {
      try {
        final f = File(_logoPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await SettingsService.setClinicLogoPath('');
    if (!mounted) return;
    setState(() => _logoPath = '');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _section(
          title: 'Clinic / Lab',
          subtitle:
              'Replaces the hardcoded "Department of Laboratory Medicine" header on every printed report.',
          children: [
            _logoCard(),
            const SizedBox(height: 12),
            _field(_clinicName, 'Clinic name',
                hint: 'e.g. Acme Medical Lab'),
            _field(_clinicAddress, 'Address (multi-line)',
                hint: 'Street, city, postal code', minLines: 2, maxLines: 4),
            Row(
              children: [
                Expanded(child: _field(_clinicPhone, 'Phone')),
                const SizedBox(width: 12),
                Expanded(child: _field(_clinicEmail, 'Email')),
              ],
            ),
            _field(_clinicWebsite, 'Website'),
          ],
        ),
        _section(
          title: 'Pathologist signature',
          subtitle: 'Used on the printed report and in the bottom signature block.',
          children: [
            _field(_pathologistName, 'Name'),
            _field(_pathologistReg, 'Registration number'),
            _field(_pathologistTitle, 'Title / role'),
          ],
        ),
        _section(
          title: 'Admin · Dual sign-out',
          subtitle:
              'Some labs require two pathologists to co-sign every report (e.g. resident + consultant, or peer-review workflow). When enabled, both signature blocks are snapshotted onto every new report and printed side-by-side.',
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable dual signature on new reports'),
              subtitle: Text(
                  _dualSignature
                      ? 'New reports will carry both pathologists\' signatures.'
                      : 'Reports will be signed by the primary pathologist only.',
                  style: Theme.of(context).textTheme.bodySmall),
              value: _dualSignature,
              onChanged: (v) {
                setState(() => _dualSignature = v);
                _scheduleSave();
              },
            ),
            if (_dualSignature) ...[
              const SizedBox(height: 8),
              const Text('Second pathologist',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4)),
              const SizedBox(height: 8),
              _field(_pathologist2Name, 'Name',
                  hint: 'e.g. Dr. Jane Smith'),
              _field(_pathologist2Reg, 'Registration number',
                  hint: 'e.g. KMC - 12345'),
              _field(_pathologist2Title, 'Title / role',
                  hint: 'e.g. Senior Resident, Histopathology'),
            ],
          ],
        ),
        _section(
          title: 'Print options',
          subtitle:
              'Watermark renders faintly behind every PDF page. Leave the text blank to disable it. Linear barcode prints below the QR for legacy scanners.',
          children: [
            _field(_watermarkText, 'PDF watermark text',
                hint: 'Leave blank to disable'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Print Code 128 barcode under QR'),
              subtitle: Text(
                  'Useful when older lab scanners only read 1D barcodes.',
                  style: Theme.of(context).textTheme.bodySmall),
              value: _printBarcode,
              onChanged: (v) {
                setState(() => _printBarcode = v);
                _scheduleSave();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _section({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _logoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: _logoPath.isNotEmpty && File(_logoPath).existsSync()
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.file(File(_logoPath),
                        fit: BoxFit.contain),
                  )
                : const Icon(Icons.image_outlined,
                    size: 32, color: AppColors.textHint),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Clinic logo',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    _logoPath.isEmpty
                        ? 'No logo uploaded — printed reports show no logo.'
                        : 'PNG with transparency recommended for clean header overlay.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickLogo,
                      icon: const Icon(Icons.upload_file_rounded, size: 16),
                      label: Text(_logoPath.isEmpty
                          ? 'Upload PNG'
                          : 'Replace PNG'),
                    ),
                    if (_logoPath.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _clearLogo,
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 16),
                        label: const Text('Remove'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {String? hint, int minLines = 1, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        minLines: minLines,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
        ),
        onChanged: (_) => _scheduleSave(),
      ),
    );
  }
}

// ─── Voice commands tab (was the original screen body) ─────────────────

class _VoiceCommandsTab extends StatefulWidget {
  const _VoiceCommandsTab();

  @override
  State<_VoiceCommandsTab> createState() => _VoiceCommandsTabState();
}

enum _EditState { idle, pickingSlot, capturingPhrase, confirming }

class _VoiceCommandsTabState extends State<_VoiceCommandsTab> {
  final VoiceCommandService _voice = VoiceCommandService.instance;
  StreamSubscription<VoiceCommandEvent>? _cmdSub;
  StreamSubscription<TranscriptUpdate>? _transcriptSub;

  _EditState _editState = _EditState.idle;
  VoiceCommand? _selectedCommand;
  String _pendingPhrase = '';
  String _liveTranscript = '';
  String _statusMessage =
      'Say "change <command>" to edit — e.g. "change start"';

  @override
  void initState() {
    super.initState();
    _cmdSub = _voice.commands.listen(_onCommand);
    _transcriptSub = _voice.transcript.listen((u) {
      if (!mounted) return;
      final t = u.text;
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
      case VoiceCommand.next:
        return 'next';
      case VoiceCommand.previous:
        return 'previous';
      case VoiceCommand.skip:
        return 'skip';
    }
  }

  @override
  Widget build(BuildContext context) {
    final phrases = SettingsService.getPhrases();
    return Column(
      children: [
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
