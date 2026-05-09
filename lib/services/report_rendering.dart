import '../models/report_models.dart';
import 'hive_storage_service.dart';

/// Shared formatting helpers used by BOTH the on-screen report view and
/// the PDF builder. Keeping the data-shaping logic in one place prevents
/// the two renderers from drifting apart (which they did when the
/// diagnosis headline was added on-screen but not in the PDF).
///
/// The renderers themselves stay separate — Flutter Material vs `pdf`
/// package widgets — but they consume the same intermediate shapes
/// (SynopticRow, SynopticGroup, StagingRow, ...).

/// One CAP-style "Element: Response" pair in the SYNOPTIC SUMMARY block.
class SynopticRow {
  final String label;
  final String value;

  /// True when the value represents a positive / abnormal finding so the
  /// renderer can bold it. Detected from the value text — "POSITIVE",
  /// "INVOLVED", non-zero counts, etc.
  final bool isPositive;

  /// True when the original answer was empty and we substituted an
  /// explicit "Not identified" / "—". Renderers may dim these.
  final bool isFallback;

  const SynopticRow({
    required this.label,
    required this.value,
    this.isPositive = false,
    this.isFallback = false,
  });
}

/// A logical group of SynopticRows (== one section of the template
/// schema). Renderers may show the title as a sub-heading or skip it
/// when there is only one section.
class SynopticGroup {
  final String title;
  final List<SynopticRow> rows;
  const SynopticGroup({required this.title, required this.rows});
}

/// One row of the STAGING SUMMARY box (label : value).
class StagingRow {
  final String label;
  final String value;
  const StagingRow({required this.label, required this.value});
}

/// Build the list of SynopticGroups for a report. Resolution order:
///   1. If the report has `templateId` set AND the template schema is in
///      Hive, walk the schema in author order and pull each question's
///      answer from `synopticAnswers`. Empty answers are skipped (we do
///      NOT pad with "—" because schemas can have hundreds of questions
///      and a real synoptic only fills 10–30).
///   2. Otherwise, return an empty list — the renderer falls back to the
///      free-text microscopy block.
///
/// Gross-tagged sections (kind == 'gross') are routed to
/// [grossGroupsFor] and excluded here.
List<SynopticGroup> synopticGroupsFor(PathologyReport r) =>
    _groupsFor(r, kind: 'synoptic');

/// Same as [synopticGroupsFor] but for grossing-station sections —
/// orientation, ink map, distance to margins, # nodes by station,
/// Quirke grade, Breslow, etc. Renders under SPECIMEN & GROSS
/// EXAMINATION in the final report.
List<SynopticGroup> grossGroupsFor(PathologyReport r) =>
    _groupsFor(r, kind: 'gross');

List<SynopticGroup> _groupsFor(PathologyReport r, {required String kind}) {
  if (r.templateId.isEmpty) return const [];
  final schema = HiveStorageService.getTemplateSchema(r.templateId);
  if (schema == null) return const [];

  final groups = <SynopticGroup>[];
  for (final section in schema.sections) {
    if (section.kind != kind) continue;
    final rows = <SynopticRow>[];
    for (final q in section.questions) {
      final raw = r.synopticAnswers[q.id];
      final text = formatAnswerValue(raw, q);
      if (text.isEmpty) continue; // skip unanswered questions
      rows.add(SynopticRow(
        label: q.label,
        value: text,
        isPositive: isPositiveValue(text),
      ));
    }
    if (rows.isNotEmpty) {
      groups.add(SynopticGroup(title: section.title, rows: rows));
    }
  }
  return groups;
}

/// Build the rows for the STAGING SUMMARY box. Prefers structured
/// `staging` fields; falls back to the legacy `pathologicStaging` string
/// for older reports (which renders as a single "pTNM" row).
List<StagingRow> stagingRowsFor(PathologyReport r) {
  final s = r.staging;
  if (!s.isEmpty) {
    return [
      if (s.pT.isNotEmpty) StagingRow(label: 'pT', value: s.pT),
      if (s.pN.isNotEmpty) StagingRow(label: 'pN', value: s.pN),
      if (s.pM.isNotEmpty) StagingRow(label: 'pM', value: s.pM),
      if (s.stageGroup.isNotEmpty)
        StagingRow(label: 'Stage Group', value: s.stageGroup),
      if (s.prefix.isNotEmpty) StagingRow(label: 'Prefix', value: s.prefix),
      if (s.ajccEdition.isNotEmpty)
        StagingRow(label: 'Edition', value: s.ajccEdition),
      if (s.additional.isNotEmpty)
        StagingRow(label: 'Additional', value: s.additional),
    ];
  }
  if (r.pathologicStaging.trim().isNotEmpty) {
    return [StagingRow(label: 'pTNM', value: r.pathologicStaging.trim())];
  }
  return const [];
}

/// Coerce a synoptic answer (which may be a String, List<String>, num,
/// bool, or null) into a display string. For singleSelect / text we
/// return the raw value; for multiSelect we join with ", "; for numerics
/// we append the question's units. Empty results signal "skip this row"
/// to the caller.
String formatAnswerValue(dynamic raw, TemplateQuestion q) {
  if (raw == null) return '';
  if (raw is String) return raw.trim();
  if (raw is bool) return raw ? 'Yes' : 'No';
  if (raw is num) {
    final text = raw == raw.toInt() ? raw.toInt().toString() : raw.toString();
    return q.units.isEmpty ? text : '$text ${q.units}';
  }
  if (raw is List) {
    final parts = raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.join(', ');
  }
  return raw.toString().trim();
}

/// Heuristic — true if the value text suggests a POSITIVE / abnormal
/// finding. Used by the renderer to bold the value (Valenstein 2008
/// found bolded positives + explicit negatives are read 17% faster).
bool isPositiveValue(String value) {
  final v = value.toUpperCase();
  if (v == 'NO' || v == 'NEGATIVE' || v == 'NOT IDENTIFIED' ||
      v == 'NOT APPLICABLE' || v == 'ABSENT' || v == 'NONE' || v == '—') {
    return false;
  }
  for (final marker in const [
    'POSITIVE', 'PRESENT', 'INVOLVED', 'IDENTIFIED', 'MACROMET',
    'EXTENSIVE', 'INVASIVE', 'METASTATIC', 'MUTATED', 'AMPLIFIED',
    'HIGH GRADE', 'GRADE 3', 'POOR'
  ]) {
    if (v.contains(marker)) return true;
  }
  return false;
}

/// Substitute an explicit, easy-to-scan placeholder for empty values
/// in fields where SILENCE COULD BE MISREAD (margins, LVI, PNI, etc.).
/// Renderers should call this only on those critical fields, not on
/// every blank — over-applying clutters the report.
String orNotIdentified(String value) =>
    value.trim().isEmpty ? 'Not identified' : value.trim();
