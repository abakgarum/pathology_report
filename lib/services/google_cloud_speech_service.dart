import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GoogleCloudSpeechService {
  static String get _apiKey =>
      dotenv.env['GOOGLE_CLOUD_API_KEY'] ?? dotenv.env['API_KEY'] ?? '';

  static const String _endpoint =
      'https://speech.googleapis.com/v1/speech:recognize';

  /// Transcribe an audio file using Google Cloud Speech-to-Text (REST + API key).
  /// The app records m4a (AAC). Google Cloud Speech v1 does not natively accept
  /// AAC, so we send it as `ENCODING_UNSPECIFIED` and rely on auto-detection —
  /// which works for containers Google can parse (FLAC/LINEAR16/OGG_OPUS/MP3).
  /// If you hit errors, convert your recordings to one of those formats.
  static Future<String> transcribeAudio(
    String filePath, {
    String languageCode = 'en-US',
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception(
          'Google Cloud API key not found. Set GOOGLE_CLOUD_API_KEY (or API_KEY) in .env.');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Audio file not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final base64Audio = base64Encode(bytes);

    try {
      final response = await http.post(
        Uri.parse('$_endpoint?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'config': {
            'encoding': 'ENCODING_UNSPECIFIED',
            'languageCode': languageCode,
            'enableAutomaticPunctuation': true,
            'model': 'latest_long',
          },
          'audio': {'content': base64Audio},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        final transcript = results
            .map((r) {
              final alts = (r as Map<String, dynamic>)['alternatives']
                      as List<dynamic>? ??
                  [];
              if (alts.isEmpty) return '';
              return (alts.first as Map<String, dynamic>)['transcript']
                      ?.toString() ??
                  '';
            })
            .where((s) => s.isNotEmpty)
            .join(' ');
        return transcript.trim();
      } else {
        throw Exception(
            'Google Cloud Speech error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        throw Exception(
            'Network error connecting to Google Cloud Speech API: $e.');
      }
      rethrow;
    }
  }
}
