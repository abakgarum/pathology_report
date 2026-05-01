import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// OpenAI helpers for:
///   1. Whisper transcription (audio -> text)
///   2. Chat completions that turn a raw dictation into a structured
///      histopathology report matching the lab template.
///   3. Parsing an uploaded CAP-style template into a structured Q&A schema.
///   4. Composing a synoptic report from captured answers + free-form
///      dictation per the CAP synoptic format ("element: response", one per
///      line, in a single contiguous block).
class OpenAIService {
  static String get _apiKey => dotenv.env['OPENAI_API_KEY'] ?? '';

  static const String _transcriptionsUrl =
      'https://api.openai.com/v1/audio/transcriptions';
  static const String _chatUrl = 'https://api.openai.com/v1/chat/completions';

  /// Glossary biased into Whisper's `prompt` to lift accuracy for clinical
  /// terms. Whisper's prompt is capped at 224 tokens — keep this terse.
  /// Reference: cookbook.openai.com/examples/whisper_prompting_guide
  static const String medicalGlossary =
      'Histopathology dictation. Common terms: '
      'adenocarcinoma, squamous cell carcinoma, lobular, ductal, cribriform, '
      'micropapillary, tubular, mucinous, metaplastic, sarcomatoid, anaplastic, '
      'lymphovascular invasion, perineural invasion, extranodal extension, '
      'immunohistochemistry, IHC, AE1/AE3, CK7, CK20, CK5/6, TTF-1, p63, p40, '
      'Ki-67, ER, PR, HER2, Gleason 3+4=7, Gleason 4+3=7, Nottingham grade, '
      'mitotic count, nuclear pleomorphism, glandular differentiation, '
      'pTNM staging, pT1, pT2, pT3, pT4, pN0, pN1, pN2, pM0, pM1, '
      'margins uninvolved, margin involved, distance to closest margin, '
      'high grade dysplasia, low grade dysplasia, atypical hyperplasia, '
      'DCIS, LCIS, in situ, invasive, well differentiated, '
      'moderately differentiated, poorly differentiated.';

  // ─── 1. Whisper transcription ─────────────────────────────────

  static Future<String> transcribeAudio(
    String filePath, {
    String model = 'whisper-1',
    String? language,
    String? prompt,
  }) async {
    _requireKey();

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Audio file not found: $filePath');
    }

    final request = http.MultipartRequest('POST', Uri.parse(_transcriptionsUrl))
      ..headers['Authorization'] = 'Bearer $_apiKey'
      ..fields['model'] = model
      ..fields['response_format'] = 'json';

    if (language != null && language.isNotEmpty) {
      request.fields['language'] = language;
    }
    // Always seed Whisper with the medical glossary; callers can extend it
    // with question-specific context (e.g. the current template question).
    final effectivePrompt = (prompt == null || prompt.trim().isEmpty)
        ? medicalGlossary
        : '$medicalGlossary $prompt';
    request.fields['prompt'] = effectivePrompt;

    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    try {
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['text'] as String?)?.trim() ?? '';
      }
      throw Exception(
          'Whisper API error ${response.statusCode}: ${response.body}');
    } catch (e) {
      if (_isNetworkError(e)) {
        throw Exception('Network error connecting to OpenAI: $e');
      }
      rethrow;
    }
  }

  // ─── 2. Structured pathology report generation ────────────────

  /// Generates the lab-template report sections from a raw dictation.
  /// Returns a map with these exact keys (empty string if not dictated):
  ///   patient_name, patient_age, patient_gender, patient_id, lab_no,
  ///   visit_no, ordered_by, referred_by, clinical_information, specimen,
  ///   gross_examination, microscopy_impression, summary
  static Future<Map<String, String>> generateReportFromTranscript(
    String rawTranscript, {
    String patientContext = '',
    String model = 'gpt-4o-mini',
  }) async {
    _requireKey();

    const systemPrompt = '''
You are a histopathology report formatter. A pathologist dictated a report
by voice. Your ONLY job is to place what was said into the correct fields
of the department template and fix speech-to-text artifacts. You are not a
co-author.

ABSOLUTE RULES — do not violate:
1. Do NOT add any clinical content, observations, measurements, impressions,
   or phrasing that is not present in the transcript. No "filler" sentences.
2. Do NOT invent patient demographics, lab numbers, dates, doctor names, or
   specimen details. If the transcript does not state it, leave the field
   as an empty string "".
3. Do NOT expand abbreviations into full diagnoses, and do NOT add "features
   are suggestive of…" style impression lines unless the pathologist
   actually dictated them.
4. You MAY: correct obvious speech-to-text errors using medical context
   (e.g. "pyriform sinus"), fix punctuation/capitalization, split run-on
   sentences, and route the dictated content into the correct section.
5. If a dictated sentence does not clearly belong to any section, place it
   verbatim in the most plausible section rather than dropping it.

Return a JSON object with these exact keys:

{
  "patient_name": "",
  "patient_age": "",
  "patient_gender": "",
  "patient_id": "",
  "lab_no": "",
  "visit_no": "",
  "ordered_by": "",
  "referred_by": "",
  "clinical_information": "",
  "specimen": "",
  "gross_examination": "",
  "microscopy_impression": "",
  "summary": ""
}

Field rules:
- "patient_age" as a plain number string (e.g. "76"); omit "Y".
- "patient_gender" must be "Male", "Female", "Other", or "".
- "microscopy_impression" combines microscopic description and impression
  into one field — but only using text the pathologist actually dictated.
- "summary" is a verbatim condensation of the dictated summary. If none
  was dictated, return "".
- Return ONLY valid JSON. No markdown fences, no commentary.
''';

    final userPrompt = '''
${patientContext.isNotEmpty ? 'Known patient context (use as ground truth, do not invent beyond this):\n$patientContext\n\n' : ''}Raw dictation transcript (this is the ONLY source of clinical content):
"""
$rawTranscript
"""
''';

    try {
      final response = await http.post(
        Uri.parse(_chatUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'temperature': 0.2,
          'response_format': {'type': 'json_object'},
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content =
            data['choices'][0]['message']['content'] as String? ?? '{}';
        final cleaned = _stripCodeFences(content);
        final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
        return parsed.map((k, v) => MapEntry(k, (v ?? '').toString()));
      }
      throw Exception(
          'OpenAI report error ${response.statusCode}: ${response.body}');
    } catch (e) {
      if (_isNetworkError(e)) {
        throw Exception('Network error connecting to OpenAI: $e');
      }
      rethrow;
    }
  }

  /// Optional: clean up a raw transcript (punctuation, medical terms).
  static Future<String> correctTranscription(String rawText,
      {String model = 'gpt-4o-mini'}) async {
    _requireKey();
    final response = await http.post(
      Uri.parse(_chatUrl),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'temperature': 0.1,
        'messages': [
          {
            'role': 'system',
            'content':
                'You are a medical transcription editor. Fix STT errors, add punctuation, correct medical terminology. Keep meaning identical. Return ONLY the corrected text.'
          },
          {'role': 'user', 'content': rawText},
        ],
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['choices'][0]['message']['content'] as String).trim();
    }
    throw Exception('OpenAI correction error ${response.statusCode}');
  }

  // ─── 3. Template parser (CAP-style synoptic Q&A extraction) ───

  /// Parse the plain text content of a CAP-style synoptic protocol into a
  /// structured Q&A tree. Returns the JSON string the caller decodes into a
  /// `TemplateSchema`.
  ///
  /// The prompt teaches the model the conventions used in CAP Word/PDF
  /// protocols:
  ///   - Lines starting with `___` (underscores) are *answer choices*.
  ///   - Lines starting with `+` are *optional* questions/answers.
  ///   - Indentation depth encodes branching (DisablesChildren in SDC).
  ///   - "Note —" lines are narrative guidance; ignore.
  ///   - Lines ending with `:` and followed by indented `___` lines are
  ///     *questions*.
  ///
  /// Uses a higher reasoning model by default. Caller can override.
  static Future<String> parseTemplate(
    String extractedText, {
    String model = 'gpt-4o',
  }) async {
    _requireKey();
    if (extractedText.trim().isEmpty) {
      throw Exception('Extracted template text was empty.');
    }

    const systemPrompt = '''
You convert CAP-style synoptic pathology protocol documents into a strict
JSON schema. The input is the plain-text contents of a Word document (CAP
Cancer Protocol, hospital reporting template, or similar). Output ONLY a
JSON object — no markdown, no commentary.

Conventions you MUST recognise:
- Section headers: ALL-CAPS lines or short title lines that group questions.
- A *question*: a line ending with ":" or that introduces an enumerated set
  of answers. Often preceded by a number/letter like "1." or "a)".
- An *answer choice*: a line starting with "___" (underscores), "☐", "[ ]",
  "o ", "•", or similar bullet markers. May begin with "+ ___" — the "+"
  marks the entire choice as optional. Strip the marker; keep the label text.
- *Optional* element: leading "+" before a question or answer means it is
  optional (not required for synoptic compliance). Set "required": false.
- *Branching* (CAP DisablesChildren): an answer is a *parent* of any
  question whose indentation depth is GREATER than the answer's, until
  indentation returns to the answer's level or shallower. Capture this by
  setting `triggers_question_ids` on the parent answer to the IDs of its
  child questions.
- *Free-text affordances*: an answer like "Other (specify): ___" or
  "Not specified ___" means the question allows free text alongside the
  selection. Set `free_text_allowed`: true on the question.
- *Numeric fields*: questions with units (mm, cm, %, ml, °) or "(specify
  measurement)" become `"type": "decimal"` (or "integer" if no decimal
  point is meaningful) and capture the unit string in `units`.
- *Dates*: "Date of …" with blank or "(specify date)" becomes `"type": "date"`.
- *Multi-select*: questions with "select all that apply", "check all", or
  multiple checkboxes with no exclusion become `"type": "multi_select"`.
- "Note —" / "Comment —" / "Reference —" paragraphs are NARRATIVE; skip.

Output schema (use exactly these keys):
{
  "version": "v4.7.0.0 or similar if found, else empty string",
  "sections": [
    {
      "title": "Section title",
      "questions": [
        {
          "id": "q-001",
          "label": "Question text without trailing colon",
          "type": "single_select" | "multi_select" | "text" | "integer" | "decimal" | "date",
          "required": true,
          "units": "mm",
          "free_text_allowed": false,
          "parent_answer_id": "",
          "answers": [
            {
              "id": "a-001",
              "label": "Answer choice text",
              "triggers_question_ids": ["q-014", "q-015"],
              "disables_answer_ids": []
            }
          ]
        }
      ]
    }
  ]
}

Rules:
- Generate stable, sequential, unique ids of the form "q-001", "q-002", …
  for questions and "a-001", "a-002", … for answers.
- Order questions in document order.
- For type != "single_select" and != "multi_select", "answers" MUST be [].
- Strip leading bullet markers ("___", "+", "☐", "[ ]", numbering) from
  every label.
- If you cannot determine a value, use the field's empty default
  (`""`, `[]`, `false`).
- Return ONLY the JSON object. No explanations.
''';

    // Truncate generously — gpt-4o handles long context. CAP protocols are
    // usually <60k chars after .docx text extraction.
    final clipped = extractedText.length > 80000
        ? extractedText.substring(0, 80000)
        : extractedText;

    try {
      final response = await http
          .post(
        Uri.parse(_chatUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'temperature': 0.0,
          'response_format': {'type': 'json_object'},
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': clipped},
          ],
        }),
      )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content =
            data['choices'][0]['message']['content'] as String? ?? '{}';
        return _stripCodeFences(content);
      }
      throw Exception(
          'Template parse error ${response.statusCode}: ${response.body}');
    } catch (e) {
      if (_isNetworkError(e)) {
        throw Exception('Network error connecting to OpenAI: $e');
      }
      rethrow;
    }
  }

  // ─── 4. Synoptic report composer ──────────────────────────────

  /// Compose the synoptic block (one `Element: response` per line) from
  /// captured answers plus any free-form dictation. Returns a Map with:
  ///   - `synoptic`: the contiguous synoptic report text (compliance block)
  ///   - `clinical_information`, `specimen`, `gross_examination`,
  ///     `microscopy_impression`, `summary`: routed free-form content
  ///     extracted from the dictation that did NOT fit a discrete answer.
  static Future<Map<String, String>> composeSynopticReport({
    required Map<String, dynamic> answers,
    required Map<String, String> questionLabels,
    String freeFormDictation = '',
    String templateName = '',
    String model = 'gpt-4o-mini',
  }) async {
    _requireKey();

    final labeled = <String, dynamic>{};
    for (final entry in answers.entries) {
      final label = questionLabels[entry.key] ?? entry.key;
      labeled[label] = entry.value;
    }

    const systemPrompt = '''
You are a histopathology synoptic report composer. You receive:
  1. A map of {questionLabel: answer} captured during a guided template
     workflow (CAP-style synoptic protocol).
  2. Optional free-form dictation the pathologist added alongside the
     guided answers.

Produce a JSON object with these exact keys:

{
  "synoptic": "",
  "clinical_information": "",
  "specimen": "",
  "gross_examination": "",
  "microscopy_impression": "",
  "summary": ""
}

Rules:
- "synoptic" is the contiguous synoptic block required by CoC/CAP. Format:
    Element: response
  one element-response pair per line, in the order received. Do NOT
  reorder, paraphrase, or omit any answer. Skip pairs where the answer is
  empty/null. Numeric values include their units exactly as captured.
- The other four section keys ("clinical_information", "specimen",
  "gross_examination", "microscopy_impression") receive routed FREE-FORM
  dictation only — never the synoptic answers (which already live in
  "synoptic"). If no free-form text was dictated for a section, leave it "".
- "summary" is one short sentence (≤25 words) summarising the diagnosis
  derived from the captured answers. If insufficient information to
  summarise, return "".
- Do NOT invent clinical content. Do NOT add clauses like "features are
  suggestive of…" unless the pathologist actually said them.
- Return ONLY the JSON object. No markdown fences, no commentary.
''';

    final userPayload = jsonEncode({
      'template_name': templateName,
      'answers': labeled,
      'free_form_dictation': freeFormDictation,
    });

    try {
      final response = await http.post(
        Uri.parse(_chatUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'temperature': 0.1,
          'response_format': {'type': 'json_object'},
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPayload},
          ],
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content =
            data['choices'][0]['message']['content'] as String? ?? '{}';
        final cleaned = _stripCodeFences(content);
        final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
        return parsed.map((k, v) => MapEntry(k, (v ?? '').toString()));
      }
      throw Exception(
          'Synoptic compose error ${response.statusCode}: ${response.body}');
    } catch (e) {
      if (_isNetworkError(e)) {
        throw Exception('Network error connecting to OpenAI: $e');
      }
      rethrow;
    }
  }

  // ─── helpers ──────────────────────────────────────────────────

  static void _requireKey() {
    if (_apiKey.isEmpty) {
      throw Exception(
          'OpenAI API key not found. Check .env and ensure OPENAI_API_KEY is set.');
    }
  }

  static bool _isNetworkError(Object e) {
    final s = e.toString();
    return s.contains('SocketException') || s.contains('Connection');
  }

  static String _stripCodeFences(String s) {
    var t = s.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      t = t.replaceFirst(RegExp(r'\s*```$'), '');
    }
    return t;
  }
}
