// lib/services/voice_api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class VoiceApiService {
  static const String baseUrl = 'https://voice-live-api.onrender.com';
  static const String processUrl = '$baseUrl/voice/process';

  /// Send audio data to backend and get response
  /// Returns a map with keys:
  ///  - 'raw': raw response body string
  ///  - 'status': http status code
  ///  - 'json': decoded response body if JSON
  ///  - 'nlu': parsed JSON object if response['text'] contained JSON
  static Future<Map<String, dynamic>> processVoice({
    required String audioBase64,
    String? sessionId,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    try {
      final response = await http.post(
        Uri.parse(processUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'audio_data': audioBase64,
          if (sessionId != null) 'session_id': sessionId,
        }),
      ).timeout(timeout);

      final body = response.body;
      final status = response.statusCode;
      Map<String, dynamic>? bodyJson;
      try {
        bodyJson = jsonDecode(body) as Map<String, dynamic>?;
      } catch (e) {
        bodyJson = null;
      }

      // Attempt to parse model output text as JSON (NLU)
      dynamic parsedNlu;
      try {
        final text = (bodyJson != null && bodyJson['text'] != null) ? bodyJson['text'] as String : null;
        if (text != null) {
          // try direct json parse
          parsedNlu = jsonDecode(text);
        }
      } catch (_) {
        parsedNlu = null;
      }

      return {
        'raw': body,
        'status': status,
        'json': bodyJson,
        'nlu': parsedNlu,
      };
    } catch (e) {
      throw Exception('Voice process error: $e');
    }
  }

  /// List active sessions
  static Future<List<String>> listSessions() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/voice/sessions'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return List<String>.from(data['sessions'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Close a specific session
  static Future<bool> closeSession(String sessionId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/voice/session/$sessionId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
