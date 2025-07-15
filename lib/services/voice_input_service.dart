// lib/services/voice_input_service.dart
import 'package:dio/dio.dart';

class VoiceInputService {
  static final Dio _dio = Dio();

  /// Transcribes audio using Bhashini API and returns translated English text.
  /// [filePath] - Path to the local audio file.
  static Future<String> transcribeAndTranslate(String filePath) async {
    try {
      final String bhashiniApiUrl = 'https://meity-api.bhashini.gov.in/asr-translation'; // Replace with actual if needed

      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(filePath, filename: 'audio.wav'),
        'source_language': 'auto',
        'target_language': 'en',
      });

      final response = await _dio.post(
        bhashiniApiUrl,
        data: formData,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer YOUR_API_KEY', // Replace with actual token if needed
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        return data['translated_text'] ?? data['transcription'] ?? 'Could not parse response';
      } else {
        print("VoiceInputService: ASR failed with status ${response.statusCode}");
        return '';
      }
    } catch (e) {
      print("VoiceInputService: Error during transcription: $e");
      return '';
    }
  }
}
