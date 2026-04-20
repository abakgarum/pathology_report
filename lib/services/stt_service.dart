import 'gemini_service.dart';
import 'google_cloud_speech_service.dart';
import 'openai_service.dart';

enum SttProvider { whisper, googleCloud, gemini }

extension SttProviderLabel on SttProvider {
  String get label {
    switch (this) {
      case SttProvider.whisper:
        return 'Whisper (OpenAI)';
      case SttProvider.googleCloud:
        return 'Google Cloud';
      case SttProvider.gemini:
        return 'Gemini';
    }
  }

  String get shortLabel {
    switch (this) {
      case SttProvider.whisper:
        return 'Whisper';
      case SttProvider.googleCloud:
        return 'Google';
      case SttProvider.gemini:
        return 'Gemini';
    }
  }
}

class SttService {
  static Future<String> transcribe(
    String filePath,
    SttProvider provider,
  ) {
    switch (provider) {
      case SttProvider.whisper:
        return OpenAIService.transcribeAudio(filePath);
      case SttProvider.googleCloud:
        return GoogleCloudSpeechService.transcribeAudio(filePath);
      case SttProvider.gemini:
        return GeminiService.transcribeAudio(filePath);
    }
  }
}
