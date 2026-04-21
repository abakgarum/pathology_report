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

    final systemPrompt = '''
You are an expert histopathologist assistant. A pathologist has dictated a
pathology report via voice. Turn the raw transcript into a polished,
professionally worded histopathology report that follows the department
template exactly.

You MUST return a JSON object with these exact keys (use empty string ""
if a field was not mentioned — never invent or hallucinate values):

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

Formatting rules:
- Use proper medical terminology and grammatically complete sentences.
- Fix speech-to-text errors using medical context (e.g. "pyriform sinus").
- "gross_examination" should describe what was received with measurements
  (e.g. "Received multiple gray white to gray brown soft tissue bits
  together measuring 2.0 x 1.0 x 1.0 cm, entirely processed in 1 block.").
- "microscopy_impression" should end with an impression line, e.g.
  "Features are suggestive of moderately differentiated squamous cell
  carcinoma." Combine microscopic description and impression into one field.
- "summary" = 2-3 sentence clinical summary for the referring physician.
- "patient_age" as a number string (e.g. "76"), omit "Y".
- "patient_gender" is "Male" / "Female" / "Other".
- Return ONLY valid JSON. No markdown fences, no commentary.
''';

    final userPrompt = '''
${patientContext.isNotEmpty ? 'Known patient context (use as ground truth):\n$patientContext\n\n' : ''}Raw dictation transcript:
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
