import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  static String get _apiKey => dotenv.env['API_KEY'] ?? '';

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  /// Transcribe an audio file using Gemini (inline base64 audio).
  static Future<String> transcribeAudio(
    String filePath, {
    String mimeType = 'audio/mp4',
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception(
          'Gemini API key not found. Check .env and ensure API_KEY is set.');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Audio file not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final base64Audio = base64Encode(bytes);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                      'Transcribe this medical dictation verbatim. Return ONLY the transcribed text, no commentary or formatting.'
                },
                {
                  'inline_data': {
                    'mime_type': mimeType,
                    'data': base64Audio,
                  }
                }
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.0,
            'maxOutputTokens': 2048,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
        return text.trim();
      } else {
        throw Exception(
            'Gemini transcription error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        throw Exception(
            'Network error connecting to Gemini API: $e. Check your internet connection.');
      }
      rethrow;
    }
  }

  /// Generate a structured pathology report from raw voice transcript
  static Future<Map<String, String>> generateReportFromTranscript(
    String rawTranscript, {
    String patientContext = '',
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception(
          'Gemini API key not found. Check .env file and ensure API_KEY is set.');
    }

    final prompt = '''
You are an expert pathologist assistant. A doctor has dictated a pathology report via voice.
Below is the raw transcript of their dictation. Parse it carefully and generate a structured pathology report.

${patientContext.isNotEmpty ? 'Patient Context: $patientContext\n' : ''}
Raw Transcript:
"""
$rawTranscript
"""

Extract and return a JSON object with these exact keys (use empty string "" if info not mentioned):
{
  "patient_name": "",
  "patient_age": "",
  "patient_gender": "",
  "referring_doctor": "",
  "hospital_id": "",
  "specimen_type": "",
  "specimen_site": "",
  "clinical_history": "",
  "gross_description": "",
  "microscopic_description": "",
  "diagnosis": "",
  "grade": "",
  "stage": "",
  "immunohistochemistry": "",
  "special_stains": "",
  "molecular_studies": "",
  "comments": "",
  "summary": "A concise 2-3 sentence clinical summary of the findings suitable for the referring physician"
}

IMPORTANT:
- Use proper medical terminology and formatting
- Fix any speech-to-text errors using medical context
- The summary should be precise, professional, and clinically actionable
- Return ONLY valid JSON, no markdown or extra text
''';

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.2,
            'maxOutputTokens': 2048,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text =
            data['candidates'][0]['content']['parts'][0]['text'] as String;

        // Clean markdown code fences if present
        String cleanJson = text.trim();
        if (cleanJson.startsWith('```')) {
          cleanJson = cleanJson.replaceFirst(RegExp(r'^```json?\s*'), '');
          cleanJson = cleanJson.replaceFirst(RegExp(r'\s*```$'), '');
        }

        final parsed = jsonDecode(cleanJson) as Map<String, dynamic>;
        return parsed.map((key, value) => MapEntry(key, value.toString()));
      } else {
        throw Exception(
            'Gemini API error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        throw Exception(
            'Network error connecting to Gemini API: $e. Check your internet connection.');
      }
      rethrow;
    }
  }

  /// Generate only a summary from transcript (lighter call)
  static Future<String> generateSummary(String transcript) async {
    final prompt = '''
You are an expert pathologist. Summarize the following pathology dictation into a precise,
professional clinical summary (2-4 sentences) suitable for the referring physician.
Fix any speech recognition errors using medical context.

Transcript:
"""
$transcript
"""

Return ONLY the summary text, no JSON or formatting.
''';

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.2,
            'maxOutputTokens': 512,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'] as String;
      } else {
        throw Exception(
            'Gemini API error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        throw Exception(
            'Network error connecting to Gemini API: $e. Check your internet connection.');
      }
      rethrow;
    }
  }

  /// Transcribe text correction — fix STT errors in medical context
  static Future<String> correctTranscription(String rawText) async {
    final prompt = '''
You are a medical transcription specialist. The following text was generated by speech-to-text
from a pathologist's dictation. Fix any recognition errors, correct medical terminology,
add proper punctuation, and format it clearly. Keep the meaning exactly the same.

Raw STT text:
"""
$rawText
"""

Return ONLY the corrected text.
''';

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': 1024,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'] as String;
      } else {
        throw Exception('Gemini API error: ${response.statusCode}');
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        throw Exception(
            'Network error connecting to Gemini API: $e. Check your internet connection.');
      }
      rethrow;
    }
  }
}
