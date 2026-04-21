import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/report_models.dart';

/// Single source of truth for persisted pathology data.
///
/// Boxes:
///   - `patients`   : Patient keyed by patientId
///   - `reports`    : PathologyReport keyed by report id
///   - `drafts`     : partial report state keyed by patientId (Map<String, dynamic>)
///
/// Audio files live in the app documents directory under `pathology_recordings/`
/// and only their paths are stored in Hive.
class HiveStorageService {
  static const String patientsBox = 'patients';
  static const String reportsBox = 'reports';
  static const String draftsBox = 'drafts';

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter('pathology_report_db');

    Hive.registerAdapter(PatientAdapter());
    Hive.registerAdapter(VoiceRecordingAdapter());
    Hive.registerAdapter(ReportStatusAdapter());
    Hive.registerAdapter(PathologyReportAdapter());

    await Hive.openBox<Patient>(patientsBox);
    await Hive.openBox<PathologyReport>(reportsBox);
    await Hive.openBox(draftsBox); // dynamic map

    _initialized = true;
  }

  // ─── Patient operations ─────────────────────────────────────────

  static Box<Patient> get _patients => Hive.box<Patient>(patientsBox);
  static Box<PathologyReport> get _reports =>
      Hive.box<PathologyReport>(reportsBox);
  static Box get _drafts => Hive.box(draftsBox);

  static Patient? getPatient(String patientId) {
    if (patientId.isEmpty) return null;
    return _patients.get(patientId);
  }

  static Future<void> savePatient(Patient p) async {
    await _patients.put(p.patientId, p);
  }

  static List<Patient> allPatients() {
    final list = _patients.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  static Future<void> deletePatient(String patientId) async {
    await _patients.delete(patientId);
  }

  // ─── Report operations ─────────────────────────────────────────

  static Future<void> saveReport(PathologyReport report) async {
    await _reports.put(report.id, report);
    // Also keep patient record up to date from the snapshot on the report
    if (report.patientId.isNotEmpty) {
      final existing = getPatient(report.patientId);
      final patient = (existing ??
              Patient(patientId: report.patientId))
          .copyWith(
        name: report.patientName,
        age: report.patientAge,
        gender: report.patientGender,
        orderedBy: report.orderedBy,
        referringDoctor: report.referredBy,
        labNumber: report.labNo,
        visitNumber: report.visitNo,
      );
      await savePatient(patient);
    }
  }

  static PathologyReport? getReport(String id) => _reports.get(id);

  static List<PathologyReport> allReports() {
    final list = _reports.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  static List<PathologyReport> reportsForPatient(String patientId) {
    return _reports.values
        .where((r) => r.patientId == patientId)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<void> deleteReport(String id) async {
    final r = _reports.get(id);
    if (r != null) {
      // best-effort: remove audio files on disk
      for (final rec in r.voiceRecordings) {
        try {
          final f = File(rec.filePath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    await _reports.delete(id);
  }

  static ValueListenable<Box<PathologyReport>> reportsListenable() =>
      _reports.listenable();

  // ─── Draft operations (autosave while dictating) ────────────────

  static Future<void> saveDraft(String patientId, Map<String, dynamic> draft) {
    return _drafts.put(patientId, draft);
  }

  static Map<String, dynamic>? getDraft(String patientId) {
    final raw = _drafts.get(patientId);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  static Future<void> clearDraft(String patientId) => _drafts.delete(patientId);

  // ─── Audio file storage ────────────────────────────────────────

  /// Return (create if missing) the directory where all recordings live.
  static Future<Directory> recordingsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'pathology_recordings'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Generate a new recording file path (not yet created) inside the
  /// recordings directory.
  static Future<String> newRecordingPath({String extension = 'm4a'}) async {
    final dir = await recordingsDir();
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_${_randomShort()}.$extension';
    return p.join(dir.path, name);
  }

  static String _randomShort() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return ts.toRadixString(36).substring(ts.toRadixString(36).length - 6);
  }

  /// Generate the next report number in the H-NNN/YYYY format used in the
  /// lab template.
  static String nextReportNumber() {
    final year = DateTime.now().year;
    final yearReports =
        _reports.values.where((r) => r.createdAt.year == year).length;
    final seq = (yearReports + 1).toString().padLeft(3, '0');
    return 'H-$seq/$year';
  }
}
