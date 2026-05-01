import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/report_models.dart';
import '../services/hive_storage_service.dart';
import '../services/settings_service.dart';
import '../services/template_parser_service.dart';
import '../theme/app_theme.dart';

/// Manage report template files. Each template is backed by an uploaded
/// document (e.g. a CAP protocol `.docx`). On upload the file is copied
/// into the app's documents directory AND the contents are parsed by the
/// LLM into a structured Q&A schema that drives the guided wizard.
class TemplatesScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const TemplatesScreen({super.key, this.onBack});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  String? _selectedId;
  final Set<String> _parsing = <String>{};
  final Map<String, String> _parseErrors = <String, String>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            _licensingNotice(),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: HiveStorageService.templatesListenable(),
                builder: (context, box, _) {
                  final templates = HiveStorageService.allTemplates();
                  final activeId = SettingsService.getActiveTemplateId();
                  if (templates.isEmpty) return _empty();
                  return LayoutBuilder(
                    builder: (context, c) {
                      final wide = c.maxWidth > 820;
                      final selected = templates.firstWhere(
                        (t) => t.id == _selectedId,
                        orElse: () => templates.first,
                      );
                      return wide
                          ? Row(
                              children: [
                                SizedBox(
                                  width: 320,
                                  child:
                                      _list(templates, activeId, selected.id),
                                ),
                                const VerticalDivider(width: 1),
                                Expanded(child: _preview(selected, activeId)),
                              ],
                            )
                          : _list(templates, activeId, selected.id);
                    },
                  );
                },
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
          if (widget.onBack != null)
            IconButton(
              tooltip: 'Back',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          const Icon(Icons.description_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Text('Report Templates',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Upload a .docx — the file is parsed into a guided Q&A wizard.',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          FilledButton.icon(
            onPressed: () => _openUploadDialog(),
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Upload template'),
          ),
        ],
      ),
    );
  }

  Widget _licensingNotice() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.gavel_rounded,
              size: 16, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'CAP cancer protocols are copyrighted. You are responsible for '
              'ensuring you have a valid CAP license for any CAP protocol '
              'files you upload — this app does not ship CAP content.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined,
              size: 48, color: AppColors.textHint.withOpacity(0.6)),
          const SizedBox(height: 10),
          Text('No template files yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
              'Upload a .docx — the wizard will guide each report through it.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _openUploadDialog(),
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Upload first template'),
          ),
        ],
      ),
    );
  }

  Widget _list(
      List<TemplateDocument> templates, String activeId, String currentId) {
    return ValueListenableBuilder(
      valueListenable: HiveStorageService.schemasListenable(),
      builder: (_, __, ___) {
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: templates.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: AppColors.divider),
          itemBuilder: (context, i) {
            final t = templates[i];
            final isActive = t.id == activeId;
            final isSelected = t.id == currentId;
            final schema = HiveStorageService.getTemplateSchema(t.id);
            final parsing = _parsing.contains(t.id);
            return Material(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.06)
                  : Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _selectedId = t.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        isActive
                            ? Icons.star_rounded
                            : _iconForExt(t.sourceFileName),
                        size: 18,
                        color: isActive
                            ? AppColors.warning
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name.isEmpty ? 'Untitled template' : t.name,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (t.label.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              _labelChip(t.label),
                            ],
                            const SizedBox(height: 4),
                            _parsedStatusChip(t, schema, parsing),
                          ],
                        ),
                      ),
                      if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('Default',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.warning)),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _parsedStatusChip(
      TemplateDocument t, TemplateSchema? schema, bool parsing) {
    if (parsing) {
      return _statusChip(
        'Parsing…',
        const Color(0xFF3182CE),
        leading: const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.6),
        ),
      );
    }
    if (schema != null) {
      final secs = schema.sections.length;
      final qs = schema.totalQuestions;
      return _statusChip(
        'Parsed · $secs sec · $qs Q',
        AppColors.success,
        leading: const Icon(Icons.check_circle_rounded,
            size: 11, color: AppColors.success),
      );
    }
    final err = _parseErrors[t.id];
    if (err != null) {
      return _statusChip(
        'Parse failed — tap Re-parse',
        AppColors.error,
        leading: const Icon(Icons.error_outline_rounded,
            size: 11, color: AppColors.error),
      );
    }
    return _statusChip(
      'Free-form (not parsed)',
      AppColors.textHint,
      leading: const Icon(Icons.subject_rounded,
          size: 11, color: AppColors.textHint),
    );
  }

  Widget _statusChip(String label, Color color, {Widget? leading}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) leading,
          if (leading != null) const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(TemplateDocument t, DateFormat fmt) {
    Widget item(IconData icon, String label, String value) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.textHint),
            const SizedBox(width: 4),
            Text('$label ',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHint)),
            Flexible(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        item(Icons.schedule_rounded, 'Created', fmt.format(t.createdAt)),
        item(Icons.edit_calendar_rounded, 'Updated', fmt.format(t.updatedAt)),
        item(Icons.insert_drive_file_outlined, 'File',
            '${t.sourceFileName} · ${_fmtSize(t.fileSize)}'),
      ],
    );
  }

  Widget _labelChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.info),
      ),
    );
  }

  Widget _preview(TemplateDocument t, String activeId) {
    final isActive = t.id == activeId;
    final fmt = DateFormat('dd MMM yyyy · HH:mm');
    final schema = HiveStorageService.getTemplateSchema(t.id);
    final parsing = _parsing.contains(t.id);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name.isEmpty ? 'Untitled template' : t.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (t.label.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _labelChip(t.label),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: parsing ? null : () => _reparse(t),
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: Text(schema == null ? 'Parse' : 'Re-parse'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _setActive(t.id, !isActive),
                icon: Icon(
                  isActive ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 18,
                  color: isActive ? AppColors.warning : null,
                ),
                label: Text(isActive ? 'Active' : 'Set as default'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _editMetadata(t),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Rename'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _confirmDelete(t),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _metaRow(t, fmt),
          const SizedBox(height: 16),
          Expanded(child: _previewBody(t, schema, parsing)),
        ],
      ),
    );
  }

  Widget _previewBody(
      TemplateDocument t, TemplateSchema? schema, bool parsing) {
    if (parsing) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.4)),
            SizedBox(height: 12),
            Text('Parsing template — usually 5-15 seconds…',
                style: TextStyle(fontSize: 12, color: AppColors.textHint)),
          ],
        ),
      );
    }
    if (schema == null) {
      final err = _parseErrors[t.id];
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_iconForExt(t.sourceFileName),
                size: 56, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              t.sourceFileName.isEmpty ? 'File' : t.sourceFileName,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(_fmtSize(t.fileSize),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            if (err != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Last parse error: $err',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.error)),
              ),
              const SizedBox(height: 12),
            ] else ...[
              const Text(
                'Not parsed yet — guided mode unavailable for this template. '
                'Reports will fall back to free-form dictation.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => _reparse(t),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: const Text('Parse now'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _revealInFinder(t),
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text('Reveal in Finder'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _replaceFile(t),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Replace file'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return _schemaBrowser(schema);
  }

  Widget _schemaBrowser(TemplateSchema schema) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(8),
      child: ListView.builder(
        itemCount: schema.sections.length,
        itemBuilder: (_, i) {
          final s = schema.sections[i];
          return ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    s.title.isEmpty ? 'Section ${i + 1}' : s.title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                Text('${s.questions.length} Q',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textHint)),
              ],
            ),
            childrenPadding:
                const EdgeInsets.fromLTRB(12, 0, 12, 8),
            children: s.questions.map(_questionTile).toList(),
          );
        },
      ),
    );
  }

  Widget _questionTile(TemplateQuestion q) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    q.label,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                if (!q.required)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.textHint.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('optional',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textHint)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _qMetaChip(q.type.label),
                if (q.units.isNotEmpty) _qMetaChip('units: ${q.units}'),
                if (q.freeTextAllowed) _qMetaChip('+ free text'),
              ],
            ),
            if (q.answers.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...q.answers.map((a) => Padding(
                    padding:
                        const EdgeInsets.only(left: 8, top: 2, bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textHint)),
                        Expanded(
                          child: Text(
                            '${a.label}${a.triggersQuestionIds.isNotEmpty ? "  →  ${a.triggersQuestionIds.length} sub-question(s)" : ""}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _qMetaChip(String s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(s,
          style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.primary)),
    );
  }

  Future<void> _setActive(String id, bool active) async {
    await SettingsService.setActiveTemplateId(active ? id : '');
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            active ? 'Template set as default' : 'Template deactivated'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDelete(TemplateDocument t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text(
            '"${t.name.isEmpty ? 'Untitled' : t.name}" (${t.sourceFileName}) will be removed and the stored file deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await HiveStorageService.deleteTemplate(t.id);
    if (SettingsService.getActiveTemplateId() == t.id) {
      await SettingsService.setActiveTemplateId('');
    }
    if (mounted) setState(() => _selectedId = null);
  }

  Future<void> _revealInFinder(TemplateDocument t) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', t.filePath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', t.filePath]);
      } else {
        await Process.run('xdg-open', [p.dirname(t.filePath)]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open folder — $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _replaceFile(TemplateDocument t) async {
    final picked = await _pickTemplateFile();
    if (picked == null) return;
    // Remove old stored file first.
    try {
      final f = File(t.filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    final newPath = await HiveStorageService.storeTemplateFile(
      sourcePath: picked.path,
      id: t.id,
    );
    final size = await File(newPath).length();
    final updated = t.copyWith(
      filePath: newPath,
      sourceFileName: p.basename(picked.path),
      fileSize: size,
    );
    await HiveStorageService.saveTemplate(updated);
    // The schema is now stale — drop it and re-parse.
    await HiveStorageService.deleteTemplateSchema(t.id);
    if (!mounted) return;
    setState(() {});
    _runParse(updated);
  }

  Future<void> _openUploadDialog() async {
    final picked = await _pickTemplateFile();
    if (picked == null) return;
    if (!mounted) return;
    final result = await showDialog<_TemplateMeta>(
      context: context,
      builder: (_) => _TemplateMetaDialog(
        initialName: p.basenameWithoutExtension(picked.path),
        fileName: p.basename(picked.path),
      ),
    );
    if (result == null) return;

    final id = TemplateDocument(
      name: result.name,
      label: result.label,
      filePath: '',
      sourceFileName: p.basename(picked.path),
    ).id; // generate id first so filename is stable

    final storedPath = await HiveStorageService.storeTemplateFile(
      sourcePath: picked.path,
      id: id,
    );
    final size = await File(storedPath).length();
    final template = TemplateDocument(
      id: id,
      name: result.name,
      label: result.label,
      filePath: storedPath,
      sourceFileName: p.basename(picked.path),
      fileSize: size,
    );
    await HiveStorageService.saveTemplate(template);
    if (mounted) setState(() => _selectedId = template.id);
    // Auto-parse on upload.
    _runParse(template);
  }

  Future<void> _editMetadata(TemplateDocument t) async {
    final result = await showDialog<_TemplateMeta>(
      context: context,
      builder: (_) => _TemplateMetaDialog(
        initialName: t.name,
        initialLabel: t.label,
        fileName: t.sourceFileName,
      ),
    );
    if (result == null) return;
    final updated = t.copyWith(name: result.name, label: result.label);
    await HiveStorageService.saveTemplate(updated);
    if (mounted) setState(() {});
  }

  Future<XFile?> _pickTemplateFile() async {
    const groups = [
      XTypeGroup(label: 'Word document', extensions: ['docx']),
      XTypeGroup(label: 'Text', extensions: ['txt', 'rtf']),
    ];
    try {
      return await openFile(acceptedTypeGroups: groups);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not pick file — $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _reparse(TemplateDocument t) async {
    await HiveStorageService.deleteTemplateSchema(t.id);
    await _runParse(t);
  }

  Future<void> _runParse(TemplateDocument t) async {
    if (_parsing.contains(t.id)) return;
    setState(() {
      _parsing.add(t.id);
      _parseErrors.remove(t.id);
    });
    try {
      final schema = await TemplateParserService.parseFile(
        filePath: t.filePath,
        templateId: t.id,
      );
      await HiveStorageService.saveTemplateSchema(schema);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Parsed: ${schema.sections.length} sections · ${schema.totalQuestions} questions'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      _parseErrors[t.id] = e.toString();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Parse failed — $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _parsing.remove(t.id));
    }
  }

  // ─── helpers ────────────────────────────────────────────────

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  IconData _iconForExt(String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf_rounded;
      case '.doc':
      case '.docx':
        return Icons.description_rounded;
      case '.txt':
      case '.rtf':
        return Icons.subject_rounded;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}

// ─── Metadata dialog (name + label only — no content) ───────────

class _TemplateMeta {
  final String name;
  final String label;
  _TemplateMeta(this.name, this.label);
}

class _TemplateMetaDialog extends StatefulWidget {
  final String initialName;
  final String initialLabel;
  final String fileName;
  const _TemplateMetaDialog({
    required this.initialName,
    this.initialLabel = '',
    required this.fileName,
  });

  @override
  State<_TemplateMetaDialog> createState() => _TemplateMetaDialogState();
}

class _TemplateMetaDialogState extends State<_TemplateMetaDialog> {
  late final TextEditingController _name;
  late final TextEditingController _label;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _label = TextEditingController(text: widget.initialLabel);
  }

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Template details'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined,
                    size: 16, color: AppColors.textHint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(widget.fileName,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Template name',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Custom label (e.g. "CAP · Breast")',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Name is required'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            Navigator.pop(
                context, _TemplateMeta(name, _label.text.trim()));
          },
          icon: const Icon(Icons.save_rounded, size: 18),
          label: const Text('Save'),
        ),
      ],
    );
  }
}
