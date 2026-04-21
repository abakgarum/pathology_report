import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

// Hive type IDs (kept unique across the app)
const int _kPatientTypeId = 10;
const int _kVoiceRecordingTypeId = 11;
const int _kReportTypeId = 12;
const int _kReportStatusTypeId = 13;

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

  // Draft / raw content
  String rawTranscript;
  List<VoiceRecording> voiceRecordings;
  String summary;

  ReportStatus status;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime sampleReceiptDate;
  DateTime reportedDate;
  String pathologistName;
  String pathologistRegistration;

  PathologyReport({
    String? id,
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
    this.rawTranscript = '',
    List<VoiceRecording>? voiceRecordings,
    this.summary = '',
    this.status = ReportStatus.draft,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? sampleReceiptDate,
    DateTime? reportedDate,
    this.pathologistName = 'Dr. Komal D. Chippalkatti',
    this.pathologistRegistration = 'KMC - 79367',
  })  : id = id ?? const Uuid().v4(),
        voiceRecordings = voiceRecordings ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        sampleReceiptDate = sampleReceiptDate ?? DateTime.now(),
        reportedDate = reportedDate ?? DateTime.now();

  PathologyReport copyWith({
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
    String? rawTranscript,
    List<VoiceRecording>? voiceRecordings,
    String? summary,
    ReportStatus? status,
    DateTime? sampleReceiptDate,
    DateTime? reportedDate,
    String? pathologistName,
    String? pathologistRegistration,
  }) {
    return PathologyReport(
      id: id,
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
      rawTranscript: rawTranscript ?? this.rawTranscript,
      voiceRecordings: voiceRecordings ?? this.voiceRecordings,
      summary: summary ?? this.summary,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      sampleReceiptDate: sampleReceiptDate ?? this.sampleReceiptDate,
      reportedDate: reportedDate ?? this.reportedDate,
      pathologistName: pathologistName ?? this.pathologistName,
      pathologistRegistration:
          pathologistRegistration ?? this.pathologistRegistration,
    );
  }
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

class PathologyReportAdapter extends TypeAdapter<PathologyReport> {
  @override
  final int typeId = _kReportTypeId;

  @override
  PathologyReport read(BinaryReader reader) {
    return PathologyReport(
      id: reader.readString(),
      reportNumber: reader.readString(),
      patientId: reader.readString(),
      patientName: reader.readString(),
      patientAge: reader.readInt(),
      patientGender: reader.readString(),
      mrn: reader.readString(),
      labNo: reader.readString(),
      visitNo: reader.readString(),
      orderedBy: reader.readString(),
      referredBy: reader.readString(),
      clinicalInformation: reader.readString(),
      specimen: reader.readString(),
      grossExamination: reader.readString(),
      microscopyImpression: reader.readString(),
      rawTranscript: reader.readString(),
      voiceRecordings: (reader.readList()).cast<VoiceRecording>(),
      summary: reader.readString(),
      status: ReportStatus.values[
          reader.readInt().clamp(0, ReportStatus.values.length - 1)],
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false),
      sampleReceiptDate:
          DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false),
      reportedDate:
          DateTime.fromMillisecondsSinceEpoch(reader.readInt(), isUtc: false),
      pathologistName: reader.readString(),
      pathologistRegistration: reader.readString(),
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
  }
}
