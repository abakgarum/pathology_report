import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/report_models.dart';
import '../services/hive_storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/audio_player_widget.dart';
import 'report_edit_screen.dart';

/// Report detail view — renders the stored report exactly in the template
/// format from the department (Histopathology Report layout) and offers
/// PDF export / print.
class ReportDetailScreen extends StatefulWidget {
  final PathologyReport report;
  final VoidCallback? onDeleted;

  const ReportDetailScreen({
    super.key,
    required this.report,
    this.onDeleted,
  });

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late PathologyReport _report;
  bool _showPlayback = false;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_report.reportNumber),
        actions: [
          if (_report.voiceRecordings.isNotEmpty)
            IconButton(
              onPressed: () =>
                  setState(() => _showPlayback = !_showPlayback),
              icon: Icon(_showPlayback
                  ? Icons.close_rounded
                  : Icons.play_circle_outline_rounded),
              tooltip: _showPlayback ? 'Hide playback' : 'Play recording',
            ),
          IconButton(
            onPressed: _openEdit,
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit',
          ),
          IconButton(
            onPressed: () => _exportPdf(context),
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Export PDF',
          ),
          IconButton(
            onPressed: () => _exportPdf(context, share: true),
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share PDF',
          ),
          IconButton(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusBar(
                  report: _report,
                  onChanged: _changeStatus,
                  onEdit: _openEdit,
                ),
                if (_showPlayback &&
                    _report.voiceRecordings.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _PlaybackPanel(report: _report),
                ],
                const SizedBox(height: 16),
                _TemplateView(r: _report),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeStatus(ReportStatus s) async {
    if (_report.status == s) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change status?'),
        content: Text(
            'Set ${_report.reportNumber} from "${_report.status.label}" to "${s.label}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final updated = _report.copyWith(status: s);
    await HiveStorageService.saveReport(updated);
    if (!mounted) return;
    setState(() => _report = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Status set to ${s.label}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openEdit() async {
    final updated = await Navigator.of(context).push<PathologyReport>(
      MaterialPageRoute(
        builder: (_) => ReportEditScreen(
          report: _report,
          onSaved: (r) => _report = r,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _report = updated);
    }
  }

  Future<void> _exportPdf(BuildContext context, {bool share = false}) async {
    final bytes = await _buildPdfBytes(_report);
    if (share) {
      await Printing.sharePdf(bytes: bytes, filename: '${_report.reportNumber}.pdf');
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete report?'),
        content: Text(
            '${_report.reportNumber} will be permanently removed along with its audio files.'),
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
    if (ok == true) {
      await HiveStorageService.deleteReport(_report.id);
      widget.onDeleted?.call();
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

// ─── Status bar (chip row + quick edit) ────────────────────────────

class _StatusBar extends StatelessWidget {
  final PathologyReport report;
  final ValueChanged<ReportStatus> onChanged;
  final VoidCallback onEdit;

  const _StatusBar({
    required this.report,
    required this.onChanged,
    required this.onEdit,
  });

  Color _colorFor(ReportStatus s) {
    switch (s) {
      case ReportStatus.draft:
        return AppColors.draft;
      case ReportStatus.pending:
        return AppColors.pending;
      case ReportStatus.completed:
        return AppColors.completed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_rounded,
              size: 16, color: AppColors.textHint),
          const SizedBox(width: 8),
          Text('Status',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AppColors.textHint)),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: ReportStatus.values.map((s) {
                final selected = report.status == s;
                final c = _colorFor(s);
                return ChoiceChip(
                  label: Text(s.label),
                  selected: selected,
                  selectedColor: c.withOpacity(0.18),
                  labelStyle: TextStyle(
                    color: selected ? c : AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  side: BorderSide(
                      color: selected ? c : AppColors.border),
                  onSelected: (_) => onChanged(s),
                );
              }).toList(),
            ),
          ),
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}

// ─── Playback panel: audio controls + generated script ──────────

class _PlaybackPanel extends StatefulWidget {
  final PathologyReport report;
  const _PlaybackPanel({required this.report});

  @override
  State<_PlaybackPanel> createState() => _PlaybackPanelState();
}

class _PlaybackPanelState extends State<_PlaybackPanel> {
  int _selectedClip = 0;

  String _generatedScript() {
    final r = widget.report;
    final parts = <String>[
      if (r.clinicalInformation.trim().isNotEmpty)
        'CLINICAL INFORMATION\n${r.clinicalInformation.trim()}',
      if (r.specimen.trim().isNotEmpty)
        'SPECIMEN\n${r.specimen.trim()}',
      if (r.grossExamination.trim().isNotEmpty)
        'GROSS EXAMINATION\n${r.grossExamination.trim()}',
      if (r.microscopyImpression.trim().isNotEmpty)
        'MICROSCOPY AND IMPRESSION\n${r.microscopyImpression.trim()}',
    ];
    if (parts.isEmpty) return r.rawTranscript.trim();
    return parts.join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final clips = widget.report.voiceRecordings;
    if (clips.isEmpty) return const SizedBox.shrink();
    final clip = clips[_selectedClip.clamp(0, clips.length - 1)];
    final script = _generatedScript();
    final isWide = MediaQuery.of(context).size.width > 820;

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (clips.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < clips.length; i++)
                  ChoiceChip(
                    label: Text(
                      clips[i].label.isEmpty
                          ? 'Clip ${i + 1}'
                          : clips[i].label,
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: _selectedClip == i,
                    onSelected: (_) => setState(() => _selectedClip = i),
                  ),
              ],
            ),
          ),
        AudioPlayerWidget(
          key: ValueKey(clip.id),
          filePath: clip.filePath,
          title: clip.label.isEmpty
              ? 'Recording ${_selectedClip + 1}'
              : clip.label,
        ),
      ],
    );

    final right = Container(
      padding: const EdgeInsets.all(16),
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
              const Icon(Icons.description_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('Generated script',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: SelectableText(
                script.isEmpty ? '— no script generated yet —' : script,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return isWide
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: 16),
                Expanded(child: right),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: 12),
              right,
            ],
          );
  }
}

// ─── Visual template (matches the scanned lab report) ─────────────

class _TemplateView extends StatelessWidget {
  final PathologyReport r;
  const _TemplateView({required this.r});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd-MM-yyyy hh:mm a');
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text('DEPARTMENT OF LABORATORY MEDICINE',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4)),
          ),
          const SizedBox(height: 14),
          _infoGrid(fmt),
          const Divider(height: 26, thickness: 1),
          const Center(
            child: Text(
              'HISTOPATHOLOGY REPORT',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.underline),
            ),
          ),
          const SizedBox(height: 14),
          _inline('LAB NUMBER', r.reportNumber),
          const SizedBox(height: 10),
          _section('CLINICAL INFORMATION', r.clinicalInformation),
          _section('SPECIMEN', r.specimen),
          _section('GROSS EXAMINATION', r.grossExamination),
          _section('MICROSCOPY AND IMPRESSION', r.microscopyImpression),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('***Surgical specimens will be discarded after two (2) months.',
                    style: TextStyle(fontSize: 11)),
                Text('***Slides or Paraffin Blocks will be issued only on request.',
                    style: TextStyle(fontSize: 11)),
                Text('***Immunohistochemistry slides will not be provided.',
                    style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(r.pathologistName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text(r.pathologistRegistration,
                    style: const TextStyle(fontSize: 12)),
                const Text(
                    'Consultant & Head - Histopathology & Laboratory Medicine',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoGrid(DateFormat fmt) {
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 130,
                child: Text(l,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const Text(': ', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Text(v,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis),
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
              row('Name', r.patientName.isEmpty ? '—' : 'Mr ${r.patientName}'),
              row('MRN', r.mrn.isEmpty ? r.patientId : r.mrn),
              row('Age', r.patientAge > 0 ? 'Y ${r.patientAge} Y' : '—'),
              row('Ordered by', r.orderedBy.isEmpty ? '—' : r.orderedBy),
              row('Referred by', r.referredBy.isEmpty ? '—' : r.referredBy),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('Lab No', r.labNo.isEmpty ? '—' : r.labNo),
              row('Visit No', r.visitNo.isEmpty ? '—' : r.visitNo),
              row('Gender', r.patientGender.isEmpty ? '—' : r.patientGender),
              row('Sample Receipt Date', fmt.format(r.sampleReceiptDate)),
              row('Reported Date', fmt.format(r.reportedDate)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _inline(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ),
        const Text(': '),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    );
  }

  Widget _section(String label, String body) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 210,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const Text(': '),
          Expanded(
            child: Text(body,
                style: const TextStyle(fontSize: 12, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ─── PDF generation (matches on-screen template) ──────────────

Future<Uint8List> _buildPdfBytes(PathologyReport r) async {
  final doc = pw.Document();
  final fmt = DateFormat('dd-MM-yyyy hh:mm a');

  pw.Widget row(String l, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 110,
              child: pw.Text(l,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text(': ', style: const pw.TextStyle(fontSize: 10)),
            pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontSize: 10))),
          ],
        ),
      );

  pw.Widget sect(String label, String body) {
    if (body.trim().isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 190,
            child: pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text(': ', style: const pw.TextStyle(fontSize: 10)),
          pw.Expanded(
            child: pw.Text(body,
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 2)),
          ),
        ],
      ),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Center(
          child: pw.Text('DEPARTMENT OF LABORATORY MEDICINE',
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  row('Name',
                      r.patientName.isEmpty ? '—' : 'Mr ${r.patientName}'),
                  row('MRN', r.mrn.isEmpty ? r.patientId : r.mrn),
                  row('Age', r.patientAge > 0 ? 'Y ${r.patientAge} Y' : '—'),
                  row('Ordered by', r.orderedBy.isEmpty ? '—' : r.orderedBy),
                  row('Referred by',
                      r.referredBy.isEmpty ? '—' : r.referredBy),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  row('Lab No', r.labNo.isEmpty ? '—' : r.labNo),
                  row('Visit No', r.visitNo.isEmpty ? '—' : r.visitNo),
                  row('Gender',
                      r.patientGender.isEmpty ? '—' : r.patientGender),
                  row('Sample Receipt Date', fmt.format(r.sampleReceiptDate)),
                  row('Reported Date', fmt.format(r.reportedDate)),
                ],
              ),
            ),
          ],
        ),
        pw.Divider(thickness: 1),
        pw.Center(
          child: pw.Text('HISTOPATHOLOGY REPORT',
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  decoration: pw.TextDecoration.underline)),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 110,
              child: pw.Text('LAB NUMBER',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text(': ', style: const pw.TextStyle(fontSize: 10)),
            pw.Expanded(
                child: pw.Text(r.reportNumber,
                    style: const pw.TextStyle(fontSize: 10))),
          ],
        ),
        pw.SizedBox(height: 4),
        sect('CLINICAL INFORMATION', r.clinicalInformation),
        sect('SPECIMEN', r.specimen),
        sect('GROSS EXAMINATION', r.grossExamination),
        sect('MICROSCOPY AND IMPRESSION', r.microscopyImpression),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                  '***Surgical specimens will be discarded after two (2) months.',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.Text(
                  '***Slides or Paraffin Blocks will be issued only on request.',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.Text(
                  '***Immunohistochemistry slides will not be provided.',
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
        pw.SizedBox(height: 28),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(r.pathologistName,
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text(r.pathologistRegistration,
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Text(
                  'Consultant & Head - Histopathology & Laboratory Medicine',
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ],
    ),
  );

  return doc.save();
}
