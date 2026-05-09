import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

// Hive type IDs (kept unique across the app)
const int _kPatientTypeId = 10;
const int _kVoiceRecordingTypeId = 11;
const int _kReportTypeId = 12;
const int _kReportStatusTypeId = 13;
const int _kTemplateTypeId = 15; // bumped: file-only schema

// Parsed template schema (CAP-style synoptic Q&A tree)
const int _kTemplateQuestionTypeIdEnum = 16;
const int _kTemplateAnswerTypeId = 17;
const int _kTemplateQuestionTypeId = 18;
const int _kTemplateSectionTypeId = 19;
const int _kTemplateSchemaTypeId = 20;

// Structured report sub-types (CAP/RCPath-aligned synoptic data)
const int _kIhcEntryTypeId = 21;
const int _kStagingSummaryTypeId = 22;

enum ReportStatus { draft, pending, completed }

extension ReportStatusLabel on ReportStatus {
  String get label {
    switch (this) {
      case ReportStatus.draft:
        return 'Draft';
      case ReportStatus.pending:
        return 'Pending Review';
      case ReportStatus.completed:
        return 'Completed';
    }
  }
}

/// Patient record — keyed by patientId (MRN / hospital ID).
/// Name, age, gender are captured but primary lookup is by patientId.
class Patient {
  final String patientId;
  String name;
  int age;
  String gender;
  String contactNumber;
  String referringDoctor;
  String orderedBy;
  String labNumber;
  String visitNumber;
  final DateTime createdAt;
  DateTime updatedAt;

  Patient({
    required this.patientId,
    this.name = '',
    this.age = 0,
    this.gender = '',
    this.contactNumber = '',
    this.referringDoctor = '',
    this.orderedBy = '',
    this.labNumber = '',
    this.visitNumber = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Patient copyWith({
    String? name,
    int? age,
    String? gender,
    String? contactNumber,
    String? referringDoctor,
    String? orderedBy,
    String? labNumber,
    String? visitNumber,
  }) {
    return Patient(
      patientId: patientId,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      contactNumber: contactNumber ?? this.contactNumber,
      referringDoctor: referringDoctor ?? this.referringDoctor,
      orderedBy: orderedBy ?? this.orderedBy,
      labNumber: labNumber ?? this.labNumber,
      visitNumber: visitNumber ?? this.visitNumber,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Single voice-dictated chunk with path to the stored audio on disk plus
/// the transcript text (populated after Whisper returns).
class VoiceRecording {
  final String id;
  final String filePath;
  String transcription;
  final DateTime recordedAt;
  Duration duration;
  String label;

  VoiceRecording({
    String? id,
    required this.filePath,
    this.transcription = '',
    DateTime? recordedAt,
    this.duration = Duration.zero,
    this.label = '',
  })  : id = id ?? const Uuid().v4(),
        recordedAt = recordedAt ?? DateTime.now();

  VoiceRecording copyWith({
    String? transcription,
    Duration? duration,
    String? label,
  }) {
    return VoiceRecording(
      id: id,
      filePath: filePath,
      transcription: transcription ?? this.transcription,
      recordedAt: recordedAt,
      duration: duration ?? this.duration,
      label: label ?? this.label,
    );
  }
}

/// Pathology report matching the department template:
/// Lab Number, Clinical Information, Specimen, Gross Examination,
/// Microscopy & Impression.
class PathologyReport {
  final String id;
  String reportUuid; // Stable QR-encoded ID, independent of internal `id` key
  String reportNumber; // e.g. "H-748/2026"
  String patientId;

  // Snapshot of patient fields at the time of the report
  String patientName;
  int patientAge;
  String patientGender;
  String mrn;
  String labNo;
  String visitNo;
  String orderedBy;
  String referredBy;

  // Core report sections (match template)
  String clinicalInformation;
  String specimen;
  String grossExamination;
  String microscopyImpression;

  // Diagnosis-first headline. Pathologists read the bottom-line diagnosis
  // BEFORE the supporting evidence — so this 1-3 sentence statement is
  // rendered prominently at the top of the report (after Clinical
  // Information). Examples:
  //   "Residual invasive ductal carcinoma — right breast. Lymph nodes:
  //    2 of 14 show metastatic carcinoma without extracapsular extension.
  //    All surgical resection margins are free of tumour."
  // Optional — empty string means "use microscopyImpression as the
  // headline" for backward compatibility with old reports.
  String diagnosisHeadline;

  // Pathological staging string (pTNM / ypTNM, AJCC edition implied).
  // Examples: "ypT1cN1a", "pT2N0M0", "pT3aN2bM0".
  // Legacy free-text staging — kept for backward compat with reports
  // saved before structured `staging` existed. Renderer prefers
  // `staging` when populated, else falls back to this string.
  String pathologicStaging;

  // Structured CAP-style staging summary. Rendered as the "STAGING
  // SUMMARY" box right under the diagnosis headline.
  StagingSummary staging;

  // Ancillary / IHC table — each marker on its own row in the final
  // report rather than buried in microscopy prose.
  List<IhcEntry> ihcResults;

  // Microscopic description, separated from the synoptic block.
  // `microscopyImpression` becomes the SYNOPTIC SUMMARY (CAP-style
  // "Element: Response" pairs, often filled from synopticAnswers);
  // `microscopicDescription` is the prose paragraph describing the
  // histology. Empty for small biopsies that only need a synoptic.
  String microscopicDescription;

  // Pathologist's COMMENT — interpretation, recommendations, MDT note,
  // pending studies. Kept SEPARATE from the diagnosis itself per
  // Valenstein's "diagnosis is fact, comment is interpretation" rule.
  String comment;

  // Cancer family tag — used to pick the right built-in template /
  // synoptic schema. Empty for free-form reports.
  // Examples: "breast_invasive", "colorectal", "prostate", "lung",
  // "endometrial", "bladder", "melanoma", "lymph_node", "thyroid".
  String cancerType;

  // Draft / raw content
  String rawTranscript;
  List<VoiceRecording> voiceRecordings;
  String summary;

  // Synoptic answers captured during a guided template flow.
  // Map<questionId, answer> where answer is a String, List<String>, num, or bool.
  Map<String, dynamic> synopticAnswers;
  String templateId; // Empty if free-form report; else the TemplateDocument.id used.

  ReportStatus status;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime sampleReceiptDate;
  DateTime reportedDate;
  String pathologistName;
  String pathologistRegistration;
  // Dual-signature fields — populated only when the lab has dual sign-out
  // enabled in Settings. Empty strings mean "single signatory".
  String pathologistName2;
  String pathologistRegistration2;

  PathologyReport({
    String? id,
    String? reportUuid,
    required this.reportNumber,
    required this.patientId,
    this.patientName = '',
    this.patientAge = 0,
    this.patientGender = '',
    this.mrn = '',
    this.labNo = '',
    this.visitNo = '',
    this.orderedBy = '',
    this.referredBy = '',
    this.clinicalInformation = '',
    this.specimen = '',
    this.grossExamination = '',
    this.microscopyImpression = '',
    this.diagnosisHeadline = '',
    this.pathologicStaging = '',
    StagingSummary? staging,
    List<IhcEntry>? ihcResults,
    this.microscopicDescription = '',
    this.comment = '',
    this.cancerType = '',
    this.rawTranscript = '',
    List<VoiceRecording>? voiceRecordings,
    this.summary = '',
    Map<String, dynamic>? synopticAnswers,
    this.templateId = '',
    this.status = ReportStatus.draft,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? sampleReceiptDate,
    DateTime? reportedDate,
    this.pathologistName = 'Dr. Komal D. Chippalkatti',
    this.pathologistRegistration = 'KMC - 79367',
    this.pathologistName2 = '',
    this.pathologistRegistration2 = '',
  })  : id = id ?? const Uuid().v4(),
        // Default the QR UUID to a fresh v4. Caller can override for legacy reads.
        reportUuid = reportUuid ?? const Uuid().v4(),
        staging = staging ?? StagingSummary(),
        ihcResults = ihcResults ?? <IhcEntry>[],
        voiceRecordings = voiceRecordings ?? [],
        synopticAnswers = synopticAnswers ?? <String, dynamic>{},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        sampleReceiptDate = sampleReceiptDate ?? DateTime.now(),
        reportedDate = reportedDate ?? DateTime.now();

  PathologyReport copyWith({
    String? reportUuid,
    String? reportNumber,
    String? patientId,
    String? patientName,
    int? patientAge,
    String? patientGender,
    String? mrn,
    String? labNo,
    String? visitNo,
    String? orderedBy,
    String? referredBy,
    String? clinicalInformation,
    String? specimen,
    String? grossExamination,
    String? microscopyImpression,
    String? diagnosisHeadline,
    String? pathologicStaging,
    StagingSummary? staging,
    List<IhcEntry>? ihcResults,
    String? microscopicDescription,
    String? comment,
    String? cancerType,
    String? rawTranscript,
    List<VoiceRecording>? voiceRecordings,
    String? summary,
    Map<String, dynamic>? synopticAnswers,
    String? templateId,
    ReportStatus? status,
    DateTime? sampleReceiptDate,
    DateTime? reportedDate,
    String? pathologistName,
    String? pathologistRegistration,
    String? pathologistName2,
    String? pathologistRegistration2,
  }) {
    return PathologyReport(
      id: id,
      reportUuid: reportUuid ?? this.reportUuid,
      reportNumber: reportNumber ?? this.reportNumber,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      patientAge: patientAge ?? this.patientAge,
      patientGender: patientGender ?? this.patientGender,
      mrn: mrn ?? this.mrn,
      labNo: labNo ?? this.labNo,
      visitNo: visitNo ?? this.visitNo,
      orderedBy: orderedBy ?? this.orderedBy,
      referredBy: referredBy ?? this.referredBy,
      clinicalInformation: clinicalInformation ?? this.clinicalInformation,
      specimen: specimen ?? this.specimen,
      grossExamination: grossExamination ?? this.grossExamination,
      microscopyImpression: microscopyImpression ?? this.microscopyImpression,
      diagnosisHeadline: diagnosisHeadline ?? this.diagnosisHeadline,
      pathologicStaging: pathologicStaging ?? this.pathologicStaging,
      staging: staging ?? this.staging,
      ihcResults: ihcResults ?? this.ihcResults,
      microscopicDescription:
          microscopicDescription ?? this.microscopicDescription,
      comment: comment ?? this.comment,
      cancerType: cancerType ?? this.cancerType,
      rawTranscript: rawTranscript ?? this.rawTranscript,
      voiceRecordings: voiceRecordings ?? this.voiceRecordings,
      summary: summary ?? this.summary,
      synopticAnswers: synopticAnswers ?? this.synopticAnswers,
      templateId: templateId ?? this.templateId,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      sampleReceiptDate: sampleReceiptDate ?? this.sampleReceiptDate,
      reportedDate: reportedDate ?? this.reportedDate,
      pathologistName: pathologistName ?? this.pathologistName,
      pathologistRegistration:
          pathologistRegistration ?? this.pathologistRegistration,
      pathologistName2: pathologistName2 ?? this.pathologistName2,
      pathologistRegistration2:
          pathologistRegistration2 ?? this.pathologistRegistration2,
    );
  }
}

/// A pathologist-authored report template. The body is a plain-text example
/// of the desired final report (structure, phrasing, section order). The
/// report generator uses it ONLY as a formatting reference — content must
/// still come from the transcript.
class TemplateDocument {
  final String id;
  String name;
  String label; // free-form category e.g. "CAP · Breast", "Lung Biopsy"
  String filePath; // absolute path of the stored file under app docs
  String sourceFileName; // original file name as picked by the user
  int fileSize; // bytes
  final DateTime createdAt;
  DateTime updatedAt;

  TemplateDocument({
    String? id,
    required this.name,
    this.label = '',
    required this.filePath,
    required this.sourceFileName,
    this.fileSize = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  TemplateDocument copyWith({
    String? name,
    String? label,
    String? filePath,
    String? sourceFileName,
    int? fileSize,
  }) {
    return TemplateDocument(
      id: id,
      name: name ?? this.name,
      label: label ?? this.label,
      filePath: filePath ?? this.filePath,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      fileSize: fileSize ?? this.fileSize,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

// ─── Parsed template schema (CAP-style synoptic) ────────────────────────────

enum TemplateQuestionType { singleSelect, multiSelect, text, integer, decimal, date }

extension TemplateQuestionTypeLabel on TemplateQuestionType {
  String get label {
    switch (this) {
      case TemplateQuestionType.singleSelect:
        return 'Single choice';
      case TemplateQuestionType.multiSelect:
        return 'Multiple choice';
      case TemplateQuestionType.text:
        return 'Free text';
      case TemplateQuestionType.integer:
        return 'Integer';
      case TemplateQuestionType.decimal:
        return 'Decimal';
      case TemplateQuestionType.date:
        return 'Date';
    }
  }
}

/// One answer choice. `triggersQuestionIds` are the IDs of questions revealed
/// when this answer is picked (CAP "DisablesChildren" — a misnomer; in SDC it
/// actually *enables* nested questions). `disablesAnswerIds` are answer IDs
/// inside the same question that selecting this one removes (mutual exclusion
/// stronger than radio behavior).
class TemplateAnswer {
  final String id;
  String label;
  List<String> triggersQuestionIds;
  List<String> disablesAnswerIds;

  TemplateAnswer({
    String? id,
    required this.label,
    List<String>? triggersQuestionIds,
    List<String>? disablesAnswerIds,
  })  : id = id ?? const Uuid().v4(),
        triggersQuestionIds = triggersQuestionIds ?? const [],
        disablesAnswerIds = disablesAnswerIds ?? const [];
}

class TemplateQuestion {
  final String id;
  String label;
  TemplateQuestionType type;
  bool required;
  String units; // empty if not numeric
  List<TemplateAnswer> answers; // empty for free-text/numeric
  bool freeTextAllowed; // for selects with an "Other (specify)" affordance
  String parentAnswerId; // empty for top-level questions

  TemplateQuestion({
    String? id,
    required this.label,
    this.type = TemplateQuestionType.singleSelect,
    this.required = true,
    this.units = '',
    List<TemplateAnswer>? answers,
    this.freeTextAllowed = false,
    this.parentAnswerId = '',
  })  : id = id ?? const Uuid().v4(),
        answers = answers ?? [];
}

class TemplateSection {
  String title;

  /// Routing tag for the final-report renderer:
  ///   'synoptic' (default) — renders under SYNOPTIC SUMMARY
  ///   'gross'              — renders under SPECIMEN & GROSS EXAMINATION
  /// User-uploaded templates default to 'synoptic'; built-in templates
  /// mark grossing-station sections explicitly so structured gross
  /// data (orientation, ink, distance to margins, # nodes by station,
  /// Quirke grade, Breslow, Gleason cores, etc.) renders in the right
  /// section instead of being mixed into the synoptic block.
  String kind;

  List<TemplateQuestion> questions;

  TemplateSection({
    required this.title,
    this.kind = 'synoptic',
    List<TemplateQuestion>? questions,
  }) : questions = questions ?? [];
}

/// Parsed structure for one TemplateDocument. Keyed by [templateId] so the
/// schema box can be looked up directly with the template's id.
class TemplateSchema {
  final String templateId;
  String version;
  List<TemplateSection> sections;
  final DateTime parsedAt;

  TemplateSchema({
    required this.templateId,
    this.version = '',
    List<TemplateSection>? sections,
    DateTime? parsedAt,
  })  : sections = sections ?? [],
        parsedAt = parsedAt ?? DateTime.now();

  int get totalQuestions =>
      sections.fold<int>(0, (sum, s) => sum + s.questions.length);

  /// Flat list of all questions across sections (preserving order).
  List<TemplateQuestion> get allQuestions => [
        for (final s in sections) ...s.questions,
      ];

  TemplateQuestion? questionById(String id) {
    for (final s in sections) {
      for (final q in s.questions) {
        if (q.id == id) return q;
      }
    }
    return null;
  }
}

// ─── Structured ancillary / staging data (CAP synoptic) ─────────────────

/// One row of an immunohistochemistry / ancillary studies table.
/// Rendered as a row in the final report's "ANCILLARY STUDIES" block
/// rather than buried inside the microscopy prose.
class IhcEntry {
  String marker;       // e.g. "ER", "HER2", "Ki-67", "MLH1"
  String clone;        // e.g. "SP1", "4B5" — antibody clone (optional)
  String result;       // e.g. "POSITIVE", "NEGATIVE", "1+", "20%"
  String intensity;    // e.g. "Strong", "Moderate", "Weak" (optional)
  String percent;      // e.g. "95%" (optional)
  String note;         // free-text qualifier (optional)

  IhcEntry({
    this.marker = '',
    this.clone = '',
    this.result = '',
    this.intensity = '',
    this.percent = '',
    this.note = '',
  });

  bool get isEmpty =>
      marker.isEmpty && result.isEmpty && intensity.isEmpty && percent.isEmpty;
}

/// Structured pTNM staging summary. Each component is rendered on its
/// own line in the report's "STAGING SUMMARY" box. Empty fields are
/// hidden (so a small biopsy with only a Stage Group can still use this).
class StagingSummary {
  String prefix;       // p / yp / rp / a / c — usually included in pT, but may be split
  String pT;           // e.g. "pT2", "ypT1c"
  String pN;           // e.g. "pN1a (sn)", "pN0 (0/14)"
  String pM;           // e.g. "pM0", "Not applicable", "pM1 (liver)"
  String stageGroup;   // e.g. "IIB", "IIIA"
  String ajccEdition;  // e.g. "AJCC 8th edition"
  String additional;   // free-text extra prognostic remark (optional)

  StagingSummary({
    this.prefix = '',
    this.pT = '',
    this.pN = '',
    this.pM = '',
    this.stageGroup = '',
    this.ajccEdition = '',
    this.additional = '',
  });

  bool get isEmpty =>
      pT.isEmpty &&
      pN.isEmpty &&
      pM.isEmpty &&
      stageGroup.isEmpty &&
      additional.isEmpty;
}

// ─── Hive adapters (hand-written, no code-gen) ─────────────────────────

class PatientAdapter extends TypeAdapter<Patient> {
  @override
  final int typeId = _kPatientTypeId;

  @override
  Patient read(BinaryReader reader) {
    return Patient(
      patientId: reader.readString(),
      name: reader.readString(),
      age: reader.readInt(),
      gender: reader.readString(),
      contactNumber: reader.readString(),
      referringDoctor: reader.readString(),
      orderedBy: reader.readString(),
      labNumber: reader.readString(),
      visitNumber: reader.readString(),
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false),
    );
  }

  @override
  void write(BinaryWriter writer, Patient obj) {
    writer.writeString(obj.patientId);
    writer.writeString(obj.name);
    writer.writeInt(obj.age);
    writer.writeString(obj.gender);
    writer.writeString(obj.contactNumber);
    writer.writeString(obj.referringDoctor);
    writer.writeString(obj.orderedBy);
    writer.writeString(obj.labNumber);
    writer.writeString(obj.visitNumber);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    writer.writeInt(obj.updatedAt.millisecondsSinceEpoch);
  }
}

class VoiceRecordingAdapter extends TypeAdapter<VoiceRecording> {
  @override
  final int typeId = _kVoiceRecordingTypeId;

  @override
  VoiceRecording read(BinaryReader reader) {
    return VoiceRecording(
      id: reader.readString(),
      filePath: reader.readString(),
      transcription: reader.readString(),
      recordedAt:
          DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false),
      duration: Duration(milliseconds: reader.readInt()),
      label: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, VoiceRecording obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.filePath);
    writer.writeString(obj.transcription);
    writer.writeInt(obj.recordedAt.millisecondsSinceEpoch);
    writer.writeInt(obj.duration.inMilliseconds);
    writer.writeString(obj.label);
  }
}

class ReportStatusAdapter extends TypeAdapter<ReportStatus> {
  @override
  final int typeId = _kReportStatusTypeId;

  @override
  ReportStatus read(BinaryReader reader) {
    final idx = reader.readInt();
    return ReportStatus.values[idx.clamp(0, ReportStatus.values.length - 1)];
  }

  @override
  void write(BinaryWriter writer, ReportStatus obj) {
    writer.writeInt(obj.index);
  }
}

class TemplateDocumentAdapter extends TypeAdapter<TemplateDocument> {
  @override
  final int typeId = _kTemplateTypeId;

  @override
  TemplateDocument read(BinaryReader reader) {
    return TemplateDocument(
      id: reader.readString(),
      name: reader.readString(),
      label: reader.readString(),
      filePath: reader.readString(),
      sourceFileName: reader.readString(),
      fileSize: reader.readInt(),
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false),
    );
  }

  @override
  void write(BinaryWriter writer, TemplateDocument obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.writeString(obj.label);
    writer.writeString(obj.filePath);
    writer.writeString(obj.sourceFileName);
    writer.writeInt(obj.fileSize);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    writer.writeInt(obj.updatedAt.millisecondsSinceEpoch);
  }
}

class PathologyReportAdapter extends TypeAdapter<PathologyReport> {
  @override
  final int typeId = _kReportTypeId;

  @override
  PathologyReport read(BinaryReader reader) {
    final id = reader.readString();
    final reportNumber = reader.readString();
    final patientId = reader.readString();
    final patientName = reader.readString();
    final patientAge = reader.readInt();
    final patientGender = reader.readString();
    final mrn = reader.readString();
    final labNo = reader.readString();
    final visitNo = reader.readString();
    final orderedBy = reader.readString();
    final referredBy = reader.readString();
    final clinicalInformation = reader.readString();
    final specimen = reader.readString();
    final grossExamination = reader.readString();
    final microscopyImpression = reader.readString();
    final rawTranscript = reader.readString();
    final voiceRecordings = (reader.readList()).cast<VoiceRecording>();
    final summary = reader.readString();
    final status = ReportStatus.values[
        reader.readInt().clamp(0, ReportStatus.values.length - 1)];
    final createdAt =
        DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false);
    final updatedAt =
        DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false);
    final sampleReceiptDate =
        DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false);
    final reportedDate =
        DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false);
    final pathologistName = reader.readString();
    final pathologistRegistration = reader.readString();

    // Backward-compat: fields appended after v1. If the binary record was
    // written before they existed, BinaryReader.availableBytes is 0 and we
    // fall back to safe defaults (reportUuid copies `id` so old reports get
    // a stable QR-encodable identifier without rewriting storage).
    String reportUuid = id;
    Map<String, dynamic> synopticAnswers = <String, dynamic>{};
    String templateId = '';
    String pathologistName2 = '';
    String pathologistRegistration2 = '';
    String diagnosisHeadline = '';
    String pathologicStaging = '';
    StagingSummary staging = StagingSummary();
    List<IhcEntry> ihcResults = <IhcEntry>[];
    String microscopicDescription = '';
    String comment = '';
    String cancerType = '';
    if (reader.availableBytes > 0) reportUuid = reader.readString();
    if (reader.availableBytes > 0) {
      synopticAnswers = Map<String, dynamic>.from(reader.readMap());
    }
    if (reader.availableBytes > 0) templateId = reader.readString();
    if (reader.availableBytes > 0) pathologistName2 = reader.readString();
    if (reader.availableBytes > 0) pathologistRegistration2 = reader.readString();
    if (reader.availableBytes > 0) diagnosisHeadline = reader.readString();
    if (reader.availableBytes > 0) pathologicStaging = reader.readString();
    if (reader.availableBytes > 0) staging = reader.read() as StagingSummary;
    if (reader.availableBytes > 0) {
      ihcResults = (reader.readList()).cast<IhcEntry>();
    }
    if (reader.availableBytes > 0) microscopicDescription = reader.readString();
    if (reader.availableBytes > 0) comment = reader.readString();
    if (reader.availableBytes > 0) cancerType = reader.readString();

    return PathologyReport(
      id: id,
      reportUuid: reportUuid,
      reportNumber: reportNumber,
      patientId: patientId,
      patientName: patientName,
      patientAge: patientAge,
      patientGender: patientGender,
      mrn: mrn,
      labNo: labNo,
      visitNo: visitNo,
      orderedBy: orderedBy,
      referredBy: referredBy,
      clinicalInformation: clinicalInformation,
      specimen: specimen,
      grossExamination: grossExamination,
      microscopyImpression: microscopyImpression,
      rawTranscript: rawTranscript,
      voiceRecordings: voiceRecordings,
      summary: summary,
      synopticAnswers: synopticAnswers,
      templateId: templateId,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      sampleReceiptDate: sampleReceiptDate,
      reportedDate: reportedDate,
      pathologistName: pathologistName,
      pathologistRegistration: pathologistRegistration,
      pathologistName2: pathologistName2,
      pathologistRegistration2: pathologistRegistration2,
      diagnosisHeadline: diagnosisHeadline,
      pathologicStaging: pathologicStaging,
      staging: staging,
      ihcResults: ihcResults,
      microscopicDescription: microscopicDescription,
      comment: comment,
      cancerType: cancerType,
    );
  }

  @override
  void write(BinaryWriter writer, PathologyReport obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.reportNumber);
    writer.writeString(obj.patientId);
    writer.writeString(obj.patientName);
    writer.writeInt(obj.patientAge);
    writer.writeString(obj.patientGender);
    writer.writeString(obj.mrn);
    writer.writeString(obj.labNo);
    writer.writeString(obj.visitNo);
    writer.writeString(obj.orderedBy);
    writer.writeString(obj.referredBy);
    writer.writeString(obj.clinicalInformation);
    writer.writeString(obj.specimen);
    writer.writeString(obj.grossExamination);
    writer.writeString(obj.microscopyImpression);
    writer.writeString(obj.rawTranscript);
    writer.writeList(obj.voiceRecordings);
    writer.writeString(obj.summary);
    writer.writeInt(obj.status.index);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    writer.writeInt(obj.updatedAt.millisecondsSinceEpoch);
    writer.writeInt(obj.sampleReceiptDate.millisecondsSinceEpoch);
    writer.writeInt(obj.reportedDate.millisecondsSinceEpoch);
    writer.writeString(obj.pathologistName);
    writer.writeString(obj.pathologistRegistration);
    // Appended fields — order matters for backward-compatible reads.
    writer.writeString(obj.reportUuid);
    writer.writeMap(obj.synopticAnswers);
    writer.writeString(obj.templateId);
    writer.writeString(obj.pathologistName2);
    writer.writeString(obj.pathologistRegistration2);
    writer.writeString(obj.diagnosisHeadline);
    writer.writeString(obj.pathologicStaging);
    writer.write(obj.staging);
    writer.writeList(obj.ihcResults);
    writer.writeString(obj.microscopicDescription);
    writer.writeString(obj.comment);
    writer.writeString(obj.cancerType);
  }
}

// ─── Template schema adapters ───────────────────────────────────────

class TemplateQuestionTypeAdapter extends TypeAdapter<TemplateQuestionType> {
  @override
  final int typeId = _kTemplateQuestionTypeIdEnum;

  @override
  TemplateQuestionType read(BinaryReader reader) {
    final idx = reader.readInt();
    return TemplateQuestionType.values[
        idx.clamp(0, TemplateQuestionType.values.length - 1)];
  }

  @override
  void write(BinaryWriter writer, TemplateQuestionType obj) {
    writer.writeInt(obj.index);
  }
}

class TemplateAnswerAdapter extends TypeAdapter<TemplateAnswer> {
  @override
  final int typeId = _kTemplateAnswerTypeId;

  @override
  TemplateAnswer read(BinaryReader reader) {
    return TemplateAnswer(
      id: reader.readString(),
      label: reader.readString(),
      triggersQuestionIds: reader.readStringList(),
      disablesAnswerIds: reader.readStringList(),
    );
  }

  @override
  void write(BinaryWriter writer, TemplateAnswer obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.label);
    writer.writeStringList(obj.triggersQuestionIds);
    writer.writeStringList(obj.disablesAnswerIds);
  }
}

class TemplateQuestionAdapter extends TypeAdapter<TemplateQuestion> {
  @override
  final int typeId = _kTemplateQuestionTypeId;

  @override
  TemplateQuestion read(BinaryReader reader) {
    return TemplateQuestion(
      id: reader.readString(),
      label: reader.readString(),
      type: TemplateQuestionType.values[
          reader.readInt().clamp(0, TemplateQuestionType.values.length - 1)],
      required: reader.readBool(),
      units: reader.readString(),
      answers: (reader.readList()).cast<TemplateAnswer>(),
      freeTextAllowed: reader.readBool(),
      parentAnswerId: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, TemplateQuestion obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.label);
    writer.writeInt(obj.type.index);
    writer.writeBool(obj.required);
    writer.writeString(obj.units);
    writer.writeList(obj.answers);
    writer.writeBool(obj.freeTextAllowed);
    writer.writeString(obj.parentAnswerId);
  }
}

class TemplateSectionAdapter extends TypeAdapter<TemplateSection> {
  @override
  final int typeId = _kTemplateSectionTypeId;

  @override
  TemplateSection read(BinaryReader reader) {
    final title = reader.readString();
    final questions = (reader.readList()).cast<TemplateQuestion>();
    // Backward-compat: `kind` was added after v1. Old schemas don't
    // have it, so we default to 'synoptic'.
    String kind = 'synoptic';
    if (reader.availableBytes > 0) kind = reader.readString();
    return TemplateSection(title: title, kind: kind, questions: questions);
  }

  @override
  void write(BinaryWriter writer, TemplateSection obj) {
    writer.writeString(obj.title);
    writer.writeList(obj.questions);
    writer.writeString(obj.kind);
  }
}

class TemplateSchemaAdapter extends TypeAdapter<TemplateSchema> {
  @override
  final int typeId = _kTemplateSchemaTypeId;

  @override
  TemplateSchema read(BinaryReader reader) {
    return TemplateSchema(
      templateId: reader.readString(),
      version: reader.readString(),
      sections: (reader.readList()).cast<TemplateSection>(),
      parsedAt:
          DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false),
    );
  }

  @override
  void write(BinaryWriter writer, TemplateSchema obj) {
    writer.writeString(obj.templateId);
    writer.writeString(obj.version);
    writer.writeList(obj.sections);
    writer.writeInt(obj.parsedAt.millisecondsSinceEpoch);
  }
}

// ─── Structured ancillary / staging adapters ────────────────────────────

class IhcEntryAdapter extends TypeAdapter<IhcEntry> {
  @override
  final int typeId = _kIhcEntryTypeId;

  @override
  IhcEntry read(BinaryReader reader) {
    return IhcEntry(
      marker: reader.readString(),
      clone: reader.readString(),
      result: reader.readString(),
      intensity: reader.readString(),
      percent: reader.readString(),
      note: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, IhcEntry obj) {
    writer.writeString(obj.marker);
    writer.writeString(obj.clone);
    writer.writeString(obj.result);
    writer.writeString(obj.intensity);
    writer.writeString(obj.percent);
    writer.writeString(obj.note);
  }
}

class StagingSummaryAdapter extends TypeAdapter<StagingSummary> {
  @override
  final int typeId = _kStagingSummaryTypeId;

  @override
  StagingSummary read(BinaryReader reader) {
    return StagingSummary(
      prefix: reader.readString(),
      pT: reader.readString(),
      pN: reader.readString(),
      pM: reader.readString(),
      stageGroup: reader.readString(),
      ajccEdition: reader.readString(),
      additional: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, StagingSummary obj) {
    writer.writeString(obj.prefix);
    writer.writeString(obj.pT);
    writer.writeString(obj.pN);
    writer.writeString(obj.pM);
    writer.writeString(obj.stageGroup);
    writer.writeString(obj.ajccEdition);
    writer.writeString(obj.additional);
  }
}
