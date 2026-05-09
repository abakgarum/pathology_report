import '../models/report_models.dart';
import 'hive_storage_service.dart';

/// CAP/ICCR-aligned synoptic templates that ship with the app, so a
/// pathologist can produce a fully-structured cancer report without
/// uploading anything. Each entry is a `(TemplateDocument, TemplateSchema)`
/// pair: the document is the user-facing template (rendered in the
/// Templates list), the schema is the parsed Q&A tree the guided
/// wizard walks. Both go into the same Hive boxes as user-uploaded
/// templates, so the rest of the app treats them uniformly.
///
/// Sources: CAP Cancer Protocols (cap.org/protocols-and-guidelines)
/// and the ICCR datasets (iccr-cancer.org). Question wording and answer
/// choices are paraphrased; see the source protocols for full guidance.

class _BuiltInTemplate {
  final String stableId; // deterministic so re-installing doesn't dupe
  final String name;
  final String label;
  final List<TemplateSection> sections;
  const _BuiltInTemplate({
    required this.stableId,
    required this.name,
    required this.label,
    required this.sections,
  });
}

/// Convenience for declaring an answer in the template list below
/// without the noise of named arguments.
TemplateAnswer _a(String label) => TemplateAnswer(label: label);

/// Convenience for a single-select question with `n` answer labels.
TemplateQuestion _qSingle(String label, List<String> answers,
    {bool freeText = false}) {
  return TemplateQuestion(
    label: label,
    type: TemplateQuestionType.singleSelect,
    answers: answers.map(_a).toList(),
    freeTextAllowed: freeText,
  );
}

TemplateQuestion _qText(String label) => TemplateQuestion(
      label: label,
      type: TemplateQuestionType.text,
    );

TemplateQuestion _qNum(String label, {String units = ''}) => TemplateQuestion(
      label: label,
      type: TemplateQuestionType.decimal,
      units: units,
    );

TemplateQuestion _qInt(String label, {String units = ''}) => TemplateQuestion(
      label: label,
      type: TemplateQuestionType.integer,
      units: units,
    );

// ─── Breast — invasive carcinoma (CAP-aligned) ──────────────────────────

final _breastInvasive = _BuiltInTemplate(
  stableId: 'builtin-breast-invasive',
  name: 'Breast — invasive carcinoma',
  label: 'Built-in · CAP-style',
  sections: [
    // ── GROSSING STATION ───────────────────────────────────────────
    TemplateSection(title: 'Specimen & gross', kind: 'gross', questions: [
      _qSingle('Procedure', [
        'Lumpectomy / wide local excision',
        'Mastectomy — simple',
        'Mastectomy — modified radical',
        'Mastectomy — skin-sparing',
        'Mastectomy — nipple-sparing',
        'Excisional biopsy',
        'Other',
      ], freeText: true),
      _qSingle('Laterality', ['Right', 'Left']),
      _qText('Surgeon orientation (e.g. short=sup, long=lat)'),
      _qSingle('Ink convention', [
        'Six-color (sup/inf/med/lat/ant/post)',
        'Single deep + perimeter',
        'Other',
      ], freeText: true),
      _qText('Specimen dimensions (SI × ML × AP, mm)'),
      _qNum('Specimen weight', units: 'g'),
      _qText('Tumor location (clock / quadrant)'),
      _qText('Tumor dimensions (mm)'),
      _qSingle('Specimen radiograph performed', ['No', 'Yes']),
      _qSingle('Photograph taken', ['No', 'Yes']),
      _qText('Cassette key (e.g. A1–A12)'),
    ]),
    TemplateSection(
        title: 'Distance to margins (gross, mm)',
        kind: 'gross',
        questions: [
          _qNum('Superior margin', units: 'mm'),
          _qNum('Inferior margin', units: 'mm'),
          _qNum('Medial margin', units: 'mm'),
          _qNum('Lateral margin', units: 'mm'),
          _qNum('Anterior (skin) margin', units: 'mm'),
          _qNum('Posterior (deep) margin', units: 'mm'),
        ]),
    // ── SYNOPTIC ───────────────────────────────────────────────────
    TemplateSection(title: 'Tumor', questions: [
      _qSingle('Histologic type', [
        'Invasive ductal carcinoma, NST',
        'Invasive lobular carcinoma',
        'Invasive carcinoma with mixed features',
        'Tubular carcinoma',
        'Mucinous carcinoma',
        'Cribriform carcinoma',
        'Micropapillary carcinoma',
        'Metaplastic carcinoma',
        'Other',
      ], freeText: true),
      _qSingle('Histologic grade (Nottingham)', [
        'Grade 1 (well differentiated)',
        'Grade 2 (moderately differentiated)',
        'Grade 3 (poorly differentiated)',
      ]),
      _qText('Nottingham score (T+N+M, e.g. 3+2+1=6/9)'),
      _qNum('Largest invasive focus', units: 'mm'),
      _qSingle('Tumor focality', [
        'Single focus',
        'Multifocal (specify count)',
      ], freeText: true),
      _qSingle('DCIS', [
        'Not identified',
        'Present',
      ]),
      _qNum('Extent of DCIS (if present)', units: 'mm'),
      _qSingle('DCIS nuclear grade', ['Low', 'Intermediate', 'High']),
      _qSingle('DCIS necrosis', ['Absent', 'Present']),
    ]),
    TemplateSection(title: 'Margins', questions: [
      _qSingle('Margin status — invasive carcinoma', [
        'Negative',
        'Positive (ink on tumor)',
      ]),
      _qSingle('Closest margin', [
        'Superior',
        'Inferior',
        'Medial',
        'Lateral',
        'Anterior (skin)',
        'Posterior (deep)',
      ]),
      _qNum('Distance to closest margin', units: 'mm'),
      _qSingle('Margin status — DCIS', [
        'Not applicable',
        'Negative',
        'Positive',
      ]),
    ]),
    TemplateSection(title: 'Other findings', questions: [
      _qSingle('Lymphovascular invasion', ['Not identified', 'Present']),
      _qSingle('Microcalcifications', [
        'Not identified',
        'Present in invasive carcinoma',
        'Present in DCIS',
        'Present in benign tissue',
      ]),
      _qSingle('Treatment effect (post-neoadjuvant)', [
        'Not applicable',
        'No definite response',
        'Probable / definite response (partial)',
        'Complete response (no residual invasive)',
      ]),
    ]),
    TemplateSection(title: 'Lymph nodes', questions: [
      _qInt('Number of sentinel nodes examined'),
      _qInt('Number of sentinel nodes positive'),
      _qInt('Number of axillary nodes examined'),
      _qInt('Number of axillary nodes positive'),
      _qSingle('Largest metastatic deposit', [
        'Not applicable',
        'Isolated tumor cells (≤0.2 mm)',
        'Micrometastasis (>0.2–2 mm)',
        'Macrometastasis (>2 mm)',
      ]),
      _qSingle('Extranodal extension', ['Not identified', 'Present']),
    ]),
  ],
);

// ─── Colorectal carcinoma resection (CAP-aligned) ──────────────────────

final _colorectal = _BuiltInTemplate(
  stableId: 'builtin-colorectal',
  name: 'Colorectal carcinoma — resection',
  label: 'Built-in · CAP-style',
  sections: [
    // ── GROSSING STATION ───────────────────────────────────────────
    TemplateSection(title: 'Specimen & gross', kind: 'gross', questions: [
      _qSingle('Procedure', [
        'Right hemicolectomy',
        'Transverse colectomy',
        'Left hemicolectomy',
        'Sigmoidectomy',
        'Low anterior resection',
        'Abdominoperineal resection',
        'Total colectomy',
        'Polypectomy / EMR / ESD',
        'Other',
      ], freeText: true),
      _qNum('Specimen length', units: 'cm'),
      _qSingle('Tumor site', [
        'Cecum',
        'Ascending colon',
        'Hepatic flexure',
        'Transverse colon',
        'Splenic flexure',
        'Descending colon',
        'Sigmoid colon',
        'Rectosigmoid',
        'Rectum',
      ]),
      _qSingle('Configuration', [
        'Polypoid / exophytic',
        'Ulcerated',
        'Annular / constrictive',
        'Flat / infiltrative',
      ]),
      _qNum('Tumor size (gross greatest dimension)', units: 'mm'),
      _qNum('% circumference involved', units: '%'),
      _qNum('Distance from anal verge (rectum)', units: 'cm'),
      _qSingle('Mesorectal completeness — Quirke (rectum)', [
        'Not applicable',
        'Complete',
        'Nearly complete',
        'Incomplete',
      ]),
      _qSingle('Peritoneal reflection identified', ['No', 'Yes']),
      _qSingle('Gross perforation', ['No', 'Yes']),
      _qSingle('Photograph taken', ['No', 'Yes']),
    ]),
    TemplateSection(
        title: 'Gross margins & nodes',
        kind: 'gross',
        questions: [
          _qNum('Distance to proximal margin', units: 'cm'),
          _qNum('Distance to distal margin', units: 'cm'),
          _qNum('Distance to circumferential / radial margin', units: 'mm'),
          _qInt('Lymph nodes harvested grossly (count)'),
          _qNum('Largest node grossly', units: 'mm'),
          _qInt('Tumor deposits grossly (count)'),
        ]),
    // ── SYNOPTIC ───────────────────────────────────────────────────
    TemplateSection(title: 'Tumor', questions: [
      _qSingle('Histologic type', [
        'Adenocarcinoma, NOS',
        'Mucinous adenocarcinoma',
        'Signet-ring cell carcinoma',
        'Medullary carcinoma',
        'Adenosquamous carcinoma',
        'Other',
      ], freeText: true),
      _qSingle('Histologic grade', [
        'Low grade (well / moderately differentiated)',
        'High grade (poorly differentiated / undifferentiated)',
      ]),
      _qSingle('Tumor extent (depth of invasion)', [
        'pTis — intraepithelial / lamina propria',
        'pT1 — invades submucosa',
        'pT2 — invades muscularis propria',
        'pT3 — invades through muscularis into pericolorectal tissue',
        'pT4a — penetrates visceral peritoneum',
        'pT4b — directly invades adjacent organ',
      ]),
    ]),
    TemplateSection(title: 'Margins', questions: [
      _qSingle('Proximal margin', ['Negative', 'Positive']),
      _qSingle('Distal margin', ['Negative', 'Positive']),
      _qSingle('Circumferential (radial) margin', [
        'Not applicable',
        'Negative (>1 mm)',
        'Positive (≤1 mm — tumor at or within 1 mm)',
      ]),
      _qNum('Distance to closest margin', units: 'mm'),
      _qSingle('Mesorectal completeness (rectum, Quirke)', [
        'Not applicable',
        'Complete',
        'Nearly complete',
        'Incomplete',
      ]),
    ]),
    TemplateSection(title: 'Other findings', questions: [
      _qSingle('Lymphovascular invasion', ['Not identified', 'Present']),
      _qSingle('Perineural invasion', ['Not identified', 'Present']),
      _qSingle('Tumor budding (ITBCC)', [
        'Bd1 — Low (0–4 buds)',
        'Bd2 — Intermediate (5–9 buds)',
        'Bd3 — High (≥10 buds)',
      ]),
      _qInt('Tumor deposits (count)'),
      _qSingle('Treatment effect (post-neoadjuvant, modified Ryan)', [
        'Not applicable',
        'Score 0 — Complete response (no viable tumor)',
        'Score 1 — Near-complete (single cells / small foci)',
        'Score 2 — Partial response (residual cancer with evident regression)',
        'Score 3 — Poor / no response',
      ]),
    ]),
    TemplateSection(title: 'Lymph nodes', questions: [
      _qInt('Total nodes examined'),
      _qInt('Nodes positive'),
    ]),
    TemplateSection(title: 'Ancillary / molecular', questions: [
      _qSingle('Mismatch repair (MMR) IHC', [
        'Not performed',
        'Intact (proficient)',
        'Loss of MLH1 / PMS2',
        'Loss of MSH2 / MSH6',
        'Other pattern',
      ], freeText: true),
      _qText('KRAS / NRAS / BRAF result (if performed)'),
    ]),
  ],
);

// ─── Prostate — radical prostatectomy ──────────────────────────────────

final _prostate = _BuiltInTemplate(
  stableId: 'builtin-prostate',
  name: 'Prostate — radical prostatectomy',
  label: 'Built-in · CAP-style',
  sections: [
    TemplateSection(title: 'Specimen & gross', kind: 'gross', questions: [
      _qSingle('Procedure', [
        'Radical retropubic prostatectomy',
        'Robotic-assisted laparoscopic prostatectomy',
        'Perineal prostatectomy',
        'Other',
      ], freeText: true),
      _qSingle('Nerve-sparing', ['Not applicable', 'Bilateral', 'Right', 'Left', 'None']),
      _qNum('Prostate weight (excluding seminal vesicles)', units: 'g'),
      _qText('Prostate dimensions (apex-base × W × AP, mm)'),
      _qNum('Right seminal vesicle length', units: 'mm'),
      _qNum('Left seminal vesicle length', units: 'mm'),
      _qSingle('Ink convention', [
        'Right blue / Left red / Posterior black',
        'Single-color with notch',
        'Other',
      ], freeText: true),
      _qSingle('Apex handling', [
        'Coned and serial-sectioned perpendicular to urethra',
        'Submitted en face',
        'Other',
      ], freeText: true),
      _qSingle('Embedding', [
        'Whole-mount sections',
        'Standard partial sections',
      ]),
      _qSingle('Pelvic lymph nodes received', [
        'No',
        'Right obturator only',
        'Left obturator only',
        'Bilateral obturator',
        'Bilateral obturator + external iliac',
      ]),
    ]),
    TemplateSection(title: 'Tumor & grade', questions: [
      _qSingle('Histologic type', [
        'Acinar adenocarcinoma',
        'Ductal adenocarcinoma',
        'Mucinous (colloid) carcinoma',
        'Other',
      ], freeText: true),
      _qSingle('Grade Group (ISUP)', [
        'Grade Group 1 (Gleason ≤6)',
        'Grade Group 2 (3+4=7)',
        'Grade Group 3 (4+3=7)',
        'Grade Group 4 (Gleason 8)',
        'Grade Group 5 (Gleason 9–10)',
      ]),
      _qText('Gleason score (e.g. 3+4=7)'),
      _qNum('% pattern 4', units: '%'),
      _qNum('% pattern 5', units: '%'),
      _qSingle('Cribriform pattern 4', ['Not identified', 'Present']),
      _qSingle('Intraductal carcinoma (IDC-P)', ['Not identified', 'Present']),
      _qNum('Dominant tumor nodule size', units: 'mm'),
      _qSingle('Tumor location (dominant nodule)', [
        'Right apex', 'Right mid', 'Right base',
        'Left apex', 'Left mid', 'Left base',
        'Anterior', 'Bilateral / multifocal',
      ]),
    ]),
    TemplateSection(title: 'Extension & margins', questions: [
      _qSingle('Extraprostatic extension', [
        'Not identified',
        'Focal',
        'Non-focal (established)',
      ]),
      _qSingle('Seminal vesicle invasion', ['Not identified', 'Present']),
      _qSingle('Bladder neck invasion', ['Not identified', 'Present']),
      _qSingle('Margin status', ['Negative', 'Positive']),
      _qNum('Length of positive margin', units: 'mm'),
      _qText('Positive margin location(s)'),
      _qSingle('Gleason pattern at margin', [
        'Not applicable',
        'Pattern 3',
        'Pattern 4',
        'Pattern 5',
      ]),
      _qSingle('Perineural invasion', ['Not identified', 'Present']),
      _qSingle('Lymphovascular invasion', ['Not identified', 'Present']),
    ]),
    TemplateSection(title: 'Lymph nodes', questions: [
      _qInt('Total nodes examined'),
      _qInt('Nodes positive'),
      _qNum('Largest metastatic deposit', units: 'mm'),
      _qSingle('Extranodal extension', ['Not applicable', 'Not identified', 'Present']),
    ]),
  ],
);

// ─── Lung — resection ──────────────────────────────────────────────────

final _lung = _BuiltInTemplate(
  stableId: 'builtin-lung',
  name: 'Lung — resection',
  label: 'Built-in · CAP-style',
  sections: [
    TemplateSection(title: 'Specimen & gross', kind: 'gross', questions: [
      _qSingle('Procedure', [
        'Wedge resection',
        'Segmentectomy',
        'Lobectomy',
        'Bilobectomy',
        'Pneumonectomy',
        'Other',
      ], freeText: true),
      _qSingle('Lobe', [
        'Right upper',
        'Right middle',
        'Right lower',
        'Left upper',
        'Lingula',
        'Left lower',
      ]),
      _qNum('Specimen weight', units: 'g'),
      _qText('Specimen dimensions (mm)'),
      _qSingle('Pleural surface (gross)', [
        'Smooth, no puckering',
        'Puckering / retraction overlying tumor',
        'Adhesions',
      ]),
      _qNum('Tumor distance to pleura (gross)', units: 'mm'),
      _qNum('Tumor distance to bronchial margin', units: 'mm'),
      _qNum('Tumor distance to staple / parenchymal margin', units: 'mm'),
      _qInt('Satellite nodules (count)'),
      _qSingle('Photograph taken', ['No', 'Yes']),
    ]),
    TemplateSection(title: 'Tumor', questions: [
      _qSingle('Histologic type', [
        'Adenocarcinoma',
        'Squamous cell carcinoma',
        'Large cell carcinoma',
        'Small cell carcinoma',
        'Carcinoid (typical / atypical)',
        'Adenosquamous carcinoma',
        'Sarcomatoid carcinoma',
        'Other',
      ], freeText: true),
      _qNum('Tumor size (greatest dimension)', units: 'mm'),
      _qText('Adenocarcinoma — predominant pattern + % each (lepidic / acinar / papillary / micropapillary / solid)'),
      _qSingle('Spread through air spaces (STAS)', ['Not identified', 'Present']),
      _qSingle('Visceral pleural invasion', [
        'PL0 — none',
        'PL1 — invades elastic layer',
        'PL2 — invades visceral pleural surface',
        'PL3 — invades parietal pleura / chest wall',
      ]),
      _qSingle('Lymphovascular invasion', ['Not identified', 'Present']),
    ]),
    TemplateSection(title: 'Margins & nodes', questions: [
      _qSingle('Bronchial margin', ['Negative', 'Positive']),
      _qSingle('Vascular margin', ['Negative', 'Positive']),
      _qSingle('Parenchymal / staple margin', ['Negative', 'Positive']),
      _qText('Nodes by station (e.g. 4R 0/3, 7 0/2, 10R 1/2, 11R 0/4)'),
      _qInt('Total nodes examined'),
      _qInt('Nodes positive'),
    ]),
    TemplateSection(title: 'Ancillary / molecular', questions: [
      _qText('EGFR result'),
      _qText('ALK result'),
      _qText('ROS1 result'),
      _qText('BRAF / KRAS / MET / RET / NTRK (if performed)'),
      _qText('PD-L1 TPS (%)'),
    ]),
  ],
);

// ─── Endometrial carcinoma ─────────────────────────────────────────────

final _endometrial = _BuiltInTemplate(
  stableId: 'builtin-endometrial',
  name: 'Endometrial carcinoma — hysterectomy',
  label: 'Built-in · CAP-style',
  sections: [
    TemplateSection(title: 'Specimen & gross', kind: 'gross', questions: [
      _qSingle('Procedure', [
        'TAH-BSO',
        'Radical hysterectomy + BSO',
        'Supracervical hysterectomy',
        'Other',
      ], freeText: true),
      _qNum('Uterine weight', units: 'g'),
      _qText('Uterus dimensions (fundus-to-cervix × cornu-to-cornu × AP, mm)'),
      _qNum('Cervix length', units: 'mm'),
      _qNum('Endometrial cavity thickness', units: 'mm'),
      _qSingle('Tumor location', [
        'Anterior', 'Posterior', 'Fundus',
        'Lower uterine segment', 'Diffuse',
      ]),
      _qText('Tumor dimensions (mm)'),
      _qSingle('Adnexa received', ['Both', 'Right only', 'Left only', 'None']),
      _qSingle('Omentum received', ['No', 'Yes']),
      _qSingle('Peritoneal washings received', ['No', 'Yes']),
      _qSingle('SEE-FIM protocol applied to tubes', ['Not applicable', 'Yes']),
    ]),
    TemplateSection(title: 'Tumor', questions: [
      _qSingle('Histologic type', [
        'Endometrioid carcinoma',
        'Serous carcinoma',
        'Clear cell carcinoma',
        'Mixed carcinoma',
        'Carcinosarcoma (MMMT)',
        'Undifferentiated / dedifferentiated',
        'Other',
      ], freeText: true),
      _qSingle('FIGO grade (endometrioid only)', [
        'Not applicable',
        'Grade 1',
        'Grade 2',
        'Grade 3',
      ]),
      _qNum('Depth of myometrial invasion', units: 'mm'),
      _qNum('Total myometrial thickness', units: 'mm'),
      _qNum('% myometrium invaded', units: '%'),
      _qSingle('Lymphovascular space invasion (LVSI)', [
        'Not identified',
        'Focal',
        'Substantial (≥5 vessels)',
      ]),
      _qSingle('Cervical stromal involvement', ['Not identified', 'Present']),
      _qSingle('Serosal / parametrial involvement', ['Not identified', 'Present']),
      _qSingle('Adnexal involvement', ['Not identified', 'Present']),
      _qSingle('Peritoneal washings', [
        'Not performed',
        'Negative',
        'Positive / suspicious',
      ]),
    ]),
    TemplateSection(title: 'Molecular classification', questions: [
      _qSingle('POLE exonuclease mutation', [
        'Not performed', 'Wild-type', 'Pathogenic mutation',
      ]),
      _qSingle('Mismatch repair (MMR) IHC', [
        'Not performed', 'Intact', 'MLH1/PMS2 loss', 'MSH2/MSH6 loss', 'Isolated PMS2 / MSH6 loss',
      ]),
      _qSingle('p53 IHC', [
        'Not performed', 'Wild-type', 'Aberrant (mutant pattern)',
      ]),
      _qSingle('Final molecular class (TCGA)', [
        'Not assigned',
        'POLE-mutated',
        'MMR-deficient',
        'p53-abnormal',
        'No specific molecular profile (NSMP)',
      ]),
    ]),
    TemplateSection(title: 'Lymph nodes', questions: [
      _qInt('Total pelvic nodes examined'),
      _qInt('Pelvic nodes positive'),
      _qInt('Para-aortic nodes examined'),
      _qInt('Para-aortic nodes positive'),
      _qSingle('Sentinel node status', [
        'Not applicable',
        'Negative',
        'Isolated tumor cells (≤0.2 mm)',
        'Micrometastasis (>0.2–2 mm)',
        'Macrometastasis (>2 mm)',
      ]),
    ]),
  ],
);

// ─── Bladder / urothelial carcinoma ────────────────────────────────────

final _bladder = _BuiltInTemplate(
  stableId: 'builtin-bladder',
  name: 'Bladder — urothelial carcinoma',
  label: 'Built-in · CAP-style',
  sections: [
    TemplateSection(title: 'Specimen & gross', kind: 'gross', questions: [
      _qSingle('Procedure', [
        'TURBT (chips)',
        'Partial cystectomy',
        'Radical cystectomy',
        'Cystoprostatectomy',
        'Anterior exenteration',
        'Other',
      ], freeText: true),
      _qSingle('Sex / pelvic structures', [
        'Male — bladder + prostate ± SVs',
        'Male — bladder only',
        'Female — bladder ± uterus / adnexa / vaginal cuff',
        'Not applicable (TURBT)',
      ]),
      _qText('Specimen dimensions (mm) — n/a for TURBT'),
      _qInt('TURBT — # fragments'),
      _qNum('TURBT — aggregate dimension', units: 'mm'),
      _qSingle('TURBT — muscularis propria identified grossly', [
        'Not applicable', 'Suspected absent', 'Likely present',
      ]),
      _qSingle('Ink convention (cystectomy)', [
        'Right perivesical blue / Left black',
        'Other',
      ], freeText: true),
      _qNum('Right ureter length', units: 'mm'),
      _qNum('Left ureter length', units: 'mm'),
      _qSingle('Tumor location', [
        'Trigone', 'Dome', 'Anterior wall', 'Posterior wall',
        'Right lateral wall', 'Left lateral wall', 'Bladder neck',
        'Multifocal',
      ]),
      _qText('Tumor dimensions (mm)'),
      _qSingle('Configuration', [
        'Papillary', 'Sessile / nodular', 'Ulcerated', 'Flat',
      ]),
    ]),
    TemplateSection(title: 'Tumor', questions: [
      _qSingle('Histologic type', [
        'Urothelial (transitional cell) carcinoma',
        'Urothelial carcinoma with divergent differentiation',
        'Squamous cell carcinoma',
        'Adenocarcinoma',
        'Small cell / neuroendocrine carcinoma',
        'Other',
      ], freeText: true),
      _qText('Variant histology + % (micropapillary / plasmacytoid / sarcomatoid / nested / other)'),
      _qSingle('Grade (WHO 2022)', [
        'Low grade (papillary)',
        'High grade',
      ]),
      _qSingle('Depth of invasion', [
        'pTa — non-invasive papillary',
        'pTis — carcinoma in situ',
        'pT1 — invades subepithelial connective tissue',
        'pT2a — invades superficial muscularis propria',
        'pT2b — invades deep muscularis propria',
        'pT3a — invades perivesical fat (microscopic)',
        'pT3b — invades perivesical fat (macroscopic)',
        'pT4a — invades adjacent organ',
        'pT4b — invades pelvic / abdominal wall',
      ]),
      _qSingle('Carcinoma in situ (CIS)', ['Not identified', 'Present']),
      _qSingle('Lymphovascular invasion', ['Not identified', 'Present']),
    ]),
    TemplateSection(title: 'Margins & nodes', questions: [
      _qSingle('Right ureteric margin', ['Not applicable', 'Negative', 'Positive']),
      _qSingle('Left ureteric margin', ['Not applicable', 'Negative', 'Positive']),
      _qSingle('Urethral margin', ['Not applicable', 'Negative', 'Positive']),
      _qSingle('Soft-tissue / circumferential margin', ['Negative', 'Positive']),
      _qSingle('Prostatic urethral involvement (male)', [
        'Not applicable', 'Not identified', 'Stromal invasion',
      ]),
      _qInt('Total nodes examined'),
      _qInt('Nodes positive'),
    ]),
  ],
);

// ─── Cutaneous melanoma — WLE ──────────────────────────────────────────

final _melanoma = _BuiltInTemplate(
  stableId: 'builtin-melanoma',
  name: 'Cutaneous melanoma — WLE',
  label: 'Built-in · CAP-style',
  sections: [
    TemplateSection(title: 'Specimen & gross', kind: 'gross', questions: [
      _qSingle('Procedure', [
        'Shave biopsy',
        'Punch biopsy',
        'Elliptical excision',
        'Wide local excision (WLE)',
        'Mohs', 'Other',
      ], freeText: true),
      _qText('Anatomic site (be specific)'),
      _qText('Orientation (clock-position suture, e.g. suture at 12)'),
      _qText('Specimen dimensions (L × W × D, mm)'),
      _qText('Lesion dimensions (mm)'),
      _qSingle('Lesion ulceration (gross)', ['Not identified', 'Present']),
      _qSingle('Pigmentation', ['None', 'Variegated', 'Black', 'Brown', 'Blue', 'Amelanotic']),
      _qSingle('Satellites grossly', ['Not identified', 'Present']),
      _qSingle('Sectioning', [
        'Bread-loaf perpendicular to long axis',
        'Tip sections submitted en face (12 & 6)',
        'Other',
      ], freeText: true),
      _qSingle('Photograph taken', ['No', 'Yes']),
    ]),
    TemplateSection(
        title: 'Distance to margins (gross, mm)',
        kind: 'gross',
        questions: [
          _qNum('Closest peripheral margin', units: 'mm'),
          _qNum('Deep margin', units: 'mm'),
          _qText('Per-quadrant margins (if oriented)'),
        ]),
    TemplateSection(title: 'Tumor', questions: [
      _qSingle('Histologic subtype', [
        'Superficial spreading',
        'Nodular',
        'Lentigo maligna melanoma',
        'Acral lentiginous',
        'Desmoplastic',
        'Spitzoid',
        'Other',
      ], freeText: true),
      _qNum('Breslow thickness', units: 'mm'),
      _qSingle('Ulceration (microscopic)', ['Not identified', 'Present']),
      _qNum('Dermal mitotic rate', units: '/mm²'),
      _qSingle('Clark level', ['I', 'II', 'III', 'IV', 'V']),
      _qSingle('Microsatellites', ['Not identified', 'Present']),
      _qNum('Regression', units: '%'),
      _qSingle('Lymphovascular invasion', ['Not identified', 'Present']),
      _qSingle('Perineural invasion', ['Not identified', 'Present']),
      _qSingle('Neurotropism', ['Not identified', 'Present']),
    ]),
    TemplateSection(title: 'Margins (microscopic)', questions: [
      _qSingle('Peripheral margin (invasive)', ['Negative', 'Positive']),
      _qNum('Distance to peripheral margin (closest)', units: 'mm'),
      _qSingle('Deep margin', ['Negative', 'Positive']),
      _qNum('Distance to deep margin', units: 'mm'),
      _qSingle('In-situ component at margin', ['Not identified', 'Present']),
    ]),
  ],
);

// ─── Lymph node / lymphoma ─────────────────────────────────────────────

final _lymphNode = _BuiltInTemplate(
  stableId: 'builtin-lymph-node',
  name: 'Lymph node — biopsy / excision',
  label: 'Built-in · WHO-aligned',
  sections: [
    TemplateSection(title: 'Specimen & gross', kind: 'gross', questions: [
      _qText('Site / level (e.g. left cervical level II)'),
      _qInt('Number of nodes received'),
      _qText('Largest node dimensions (mm)'),
      _qText('Aggregate dimension (mm) — if matted'),
      _qSingle('Capsule / cut surface', [
        'Intact, soft pink-tan',
        'Matted',
        'Fleshy / fish-flesh',
        'Necrotic',
        'Caseating',
      ]),
      _qSingle('Received fresh', ['No', 'Yes']),
      _qInt('Touch-imprint slides prepared'),
      _qSingle('Flow cytometry sent (RPMI)', ['No', 'Yes']),
      _qSingle('Snap freeze for molecular', ['No', 'Yes']),
      _qSingle('Cytogenetics sent (sterile saline / RPMI)', ['No', 'Yes']),
      _qSingle('Microbiology cultures sent', ['No', 'Yes']),
      _qSingle('EM sample (glutaraldehyde)', ['No', 'Yes']),
    ]),
    TemplateSection(title: 'Diagnosis', questions: [
      _qText('WHO 5th-edition diagnosis line'),
      _qSingle('Architecture', [
        'Preserved nodal architecture',
        'Effaced — diffuse',
        'Effaced — nodular / follicular',
        'Effaced — interfollicular',
        'Partial effacement',
      ]),
      _qText('Grade / variant (if applicable)'),
      _qNum('Ki-67 proliferation index', units: '%'),
    ]),
    TemplateSection(title: 'Ancillary / molecular', questions: [
      _qText('Flow cytometry reference / report ID'),
      _qText('FISH (e.g. BCL2, BCL6, MYC, t(11;14), t(14;18))'),
      _qText('Molecular (clonality, NGS, etc.)'),
      _qSingle('EBER ISH (EBV)', ['Not performed', 'Negative', 'Positive']),
    ]),
  ],
);

// ─── Public API ────────────────────────────────────────────────────────

const _builtInIds = <String>{
  'builtin-breast-invasive',
  'builtin-colorectal',
  'builtin-prostate',
  'builtin-lung',
  'builtin-endometrial',
  'builtin-bladder',
  'builtin-melanoma',
  'builtin-lymph-node',
};

/// All built-in templates available for installation.
List<_BuiltInTemplate> get _allBuiltIns => [
      _breastInvasive,
      _colorectal,
      _prostate,
      _lung,
      _endometrial,
      _bladder,
      _melanoma,
      _lymphNode,
    ];

/// True when this template was installed by [installBuiltInTemplates]
/// (i.e. its id is in our well-known set).
bool isBuiltInTemplate(TemplateDocument t) => _builtInIds.contains(t.id);

/// Idempotently install every built-in template into the local Hive
/// boxes. Existing built-ins are overwritten so future template tweaks
/// propagate on next install. User-uploaded templates are untouched.
/// Returns the count newly installed (vs already present).
Future<int> installBuiltInTemplates() async {
  int installed = 0;
  for (final b in _allBuiltIns) {
    final alreadyHad = HiveStorageService.allTemplates()
        .any((t) => t.id == b.stableId);
    final doc = TemplateDocument(
      id: b.stableId,
      name: b.name,
      label: b.label,
      filePath: '', // built-in: no on-disk file
      sourceFileName: '',
      fileSize: 0,
    );
    final schema = TemplateSchema(
      templateId: b.stableId,
      version: 'built-in',
      sections: b.sections,
    );
    await HiveStorageService.saveTemplate(doc);
    await HiveStorageService.saveTemplateSchema(schema);
    if (!alreadyHad) installed++;
  }
  return installed;
}
