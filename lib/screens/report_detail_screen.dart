import 'dart:io';
import 'dart:typed_data';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/report_models.dart';
import '../services/hive_storage_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/audio_player_widget.dart';
import 'report_edit_screen.dart';

/// Report detail view — renders the stored report exactly in the template
/// format from the department (Histopathology Report layout) and offers
/// PDF export / print, with QR code (encoding the report's stable UUID)
/// and a configurable "Powered by" watermark on every PDF page.
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

/// QR payload — opaque, no PHI ever. Matches the printed PDF.
String _qrPayloadFor(PathologyReport r) =>
    'pathlabpro://report/${r.reportUuid}';

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
    final clinicName = SettingsService.getClinicName();
    final clinicAddr = SettingsService.getClinicAddress();
    final logoPath = SettingsService.getClinicLogoPath();
    final hasLogo = logoPath.isNotEmpty && File(logoPath).existsSync();
    final printBarcode = SettingsService.getPrintLinearBarcode();
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
          // Header: logo (if any) + clinic name + QR code stack on the right.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasLogo) ...[
                SizedBox(
                  height: 56,
                  child: Image.file(File(logoPath), fit: BoxFit.contain),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(clinicName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4)),
                    if (clinicAddr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(clinicAddr,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  BarcodeWidget(
                    barcode: Barcode.qrCode(),
                    data: _qrPayloadFor(r),
                    width: 70,
                    height: 70,
                    drawText: false,
                  ),
                  const SizedBox(height: 4),
                  Text(r.reportNumber,
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                  if (printBarcode)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: BarcodeWidget(
                        barcode: Barcode.code128(),
                        data: r.reportUuid,
                        width: 120,
                        height: 28,
                        drawText: false,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _infoGrid(fmt),
          const Divider(
              height: 28,
              thickness: 1.4,
              color: AppColors.textPrimary),
          const Center(
            child: Text(
              'HISTOPATHOLOGY REPORT',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: AppColors.textPrimary,
                  decoration: TextDecoration.underline,
                  decorationThickness: 1.5),
            ),
          ),
          const SizedBox(height: 14),
          _inline('LAB NUMBER', r.reportNumber),
          const SizedBox(height: 10),
          _section('CLINICAL INFORMATION', r.clinicalInformation),
          // Diagnosis-first ordering — the BOTTOM-LINE diagnosis sits at
          // the TOP of the report (after Clinical Information). This is
          // the convention every major lab uses: pathologists, treating
          // clinicians, and tumour-board readers all want the dx first
          // and the supporting evidence (Gross / Microscopy) below.
          _diagnosisHeadlineBlock(),
          if (r.pathologicStaging.trim().isNotEmpty)
            _section('PATHOLOGIC STAGING', r.pathologicStaging),
          _section('SPECIMEN', r.specimen),
          _section('GROSS EXAMINATION', r.grossExamination),
          _section('MICROSCOPY', r.microscopyImpression),
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
          _signatureBlock(),
        ],
      ),
    );
  }

  Widget _infoGrid(DateFormat fmt) {
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 130,
                child: Text(l,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              const Text(': ',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Expanded(
                child: Text(v,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary),
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
              row('Name', r.patientName.isEmpty ? '—' : r.patientName),
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
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                  color: AppColors.textPrimary)),
        ),
        const Text(': ',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary)),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary))),
      ],
    );
  }

  /// Diagnosis-first headline block. Falls back to the `summary` field
  /// (which existed before we introduced `diagnosisHeadline`) so old
  /// reports still get a meaningful top-of-page statement. If neither
  /// is present, renders nothing — the renderer collapses gracefully.
  Widget _diagnosisHeadlineBlock() {
    final body = r.diagnosisHeadline.trim().isNotEmpty
        ? r.diagnosisHeadline.trim()
        : r.summary.trim();
    if (body.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: AppColors.primary, width: 4),
            top: BorderSide(color: AppColors.border),
            right: BorderSide(color: AppColors.border),
            bottom: BorderSide(color: AppColors.border),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'HISTOPATHOLOGY DIAGNOSIS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Signature block at the bottom of the on-screen report. If the report
  /// was saved while dual sign-out was enabled (i.e. `pathologistName2` is
  /// non-empty) we render two signatory columns; otherwise just the primary.
  Widget _signatureBlock() {
    final title1 = SettingsService.getPathologistTitle();
    final title2 = SettingsService.getPathologist2Title();
    final hasSecond = r.pathologistName2.trim().isNotEmpty;

    Widget signatory(String name, String reg, String title,
        {required CrossAxisAlignment align}) {
      return Column(
        crossAxisAlignment: align,
        children: [
          Text(name,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          Text(reg, style: const TextStyle(fontSize: 12)),
          Text(title, style: const TextStyle(fontSize: 12)),
        ],
      );
    }

    if (!hasSecond) {
      return Align(
        alignment: Alignment.centerRight,
        child: signatory(r.pathologistName, r.pathologistRegistration, title1,
            align: CrossAxisAlignment.end),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: signatory(
              r.pathologistName2, r.pathologistRegistration2, title2,
              align: CrossAxisAlignment.start),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: signatory(
              r.pathologistName, r.pathologistRegistration, title1,
              align: CrossAxisAlignment.end),
        ),
      ],
    );
  }

  Widget _section(String label, String body) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 210,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    color: AppColors.textPrimary)),
          ),
          const Text(': ',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
          Expanded(
            child: Text(body,
                style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ─── PDF generation (matches on-screen template, with QR + watermark) ──────

Future<Uint8List> _buildPdfBytes(PathologyReport r) async {
  final doc = pw.Document();
  final fmt = DateFormat('dd-MM-yyyy hh:mm a');

  final clinicName = SettingsService.getClinicName();
  final clinicAddr = SettingsService.getClinicAddress();
  final clinicPhone = SettingsService.getClinicPhone();
  final clinicEmail = SettingsService.getClinicEmail();
  final clinicWebsite = SettingsService.getClinicWebsite();
  final logoPath = SettingsService.getClinicLogoPath();
  final watermark = SettingsService.getPdfWatermarkText();
  final printBarcode = SettingsService.getPrintLinearBarcode();
  final pathologistTitle = SettingsService.getPathologistTitle();

  pw.MemoryImage? logoImage;
  if (logoPath.isNotEmpty) {
    final f = File(logoPath);
    if (await f.exists()) {
      logoImage = pw.MemoryImage(await f.readAsBytes());
    }
  }

  pw.Widget row(String l, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 110,
              child: pw.Text(l,
                  style: pw.TextStyle(
                      fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text(': ',
                style: pw.TextStyle(
                    fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            pw.Expanded(
                child: pw.Text(v,
                    style: const pw.TextStyle(fontSize: 10.5))),
          ],
        ),
      );

  pw.Widget sect(String label, String body) {
    if (body.trim().isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 190,
            child: pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.3)),
          ),
          pw.Text(': ',
              style: pw.TextStyle(
                  fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
          pw.Expanded(
            child: pw.Text(body,
                style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 2.5)),
          ),
        ],
      ),
    );
  }

  /// Diagnosis-first headline block in the PDF — tinted box with a
  /// coloured left rule, mirroring the on-screen renderer.
  pw.Widget diagnosisBlock() {
    final body = r.diagnosisHeadline.trim().isNotEmpty
        ? r.diagnosisHeadline.trim()
        : r.summary.trim();
    if (body.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFEFF6FB),
          border: pw.Border(
            left: pw.BorderSide(width: 3, color: PdfColors.blueGrey700),
            top: pw.BorderSide(width: 0.5, color: PdfColors.grey400),
            right: pw.BorderSide(width: 0.5, color: PdfColors.grey400),
            bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey400),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('HISTOPATHOLOGY DIAGNOSIS',
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.5,
                    color: PdfColors.blueGrey800)),
            pw.SizedBox(height: 4),
            pw.Text(body,
                style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    lineSpacing: 3)),
          ],
        ),
      ),
    );
  }

  // Per-page watermark — drawn behind the report content via PageTheme
  // background. Skip if the user has cleared the text in Settings.
  pw.PageTheme pageTheme() {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      buildBackground: watermark.isEmpty
          ? null
          : (ctx) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Watermark.text(
                  watermark,
                  style: pw.TextStyle(
                    color: PdfColors.grey300,
                    fontSize: 60,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
    );
  }

  final clinicContact = [
    if (clinicPhone.isNotEmpty) clinicPhone,
    if (clinicEmail.isNotEmpty) clinicEmail,
    if (clinicWebsite.isNotEmpty) clinicWebsite,
  ].join(' · ');

  doc.addPage(
    pw.MultiPage(
      pageTheme: pageTheme(),
      build: (context) => [
        // Header: logo (left) + clinic name (center) + QR stack (right).
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoImage != null) ...[
              pw.SizedBox(
                width: 54,
                height: 54,
                child: pw.Image(logoImage, fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 12),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(clinicName,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  if (clinicAddr.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text(clinicAddr,
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(fontSize: 9)),
                    ),
                  if (clinicContact.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text(clinicContact,
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(fontSize: 9)),
                    ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: _qrPayloadFor(r),
                  width: 60,
                  height: 60,
                  drawText: false,
                ),
                pw.SizedBox(height: 3),
                pw.Text(r.reportNumber,
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
                if (printBarcode)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: r.reportUuid,
                      width: 110,
                      height: 22,
                      drawText: false,
                    ),
                  ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.6),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  row('Name',
                      r.patientName.isEmpty ? '—' : r.patientName),
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
        pw.Divider(thickness: 1.2),
        pw.Center(
          child: pw.Text('HISTOPATHOLOGY REPORT',
              style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.5,
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
                      fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text(': ',
                style: pw.TextStyle(
                    fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            pw.Expanded(
                child: pw.Text(r.reportNumber,
                    style: pw.TextStyle(
                        fontSize: 10.5,
                        fontWeight: pw.FontWeight.bold))),
          ],
        ),
        pw.SizedBox(height: 4),
        // Diagnosis-first ordering — same as the on-screen renderer.
        // Clinical context, then the BOTTOM-LINE diagnosis (highlighted),
        // then optional staging, then the supporting evidence.
        sect('CLINICAL INFORMATION', r.clinicalInformation),
        diagnosisBlock(),
        if (r.pathologicStaging.trim().isNotEmpty)
          sect('PATHOLOGIC STAGING', r.pathologicStaging),
        sect('SPECIMEN', r.specimen),
        sect('GROSS EXAMINATION', r.grossExamination),
        sect('MICROSCOPY', r.microscopyImpression),
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
        _pdfSignatureBlock(r, pathologistTitle),
      ],
    ),
  );

  return doc.save();
}

/// PDF signature block: dual side-by-side when the report carries a second
/// pathologist (snapshotted at save time when dual sign-out was on);
/// otherwise the single right-aligned block we've always rendered.
pw.Widget _pdfSignatureBlock(PathologyReport r, String primaryTitle) {
  final hasSecond = r.pathologistName2.trim().isNotEmpty;
  final secondTitle = SettingsService.getPathologist2Title();

  pw.Widget signatory(String name, String reg, String title,
      {required pw.CrossAxisAlignment align}) {
    return pw.Column(
      crossAxisAlignment: align,
      children: [
        pw.Text(name,
            style:
                pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Text(reg, style: const pw.TextStyle(fontSize: 10)),
        pw.Text(title, style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }

  if (!hasSecond) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: signatory(
          r.pathologistName, r.pathologistRegistration, primaryTitle,
          align: pw.CrossAxisAlignment.end),
    );
  }
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: signatory(
            r.pathologistName2, r.pathologistRegistration2, secondTitle,
            align: pw.CrossAxisAlignment.start),
      ),
      pw.SizedBox(width: 24),
      pw.Expanded(
        child: signatory(
            r.pathologistName, r.pathologistRegistration, primaryTitle,
            align: pw.CrossAxisAlignment.end),
      ),
    ],
  );
}
