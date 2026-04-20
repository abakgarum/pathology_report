import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class OpenAIService {
  static String get _apiKey => dotenv.env['OPENAI_API_KEY'] ?? '';

  static const String _transcriptionsUrl =
      'https://api.openai.com/v1/audio/transcriptions';

  /// Transcribe an audio file using OpenAI Whisper.
  /// [filePath] must point to an audio file on disk (m4a, mp3, wav, webm, etc.).
  /// Returns the raw transcript text.
  static Future<String> transcribeAudio(
    String filePath, {
    String model = 'whisper-1',
    String? language,
    String? prompt,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception(
          'OpenAI API key not found. Check .env and ensure OPENAI_API_KEY is set.');
    }

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
      } else {
        throw Exception(
            'Whisper API error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        throw Exception(
            'Network error connecting to OpenAI API: $e. Check your internet connection.');
      }
      rethrow;
    }
  }
}
