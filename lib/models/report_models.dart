import 'package:uuid/uuid.dart';

enum ReportStatus { draft, pending, completed }

enum SpecimenType {
  biopsy,
  resection,
  cytology,
  bloodSmear,
  bonemarrow,
  fnac,
  fluidAnalysis,
  other,
}

extension SpecimenTypeLabel on SpecimenType {
  String get label {
    switch (this) {
      case SpecimenType.biopsy:
        return 'Biopsy';
      case SpecimenType.resection:
        return 'Resection';
      case SpecimenType.cytology:
        return 'Cytology';
      case SpecimenType.bloodSmear:
        return 'Blood Smear';
      case SpecimenType.bonemarrow:
        return 'Bone Marrow';
      case SpecimenType.fnac:
        return 'FNAC';
      case SpecimenType.fluidAnalysis:
        return 'Fluid Analysis';
      case SpecimenType.other:
        return 'Other';
    }
  }
}

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

class Patient {
  final String id;
  final String name;
  final int age;
  final String gender;
  final String contactNumber;
  final String referringDoctor;
  final String hospitalId;

  Patient({
    String? id,
    required this.name,
    required this.age,
    required this.gender,
    this.contactNumber = '',
    this.referringDoctor = '',
    this.hospitalId = '',
  }) : id = id ?? const Uuid().v4();
}

class Specimen {
  final String id;
  final SpecimenType type;
  final String site;
  final String collectionDate;
  final String receivedDate;
  final String clinicalHistory;
  final String grossDescription;

  Specimen({
    String? id,
    required this.type,
    required this.site,
    required this.collectionDate,
    required this.receivedDate,
    this.clinicalHistory = '',
    this.grossDescription = '',
  }) : id = id ?? const Uuid().v4();
}

class PathologyFinding {
  final String microscopicDescription;
  final String diagnosis;
  final String grade;
  final String stage;
  final String immunohistochemistry;
  final String specialStains;
  final String molecularStudies;
  final String comments;

  PathologyFinding({
    this.microscopicDescription = '',
    this.diagnosis = '',
    this.grade = '',
    this.stage = '',
    this.immunohistochemistry = '',
    this.specialStains = '',
    this.molecularStudies = '',
    this.comments = '',
  });
}

/// Represents a single voice recording session with its transcription
class VoiceRecording {
  final String id;
  final String filePath;
  final String transcription;
  final DateTime recordedAt;
  final Duration duration;
  final String label; // e.g. "Gross Description", "Microscopic", "Clinical History"

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
  }) {
    return VoiceRecording(
      id: id,
      filePath: filePath,
      transcription: transcription ?? this.transcription,
      recordedAt: recordedAt,
      duration: duration ?? this.duration,
      label: label,
    );
  }
}

class PathologyReport {
  final String id;
  final String reportNumber;
  final Patient patient;
  final Specimen specimen;
  final PathologyFinding findings;
  final ReportStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String pathologistName;
  final String summary;
  final List<VoiceRecording> voiceRecordings;
  final String rawTranscript; // full combined transcript from all recordings

  PathologyReport({
    String? id,
    required this.reportNumber,
    required this.patient,
    required this.specimen,
    required this.findings,
    this.status = ReportStatus.draft,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.pathologistName = '',
    this.summary = '',
    this.voiceRecordings = const [],
    this.rawTranscript = '',
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  PathologyReport copyWith({
    Patient? patient,
    Specimen? specimen,
    PathologyFinding? findings,
    ReportStatus? status,
    String? summary,
    List<VoiceRecording>? voiceRecordings,
    String? rawTranscript,
  }) {
    return PathologyReport(
      id: id,
      reportNumber: reportNumber,
      patient: patient ?? this.patient,
      specimen: specimen ?? this.specimen,
      findings: findings ?? this.findings,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      pathologistName: pathologistName,
      summary: summary ?? this.summary,
      voiceRecordings: voiceRecordings ?? this.voiceRecordings,
      rawTranscript: rawTranscript ?? this.rawTranscript,
    );
  }
}
