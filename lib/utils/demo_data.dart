import '../models/report_models.dart';

class DemoData {
  static List<PathologyReport> getSampleReports() {
    return [
      PathologyReport(
        reportNumber: 'PATH-2026-0041',
        patient: Patient(
          name: 'Rajesh Kumar',
          age: 54,
          gender: 'Male',
          contactNumber: '+91 98765 43210',
          referringDoctor: 'Dr. Meena Sharma',
          hospitalId: 'MH-20261204',
        ),
        specimen: Specimen(
          type: SpecimenType.biopsy,
          site: 'Right lung, upper lobe',
          collectionDate: '2026-04-01',
          receivedDate: '2026-04-02',
          clinicalHistory: 'Persistent cough for 3 months, weight loss. CT shows 3.2cm spiculated mass in right upper lobe.',
          grossDescription: 'Core biopsy fragments, tan-white, firm, aggregate 1.5 x 0.3 cm.',
        ),
        findings: PathologyFinding(
          microscopicDescription: 'Sections show fragments of lung parenchyma infiltrated by a moderately differentiated adenocarcinoma with acinar and papillary growth patterns. Tumor cells show enlarged, hyperchromatic nuclei with prominent nucleoli.',
          diagnosis: 'Adenocarcinoma, moderately differentiated',
          grade: 'Grade 2 (Moderately differentiated)',
          stage: 'pT2a (pending staging workup)',
          immunohistochemistry: 'TTF-1: Positive, Napsin-A: Positive, CK7: Positive, CK20: Negative, p40: Negative',
          comments: 'Recommend molecular testing for EGFR, ALK, ROS1, and PD-L1.',
        ),
        status: ReportStatus.completed,
        pathologistName: 'Dr. Anand Patel',
        summary: 'Moderately differentiated adenocarcinoma of the right upper lobe. IHC profile consistent with primary lung adenocarcinoma. Molecular testing recommended for targeted therapy.',
        createdAt: DateTime(2026, 4, 2),
      ),
      PathologyReport(
        reportNumber: 'PATH-2026-0042',
        patient: Patient(
          name: 'Priya Nair',
          age: 38,
          gender: 'Female',
          contactNumber: '+91 87654 32109',
          referringDoctor: 'Dr. Suresh Menon',
          hospitalId: 'MH-20261205',
        ),
        specimen: Specimen(
          type: SpecimenType.fnac,
          site: 'Left breast, upper outer quadrant',
          collectionDate: '2026-04-03',
          receivedDate: '2026-04-03',
          clinicalHistory: 'Palpable lump left breast for 2 weeks. No family history of breast cancer.',
          grossDescription: 'FNAC aspirate — moderately cellular smears.',
        ),
        findings: PathologyFinding(
          microscopicDescription: 'Smears show clusters of ductal epithelial cells in a background of bare bipolar nuclei and proteinaceous material. No atypia or mitotic figures identified.',
          diagnosis: 'Fibroadenoma (Benign — Category II)',
          comments: 'Findings consistent with fibroadenoma. Correlate with imaging. Follow-up recommended.',
        ),
        status: ReportStatus.completed,
        pathologistName: 'Dr. Anand Patel',
        summary: 'Benign breast lesion consistent with fibroadenoma. No evidence of malignancy. Recommend imaging correlation and follow-up.',
        createdAt: DateTime(2026, 4, 3),
      ),
      PathologyReport(
        reportNumber: 'PATH-2026-0043',
        patient: Patient(
          name: 'Mohammed Farooq',
          age: 62,
          gender: 'Male',
          contactNumber: '+91 76543 21098',
          referringDoctor: 'Dr. Kavitha Rao',
          hospitalId: 'MH-20261206',
        ),
        specimen: Specimen(
          type: SpecimenType.biopsy,
          site: 'Sigmoid colon',
          collectionDate: '2026-04-04',
          receivedDate: '2026-04-04',
          clinicalHistory: 'Altered bowel habits, rectal bleeding x 2 months. Colonoscopy reveals polypoidal mass at 25cm.',
          grossDescription: 'Multiple biopsy fragments, tan-pink, soft, aggregate 0.8 x 0.5 cm.',
        ),
        findings: PathologyFinding(
          microscopicDescription: 'Pending microscopic examination.',
          diagnosis: 'Pending',
        ),
        status: ReportStatus.pending,
        pathologistName: 'Dr. Anand Patel',
        summary: '',
        createdAt: DateTime(2026, 4, 4),
      ),
      PathologyReport(
        reportNumber: 'PATH-2026-0044',
        patient: Patient(
          name: 'Lakshmi Devi',
          age: 45,
          gender: 'Female',
          contactNumber: '+91 65432 10987',
          referringDoctor: 'Dr. Arun Gupta',
          hospitalId: 'MH-20261207',
        ),
        specimen: Specimen(
          type: SpecimenType.resection,
          site: 'Thyroid — total thyroidectomy',
          collectionDate: '2026-04-05',
          receivedDate: '2026-04-05',
          clinicalHistory: 'Multinodular goiter with suspicious nodule right lobe. FNAC: Bethesda IV.',
        ),
        findings: PathologyFinding(),
        status: ReportStatus.draft,
        pathologistName: 'Dr. Anand Patel',
        summary: '',
        createdAt: DateTime(2026, 4, 5),
      ),
    ];
  }
}
