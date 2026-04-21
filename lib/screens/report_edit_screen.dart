import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/report_models.dart';
import '../services/hive_storage_service.dart';
import '../theme/app_theme.dart';

/// Edit every field of an existing [PathologyReport]: patient header,
/// lab number, report dates, each section (clinical / specimen / gross /
/// microscopy), summary, pathologist info, and status.
///
/// Save writes back to Hive (same id, so the detail screen stays in sync).
class ReportEditScreen extends StatefulWidget {
  final PathologyReport report;
  final ValueChanged<PathologyReport>? onSaved;

  const ReportEditScreen({
    super.key,
    required this.report,
    this.onSaved,
  });

  @override
  State<ReportEditScreen> createState() => _ReportEditScreenState();
}

class _ReportEditScreenState extends State<ReportEditScreen> {
  late final Map<String, TextEditingController> _c;
  late ReportStatus _status;
  late DateTime _sampleReceiptDate;
  late DateTime _reportedDate;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final r = widget.report;
    _c = {
      'reportNumber': TextEditingController(text: r.reportNumber),
      'patientId': TextEditingController(text: r.patientId),
      'patientName': TextEditingController(text: r.patientName),
      'patientAge':
          TextEditingController(text: r.patientAge == 0 ? '' : '${r.patientAge}'),
      'patientGender': TextEditingController(text: r.patientGender),
      'mrn': TextEditingController(text: r.mrn),
      'labNo': TextEditingController(text: r.labNo),
      'visitNo': TextEditingController(text: r.visitNo),
      'orderedBy': TextEditingController(text: r.orderedBy),
      'referredBy': TextEditingController(text: r.referredBy),
      'clinicalInformation':
          TextEditingController(text: r.clinicalInformation),
      'specimen': TextEditingController(text: r.specimen),
      'grossExamination': TextEditingController(text: r.grossExamination),
      'microscopyImpression':
          TextEditingController(text: r.microscopyImpression),
      'summary': TextEditingController(text: r.summary),
      'pathologistName': TextEditingController(text: r.pathologistName),
      'pathologistRegistration':
          TextEditingController(text: r.pathologistRegistration),
    };
    _status = r.status;
    _sampleReceiptDate = r.sampleReceiptDate;
    _reportedDate = r.reportedDate;

    for (final ctrl in _c.values) {
      ctrl.addListener(() {
        if (!_dirty) setState(() => _dirty = true);
      });
    }
  }

  @override
  void dispose() {
    for (final ctrl in _c.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final ageText = _c['patientAge']!.text.trim();
    final updated = widget.report.copyWith(
      reportNumber: _c['reportNumber']!.text.trim(),
      patientId: _c['patientId']!.text.trim(),
      patientName: _c['patientName']!.text.trim(),
      patientAge: int.tryParse(ageText) ?? 0,
      patientGender: _c['patientGender']!.text.trim(),
      mrn: _c['mrn']!.text.trim(),
      labNo: _c['labNo']!.text.trim(),
      visitNo: _c['visitNo']!.text.trim(),
      orderedBy: _c['orderedBy']!.text.trim(),
      referredBy: _c['referredBy']!.text.trim(),
      clinicalInformation: _c['clinicalInformation']!.text.trim(),
      specimen: _c['specimen']!.text.trim(),
      grossExamination: _c['grossExamination']!.text.trim(),
      microscopyImpression: _c['microscopyImpression']!.text.trim(),
      summary: _c['summary']!.text.trim(),
      pathologistName: _c['pathologistName']!.text.trim(),
      pathologistRegistration:
          _c['pathologistRegistration']!.text.trim(),
      status: _status,
      sampleReceiptDate: _sampleReceiptDate,
      reportedDate: _reportedDate,
    );
    await HiveStorageService.saveReport(updated);
    widget.onSaved?.call(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved ${updated.reportNumber}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop(updated);
  }

  Future<bool> _confirmLeaveIfDirty() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved edits.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _confirmLeaveIfDirty()) {
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text('Edit ${widget.report.reportNumber}'),
          actions: [
            TextButton.icon(
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save'),
              style: TextButton.styleFrom(
                foregroundColor:
                    _dirty ? AppColors.success : AppColors.textHint,
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _statusCard(),
                  const SizedBox(height: 16),
                  _headerCard(),
                  const SizedBox(height: 16),
                  _datesCard(),
                  const SizedBox(height: 16),
                  _sectionsCard(),
                  const SizedBox(height: 16),
                  _footerCard(),
                  const SizedBox(height: 24),
                  _bottomSaveButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Sections ───────────────────────────────────────────

  Widget _statusCard() {
    return _card(
      icon: Icons.flag_rounded,
      title: 'Status',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ReportStatus.values.map((s) {
          final selected = _status == s;
          final c = _colorFor(s);
          return ChoiceChip(
            label: Text(s.label),
            selected: selected,
            selectedColor: c.withOpacity(0.18),
            labelStyle: TextStyle(
              color: selected ? c : AppColors.textPrimary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            side: BorderSide(color: selected ? c : AppColors.border),
            onSelected: (_) => setState(() {
              _status = s;
              _dirty = true;
            }),
          );
        }).toList(),
      ),
    );
  }

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

  Widget _headerCard() {
    return _card(
      icon: Icons.person_rounded,
      title: 'Patient & report header',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _field('reportNumber', 'Report number (Lab No)')),
              const SizedBox(width: 12),
              Expanded(child: _field('patientId', 'Patient ID / MRN')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(flex: 3, child: _field('patientName', 'Patient name')),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: _field('patientAge', 'Age',
                    keyboard: TextInputType.number),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: _genderField()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _field('mrn', 'MRN (printed)')),
              const SizedBox(width: 12),
              Expanded(child: _field('labNo', 'Lab No')),
              const SizedBox(width: 12),
              Expanded(child: _field('visitNo', 'Visit No')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _field('orderedBy', 'Ordered by')),
              const SizedBox(width: 12),
              Expanded(child: _field('referredBy', 'Referred by')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _datesCard() {
    return _card(
      icon: Icons.schedule_rounded,
      title: 'Dates',
      child: Row(
        children: [
          Expanded(
            child: _dateField(
              label: 'Sample receipt',
              value: _sampleReceiptDate,
              onChanged: (d) => setState(() {
                _sampleReceiptDate = d;
                _dirty = true;
              }),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _dateField(
              label: 'Reported',
              value: _reportedDate,
              onChanged: (d) => setState(() {
                _reportedDate = d;
                _dirty = true;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionsCard() {
    return _card(
      icon: Icons.description_rounded,
      title: 'Report sections',
      child: Column(
        children: [
          _field('clinicalInformation', 'Clinical information', maxLines: 3),
          const SizedBox(height: 12),
          _field('specimen', 'Specimen', maxLines: 3),
          const SizedBox(height: 12),
          _field('grossExamination', 'Gross examination', maxLines: 5),
          const SizedBox(height: 12),
          _field('microscopyImpression', 'Microscopy and impression',
              maxLines: 6),
          const SizedBox(height: 12),
          _field('summary', 'Clinical summary', maxLines: 3),
        ],
      ),
    );
  }

  Widget _footerCard() {
    return _card(
      icon: Icons.badge_rounded,
      title: 'Pathologist',
      child: Row(
        children: [
          Expanded(flex: 3, child: _field('pathologistName', 'Name')),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child:
                _field('pathologistRegistration', 'Registration / KMC number'),
          ),
        ],
      ),
    );
  }

  Widget _bottomSaveButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: () async {
            if (await _confirmLeaveIfDirty()) {
              if (mounted) Navigator.of(context).pop();
            }
          },
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _dirty ? _save : null,
          icon: const Icon(Icons.save_rounded, size: 18),
          label: const Text('Save changes'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            padding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          ),
        ),
      ],
    );
  }

  // ─── Primitives ─────────────────────────────────────────

  Widget _card(
      {required IconData icon,
      required String title,
      required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
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
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _field(String key, String label,
      {int maxLines = 1, TextInputType? keyboard}) {
    return TextField(
      controller: _c[key],
      minLines: 1,
      maxLines: maxLines,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
      ),
    );
  }

  Widget _genderField() {
    final current = _c['patientGender']!.text.trim();
    final options = ['Male', 'Female', 'Other'];
    final matched = options.firstWhere(
      (o) => o.toLowerCase() == current.toLowerCase(),
      orElse: () => '',
    );
    return DropdownButtonFormField<String>(
      value: matched.isEmpty ? null : matched,
      isDense: true,
      decoration: const InputDecoration(
        labelText: 'Gender',
        isDense: true,
      ),
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: (v) {
        _c['patientGender']!.text = v ?? '';
        setState(() => _dirty = true);
      },
    );
  }

  Widget _dateField({
    required String label,
    required DateTime value,
    required ValueChanged<DateTime> onChanged,
  }) {
    final fmt = DateFormat('dd-MM-yyyy HH:mm');
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          initialDate: value,
        );
        if (d == null) return;
        if (!mounted) return;
        final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value),
        );
        onChanged(DateTime(
          d.year,
          d.month,
          d.day,
          t?.hour ?? value.hour,
          t?.minute ?? value.minute,
        ));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: const Icon(Icons.event_rounded, size: 18),
        ),
        child: Text(fmt.format(value),
            style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
