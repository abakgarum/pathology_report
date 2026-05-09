import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/report_models.dart';
import '../services/hive_storage_service.dart';
import '../services/settings_service.dart';
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
  late String _cancerType;
  // Live-edited copies of the structured tables. Built from the report on
  // initState; serialised back on _save.
  late List<_IhcDraft> _ihcDrafts;
  bool _dirty = false;

  // Cancer-type tag for the dropdown. Drives template selection in a
  // future iteration; today it's a free-form label only.
  static const Map<String, String> _cancerTypes = {
    '': '— Not specified —',
    'breast_invasive': 'Breast — invasive carcinoma',
    'breast_dcis': 'Breast — DCIS',
    'colorectal': 'Colorectal carcinoma',
    'gastric': 'Gastric carcinoma',
    'esophageal': 'Esophageal carcinoma',
    'liver_hcc': 'Liver / HCC',
    'prostate': 'Prostate adenocarcinoma',
    'bladder': 'Urothelial carcinoma',
    'kidney': 'Renal cell carcinoma',
    'lung': 'Lung carcinoma',
    'endometrial': 'Endometrial carcinoma',
    'cervical': 'Cervical carcinoma',
    'ovarian': 'Ovarian / tubal',
    'thyroid': 'Thyroid carcinoma',
    'melanoma': 'Cutaneous melanoma',
    'head_neck': 'Head & neck SCC',
    'lymph_node': 'Lymph node / lymphoma',
    'small_biopsy': 'Small biopsy / cores',
    'other': 'Other',
  };

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
      'microscopicDescription':
          TextEditingController(text: r.microscopicDescription),
      'diagnosisHeadline':
          TextEditingController(text: r.diagnosisHeadline),
      'comment': TextEditingController(text: r.comment),
      // Structured staging — one controller per pTNM component.
      'pT': TextEditingController(text: r.staging.pT),
      'pN': TextEditingController(text: r.staging.pN),
      'pM': TextEditingController(text: r.staging.pM),
      'stageGroup': TextEditingController(text: r.staging.stageGroup),
      'stagingPrefix': TextEditingController(text: r.staging.prefix),
      'ajccEdition': TextEditingController(text: r.staging.ajccEdition),
      'stagingAdditional':
          TextEditingController(text: r.staging.additional),
      // Legacy free-text staging — preserved as a fallback for older
      // reports (the renderer prefers the structured fields above).
      'pathologicStaging':
          TextEditingController(text: r.pathologicStaging),
      'summary': TextEditingController(text: r.summary),
      'pathologistName': TextEditingController(text: r.pathologistName),
      'pathologistRegistration':
          TextEditingController(text: r.pathologistRegistration),
      'pathologistName2': TextEditingController(text: r.pathologistName2),
      'pathologistRegistration2':
          TextEditingController(text: r.pathologistRegistration2),
    };
    _status = r.status;
    _sampleReceiptDate = r.sampleReceiptDate;
    _reportedDate = r.reportedDate;
    _cancerType = r.cancerType;
    _ihcDrafts = r.ihcResults.map(_IhcDraft.fromEntry).toList();

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
    for (final d in _ihcDrafts) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final ageText = _c['patientAge']!.text.trim();
    final staging = StagingSummary(
      prefix: _c['stagingPrefix']!.text.trim(),
      pT: _c['pT']!.text.trim(),
      pN: _c['pN']!.text.trim(),
      pM: _c['pM']!.text.trim(),
      stageGroup: _c['stageGroup']!.text.trim(),
      ajccEdition: _c['ajccEdition']!.text.trim(),
      additional: _c['stagingAdditional']!.text.trim(),
    );
    final ihc = _ihcDrafts
        .map((d) => d.toEntry())
        .where((e) => !e.isEmpty)
        .toList();
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
      microscopicDescription:
          _c['microscopicDescription']!.text.trim(),
      diagnosisHeadline: _c['diagnosisHeadline']!.text.trim(),
      pathologicStaging: _c['pathologicStaging']!.text.trim(),
      staging: staging,
      ihcResults: ihc,
      comment: _c['comment']!.text.trim(),
      cancerType: _cancerType,
      summary: _c['summary']!.text.trim(),
      pathologistName: _c['pathologistName']!.text.trim(),
      pathologistRegistration:
          _c['pathologistRegistration']!.text.trim(),
      pathologistName2: _c['pathologistName2']!.text.trim(),
      pathologistRegistration2:
          _c['pathologistRegistration2']!.text.trim(),
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
                  _diagnosisCard(),
                  const SizedBox(height: 16),
                  _stagingCard(),
                  const SizedBox(height: 16),
                  _ihcCard(),
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
      title: 'Report body',
      child: Column(
        children: [
          _field('clinicalInformation', 'Clinical information', maxLines: 3),
          const SizedBox(height: 12),
          _field('specimen', 'Specimen', maxLines: 3),
          const SizedBox(height: 12),
          _field('grossExamination', 'Gross examination', maxLines: 5),
          const SizedBox(height: 12),
          _field('microscopicDescription',
              'Microscopic description (prose)',
              maxLines: 5),
          const SizedBox(height: 12),
          _field('microscopyImpression',
              'Microscopy / synoptic free-text (legacy fallback)',
              maxLines: 5),
          const SizedBox(height: 12),
          _field('comment', 'Comment / interpretation / MDT note',
              maxLines: 4),
          const SizedBox(height: 12),
          _field('summary', 'Clinical summary (legacy)', maxLines: 2),
        ],
      ),
    );
  }

  /// Cancer type + diagnosis headline. The headline is the report's
  /// visual anchor (rendered top-of-page), so it gets its own card
  /// instead of being buried in the section list.
  Widget _diagnosisCard() {
    return _card(
      icon: Icons.center_focus_strong_rounded,
      title: 'Diagnosis',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: _cancerType.isEmpty ? '' : _cancerType,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Cancer type / specimen family',
              isDense: true,
            ),
            items: _cancerTypes.entries
                .map((e) => DropdownMenuItem(
                    value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() {
              _cancerType = v ?? '';
              _dirty = true;
            }),
          ),
          const SizedBox(height: 12),
          _field('diagnosisHeadline',
              'Final diagnosis (rendered as the FINAL DIAGNOSIS box)',
              maxLines: 5),
        ],
      ),
    );
  }

  /// Pathologic staging — structured pT/pN/pM/Stage Group editor.
  /// The legacy `pathologicStaging` free-text field is kept at the
  /// bottom as a fallback for old reports / non-AJCC schemes.
  Widget _stagingCard() {
    return _card(
      icon: Icons.numbers_rounded,
      title: 'Pathologic staging',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _field('pT', 'pT')),
              const SizedBox(width: 12),
              Expanded(child: _field('pN', 'pN')),
              const SizedBox(width: 12),
              Expanded(child: _field('pM', 'pM')),
              const SizedBox(width: 12),
              Expanded(child: _field('stageGroup', 'Stage group')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child:
                      _field('stagingPrefix', 'Prefix (p / yp / rp / a)')),
              const SizedBox(width: 12),
              Expanded(
                  child:
                      _field('ajccEdition', 'AJCC edition (e.g. 8th)')),
            ],
          ),
          const SizedBox(height: 12),
          _field('stagingAdditional',
              'Additional prognostic remark (optional)', maxLines: 2),
          const SizedBox(height: 12),
          _field('pathologicStaging',
              'Legacy free-text staging (used only if structured fields above are blank)'),
        ],
      ),
    );
  }

  /// IHC / ancillary studies table editor. Each row is a draft with
  /// its own controllers. Add / remove rows below the table.
  Widget _ihcCard() {
    return _card(
      icon: Icons.science_rounded,
      title: 'Ancillary studies — IHC',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_ihcDrafts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No IHC rows yet — add a marker below.',
                style: TextStyle(
                    fontSize: 12.5, color: AppColors.textHint),
              ),
            )
          else
            for (var i = 0; i < _ihcDrafts.length; i++) ...[
              _ihcRow(i),
              if (i < _ihcDrafts.length - 1)
                const Divider(height: 24),
            ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                _ihcDrafts.add(_IhcDraft());
                _dirty = true;
              }),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add IHC marker'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ihcRow(int i) {
    final d = _ihcDrafts[i];
    Widget cell(TextEditingController c, String label,
        {int flex = 1, int maxLines = 1}) {
      return Expanded(
        flex: flex,
        child: TextField(
          controller: c,
          minLines: 1,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
          ),
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cell(d.marker, 'Marker', flex: 3),
        const SizedBox(width: 8),
        cell(d.clone, 'Clone', flex: 2),
        const SizedBox(width: 8),
        cell(d.result, 'Result', flex: 4),
        const SizedBox(width: 8),
        cell(d.intensity, 'Intensity', flex: 2),
        const SizedBox(width: 8),
        cell(d.percent, '% cells', flex: 2),
        IconButton(
          tooltip: 'Remove row',
          onPressed: () => setState(() {
            _ihcDrafts.removeAt(i).dispose();
            _dirty = true;
          }),
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
        ),
      ],
    );
  }

  Widget _footerCard() {
    final dualSnapshotted =
        widget.report.pathologistName2.trim().isNotEmpty;
    final dualEnabled =
        dualSnapshotted || SettingsService.getDualSignatureEnabled();
    return _card(
      icon: Icons.badge_rounded,
      title: 'Pathologist',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(flex: 3, child: _field('pathologistName', 'Name')),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _field(
                    'pathologistRegistration', 'Registration / KMC number'),
              ),
            ],
          ),
          if (dualEnabled) ...[
            const SizedBox(height: 16),
            const Text('Second signatory (dual sign-out)',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    flex: 3, child: _field('pathologistName2', 'Name')),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _field('pathologistRegistration2',
                      'Registration / KMC number'),
                ),
              ],
            ),
          ],
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

/// One row of the IHC table while it's being edited. Each draft owns
/// its own controllers so typing in row N doesn't rebuild rows 0..N-1.
/// Converted to/from `IhcEntry` at load and save time.
class _IhcDraft {
  final TextEditingController marker;
  final TextEditingController clone;
  final TextEditingController result;
  final TextEditingController intensity;
  final TextEditingController percent;
  final TextEditingController note;

  _IhcDraft({
    String marker = '',
    String clone = '',
    String result = '',
    String intensity = '',
    String percent = '',
    String note = '',
  })  : marker = TextEditingController(text: marker),
        clone = TextEditingController(text: clone),
        result = TextEditingController(text: result),
        intensity = TextEditingController(text: intensity),
        percent = TextEditingController(text: percent),
        note = TextEditingController(text: note);

  factory _IhcDraft.fromEntry(IhcEntry e) => _IhcDraft(
        marker: e.marker,
        clone: e.clone,
        result: e.result,
        intensity: e.intensity,
        percent: e.percent,
        note: e.note,
      );

  IhcEntry toEntry() => IhcEntry(
        marker: marker.text.trim(),
        clone: clone.text.trim(),
        result: result.text.trim(),
        intensity: intensity.text.trim(),
        percent: percent.text.trim(),
        note: note.text.trim(),
      );

  void dispose() {
    marker.dispose();
    clone.dispose();
    result.dispose();
    intensity.dispose();
    percent.dispose();
    note.dispose();
  }
}
