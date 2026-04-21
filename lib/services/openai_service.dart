import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// OpenAI helpers for:
///   1. Whisper transcription (audio -> text)
///   2. Chat completions that turn a raw dictation into a structured
///      histopathology report matching the lab template.
class OpenAIService {
  static String get _apiKey => dotenv.env['OPENAI_API_KEY'] ?? '';

  static const String _transcriptionsUrl =
      'https://api.openai.com/v1/audio/transcriptions';
  static const String _chatUrl = 'https://api.openai.com/v1/chat/completions';

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
    if (prompt != null && prompt.isNotEmpty) {
      request.fields['prompt'] = prompt;
    }

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
