// lib/services/azure_conversation.dart
//
// Robust Vertex AI wrapper that tries multiple SDK shapes at runtime.
// This file attempts to be compatible with several firebase_ai / firebase_vertexai versions.

import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VertexAIService {
  VertexAIService._();
  static final VertexAIService instance = VertexAIService._();

  dynamic _ai; // FirebaseAI / VertexAI client
  dynamic _model; // GenerativeModel
  dynamic _chat; // ChatSession or LocalChatSession

  Future<void> init({
    String location = 'us-central1',
    String modelName = 'gemini-2.5-flash-lite',
    GenerationConfig? generationConfig,
  }) async {
    // Try the modern factory signature; fallback to older variant if needed.
    try {
      _ai = FirebaseAI.vertexAI(auth: FirebaseAuth.instance, location: location);
    } catch (e) {
      try {
        _ai = FirebaseAI.vertexAI(location: location);
      } catch (e2) {
        rethrow;
      }
    }

    final genConfig = generationConfig ??
        GenerationConfig(
          maxOutputTokens: 65535,
          temperature: 1,
          topP: 0.95,
        );

    _model = _ai.generativeModel(model: modelName, generationConfig: genConfig);

    if (kDebugMode) debugPrint('VertexAIService initialized (location=$location, model=$modelName)');
  }

  Future<void> createModelWithSystemInstruction(
      String systemText, {
        String modelName = 'gemini-2.5-flash-lite',
        GenerationConfig? generationConfig,
        List<dynamic>? safetySettings,
      }) async {
    if (_ai == null) {
      await init(location: 'us-central1', modelName: modelName, generationConfig: generationConfig);
    }

    final genConfig = generationConfig ??
        GenerationConfig(
          maxOutputTokens: 65535,
          temperature: 1,
          topP: 0.95,
        );

    final systemInstruction = Content('system', [TextPart(systemText)]);

    _model = _ai.generativeModel(
      model: modelName,
      generationConfig: genConfig,
      systemInstruction: systemInstruction,
      // safetySettings: safetySettings,
    );

    if (kDebugMode) debugPrint('VertexAIService model created with system instruction (model=$modelName)');
  }

  /// Try to start an SDK chat session; fallback to LocalChatSession wrapper.
  dynamic startChat({List<Content>? history}) {
    if (_model == null) {
      throw Exception('VertexAIService: model not initialized.');
    }

    try {
      _chat = _model.startChat(history: history);
      if (kDebugMode) debugPrint('Using SDK startChat()');
      return _chat;
    } catch (e) {
      if (kDebugMode) debugPrint('startChat not available, using LocalChatSession fallback: $e');
      _chat = LocalChatSession(_model, initialHistory: history);
      return _chat;
    }
  }

  /// Send a message to chat. Works whether SDK chat exists or using LocalChatSession fallback.
  Future<String> sendMessageToChat(String role, String text) async {
    if (_model == null) {
      throw Exception('VertexAIService: model not initialized.');
    }

    if (_chat == null) {
      startChat();
    }

    final content = Content(role, [TextPart(text)]);

    // If chat has sendMessage (SDK chat), prefer it.
    try {
      if (_chat != null) {
        final send = (_chat as dynamic).sendMessage;
        if (send != null) {
          final response = await _chat.sendMessage(content);
          final extracted = _extractTextFromResponse(response);
          if (kDebugMode) debugPrint('sendMessageToChat (sdk) -> $extracted');
          return extracted.trim();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('SDK Chat.sendMessage failed, falling back to generateContent: $e');
    }

    // Fallback: call model.generateContent via flexible arg shapes
    final fullPrompt = _buildPromptFromHistoryAndContent(content);
    final resp = await _callGenerateContentFlexible(_model, fullPrompt);
    final textOut = _extractTextFromResponse(resp);
    if (kDebugMode) debugPrint('sendMessageToChat (fallback) -> $textOut');
    return textOut.trim();
  }

  /// Flexible one-shot generation helper (tries several call signatures).
  Future<dynamic> _callGenerateContentFlexible(dynamic model, String prompt) async {
    // Attempt 1: Iterable<Content> (some SDKs expect a list of Content)
    final contentList = [Content('user', [TextPart(prompt)])];
    try {
      if (kDebugMode) debugPrint('Trying generateContent(Iterable<Content>)');
      final r = await model.generateContent(contentList);
      return r;
    } catch (e1) {
      if (kDebugMode) debugPrint('generateContent(Iterable) failed: $e1');
    }

    // Attempt 2: single Content object
    try {
      if (kDebugMode) debugPrint('Trying generateContent(Content)');
      final r = await model.generateContent(Content('user', [TextPart(prompt)]));
      return r;
    } catch (e2) {
      if (kDebugMode) debugPrint('generateContent(Content) failed: $e2');
    }

    // Attempt 3: raw String
    try {
      if (kDebugMode) debugPrint('Trying generateContent(String)');
      final r = await model.generateContent(prompt);
      return r;
    } catch (e3) {
      if (kDebugMode) debugPrint('generateContent(String) failed: $e3');
    }

    // Attempt 4: sometimes SDKs provide `generateText` or `generate` methods
    try {
      if (kDebugMode) debugPrint('Trying generateText(String) fallback');
      final r = await model.generateText(prompt);
      return r;
    } catch (e4) {
      if (kDebugMode) debugPrint('generateText fallback failed: $e4');
    }

    // Nothing worked: throw with helpful message
    throw Exception('No compatible generateContent signature found on GenerativeModel.');
  }

  /// Build a simple prompt string including recent history (if LocalChatSession used)
  String _buildPromptFromHistoryAndContent(Content newContent) {
    final buffer = StringBuffer();
    if (_chat is LocalChatSession) {
      final lc = _chat as LocalChatSession;
      for (final h in lc.history) {
        final role = h.role ?? 'user';
        buffer.writeln('[$role] ${_textFromContent(h)}\n');
      }
    }
    buffer.writeln('[${newContent.role}] ${_textFromContent(newContent)}\n');
    return buffer.toString();
  }

  String _textFromContent(Content c) {
    try {
      final parts = c.parts as List;
      return parts.map((p) {
        if (p is TextPart) return p.text;
        if (p is Map && p.containsKey('text')) return p['text'].toString();
        return p.toString();
      }).join(' ');
    } catch (_) {
      return c.toString();
    }
  }

  /// Robust extractor that inspects many likely shapes for the model response.
  String _extractTextFromResponse(dynamic resp) {
    if (resp == null) return '';

    // If SDK returned a plain String
    if (resp is String) return resp;

    // If response has .text
    try {
      final txt = resp.text;
      if (txt != null && txt is String && txt.isNotEmpty) return txt;
    } catch (_) {}

    // If response is a Map-like
    try {
      final Map m = resp as Map;
      // common: { 'output': [ { 'content': [ { 'text': '...' } ] } ] }
      if (m.containsKey('output')) {
        final output = m['output'];
        if (output is List && output.isNotEmpty) {
          final first = output.first;
          if (first is Map && first.containsKey('content')) {
            final content = first['content'];
            if (content is List && content.isNotEmpty) {
              // find first text field
              for (final c in content) {
                if (c is Map && c.containsKey('text')) return c['text'].toString();
              }
            }
          }
        }
      }

      // common: { 'candidates': [ { 'content': [ { 'text': '...' } ] } ] }
      if (m.containsKey('candidates')) {
        final cand = m['candidates'];
        if (cand is List && cand.isNotEmpty) {
          final c0 = cand.first;
          if (c0 is Map && c0.containsKey('content')) {
            final content = c0['content'];
            if (content is List && content.isNotEmpty) {
              for (final c in content) {
                if (c is Map && c.containsKey('text')) return c['text'].toString();
                if (c is String) return c;
              }
            }
          }
        }
      }
    } catch (_) {}

    // If response has a nested structure with 'candidates' field as object-like:
    try {
      final dyn = resp as dynamic;
      final cand = dyn.candidates;
      if (cand != null && cand is List && cand.isNotEmpty) {
        final first = cand.first;
        try {
          if (first is Map && first['content'] is List) {
            final cont = first['content'] as List;
            for (final item in cont) {
              if (item is Map && item['text'] != null) return item['text'].toString();
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    // If response has .outputs or .candidates and each has .text-like fields, attempt generically:
    try {
      final asJson = jsonEncode(resp);
      // Try to find the first occurrence of a "text":"..." substring via regex
      final m = RegExp(r'"text"\s*:\s*"([^"]{1,10000})"').firstMatch(asJson);
      if (m != null) return m.group(1) ?? '';
    } catch (_) {}

    // As a last resort, return the object's toString()
    try {
      return resp.toString();
    } catch (_) {
      return '';
    }
  }

  /// One-shot generation wrapper (uses flexible call).
  Future<String> generateTextFromPrompt(
      String prompt, {
        String modelName = 'gemini-2.5-flash-lite',
        GenerationConfig? generationConfig,
      }) async {
    if (_ai == null) {
      await init(location: 'us-central1', modelName: modelName, generationConfig: generationConfig);
    }

    final resp = await _callGenerateContentFlexible(_model, prompt);
    return _extractTextFromResponse(resp).trim();
  }

  /// Summarize email thread (uses createModelWithSystemInstruction then generate).
  Future<String> summarizeEmailThread(String emailThread) async {
    final systemText = 'You are an AI assistant tasked with summarizing email threads. Provide a concise summary that captures main topic, key points, decisions, and action items.';

    await createModelWithSystemInstruction(systemText, modelName: 'gemini-2.5-flash-lite');

    final prompt = '''
You will be provided with an email thread. Create a concise summary that includes:
- Main topic
- Key points discussed
- Decisions made
- Action items assigned

Here is the email thread:
$emailThread
''';

    final resp = await _callGenerateContentFlexible(_model, prompt);
    return _extractTextFromResponse(resp).trim().isNotEmpty ? _extractTextFromResponse(resp).trim() : 'No summary produced.';
  }
}

/// LocalChatSession fallback: builds a simple history and calls model.generateContent(prompt)
class LocalChatSession {
  final dynamic model;
  final List<Content> history = [];

  LocalChatSession(this.model, {List<Content>? initialHistory}) {
    if (initialHistory != null) history.addAll(initialHistory);
  }

  Future<dynamic> sendMessage(Content content) async {
    history.add(content);

    final buffer = StringBuffer();
    for (final c in history) {
      final role = c.role ?? 'user';
      final text = _textFromContent(c);
      buffer.writeln('[$role] $text\n');
    }
    final prompt = buffer.toString();

    // Use the same flexible call path as service
    dynamic resp;
    try {
      resp = await VertexAIService.instance._callGenerateContentFlexible(model, prompt);
    } catch (e) {
      rethrow;
    }

    // Add assistant reply to history for future context if possible
    final assistantText = VertexAIService.instance._extractTextFromResponse(resp);
    history.add(Content('assistant', [TextPart(assistantText)]));

    // Return a small wrapper that contains .text for compatibility
    return _LocalChatResponse(text: assistantText);
  }

  String _textFromContent(Content c) {
    try {
      final parts = c.parts as List;
      return parts.map((p) {
        if (p is TextPart) return p.text;
        if (p is Map && p.containsKey('text')) return p['text'].toString();
        return p.toString();
      }).join(' ');
    } catch (_) {
      return c.toString();
    }
  }
}

class _LocalChatResponse {
  final String text;
  _LocalChatResponse({required this.text});
}
