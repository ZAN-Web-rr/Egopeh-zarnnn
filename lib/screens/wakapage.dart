// lib/screens/wakapage.dart

import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../constants/colors.dart';
import '../constants/text.dart';
import '../services/azure_conversation.dart';
import 'mail.dart'; // contains VertexAIService now

class WakaPage extends StatefulWidget {
  const WakaPage({Key? key}) : super(key: key);

  @override
  _WakaPageState createState() => _WakaPageState();
}

class _WakaPageState extends State<WakaPage> with SingleTickerProviderStateMixin {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  late final AnimationController _spinController;
  late final stt.SpeechToText _speech;
  late final ScrollController _scrollController;
  bool _listening = false;

  // Firestore & user
  final _firestore = FirebaseFirestore.instance;
  late final String _uid;

  // default color hex for AI-created items (same format used elsewhere)
  final String _defaultAiColorHex = '#${AppColors.blue.value.toRadixString(16).padLeft(8, '0')}';

  // Pending action state: while assistant asks clarifying questions this holds the intent & params.
  Map<String, dynamic>? _pendingAction; // e.g. {'intent':'create_task', 'params': {...}}
  final List<String> _pendingMissing = []; // ordered list of missing required fields

  @override
  void initState() {
    super.initState();

    // 1) Initialize spinner & STT
    _speech = stt.SpeechToText();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();

    // scroll controller for auto-scroll
    _scrollController = ScrollController();

    // 2) Check auth
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/login');
      });
      return;
    }
    _uid = user.uid;

    // 3) Load chat history
    _firestore
        .collection('users/$_uid/waka_history')
        .orderBy('timestamp')
        .get()
        .then((snap) {
      final loaded = snap.docs.map((d) => _ChatMessage(
        text: d['text'] as String,
        isUser: d['isUser'] as bool,
      )).toList();
      if (!mounted) return;
      setState(() => _messages.addAll(loaded));
      // scroll to end after loading history
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });

    // 4) Initialize Vertex AI (non-blocking). Adjust location/model if needed.
    _initVertexAi();
  }

  Future<void> _initVertexAi() async {
    try {
      await VertexAIService.instance.init(location: 'us-central1', modelName: 'gemini-2.5-flash-lite');
      debugPrint('VertexAI initialized');
    } catch (e) {
      debugPrint('VertexAI init error: $e');
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    _speech.stop();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Helper: add assistant message to UI + persist to waka_history
  Future<void> _addAssistantMessage(String text) async {
    setState(() => _messages.add(_ChatMessage(text: text, isUser: false)));
    _scrollToBottom();
    await _firestore.collection('users/$_uid/waka_history').add({
      'text': text,
      'isUser': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _sendText(String text) async {
    if (text.isEmpty) return;
    _controller.clear();

    // Add & persist user message
    final userMsg = _ChatMessage(text: text, isUser: true);
    setState(() => _messages.add(userMsg));
    _scrollToBottom();

    await _firestore.collection('users/$_uid/waka_history').add({
      'text': text,
      'isUser': true,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Show spinner-bubble
    setState(() => _messages.add(_ChatMessage(text: '...', isUser: false)));
    _scrollToBottom();

    try {
      // If we are mid-way through collecting missing info for a pendingAction, treat this message as the answer.
      if (_pendingAction != null && _pendingMissing.isNotEmpty) {
        final field = _pendingMissing.removeAt(0);
        final params = (_pendingAction!['params'] as Map<String, dynamic>? ) ?? <String, dynamic>{};
        params[field] = text.trim();
        _pendingAction!['params'] = params;

        // If still missing required fields, ask next question
        if (_pendingMissing.isNotEmpty) {
          final nextField = _pendingMissing.first;
          String ask;
          if (nextField == 'title') {
            ask = 'Okay — what should I call it?';
          } else if (nextField == 'due_date' || nextField == 'start') {
            ask = 'When should it start (provide a date or date+time)?';
          } else {
            ask = 'Please provide $nextField.';
          }

          // Replace spinner with assistant question
          setState(() {
            _messages
              ..removeLast()
              ..add(_ChatMessage(text: ask, isUser: false));
          });
          await _firestore.collection('users/$_uid/waka_history').add({
            'text': ask,
            'isUser': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
          _scrollToBottom();
          return;
        } else {
          // All required fields provided -> proceed to create resource
          final intent = (_pendingAction!['intent'] as String);
          final filledParams = Map<String, dynamic>.from(_pendingAction!['params'] as Map);
          // clear pending before creation to avoid re-entrancy
          _pendingAction = null;
          _pendingMissing.clear();

          if (intent == 'create_task') {
            await _createTaskFromParams(filledParams);
            return;
          } else if (intent == 'create_event') {
            await _createEventFromParams(filledParams);
            return;
          } else {
            // shouldn't happen; fallthrough to NLU
          }
        }
      }

      // 1) Try to detect intent from the user's message (NLU)
      final intentResult = await _detectIntent(text);

      // 2) If intent requires action, handle it (create task/event)
      if (intentResult != null && intentResult['intent'] != null) {
        final intent = (intentResult['intent'] as String).toLowerCase();
        final params = (intentResult['params'] as Map<String, dynamic>? ) ?? <String, dynamic>{};

        if (intent == 'create_task') {
          // Required fields for task: title
          final title = (params['title'] as String?)?.trim();
          final dueStr = (params['due_date'] as String?)?.trim();
          final notes = (params['notes'] as String?) ?? '';

          if (title == null || title.isEmpty) {
            // need title -> set pendingAction and ask
            _pendingAction = {'intent': 'create_task', 'params': params};
            _pendingMissing.clear();
            _pendingMissing.add('title');

            // Replace spinner with assistant question
            final ask = 'Sure — what should I call this task?';
            setState(() {
              _messages
                ..removeLast()
                ..add(_ChatMessage(text: ask, isUser: false));
            });
            await _firestore.collection('users/$_uid/waka_history').add({
              'text': ask,
              'isUser': false,
              'timestamp': FieldValue.serverTimestamp(),
            });
            _scrollToBottom();
            return;
          }

          // Title exists -> create immediately
          final buildParams = {
            'title': title,
            'due_date': dueStr,
            'notes': notes,
          };
          await _createTaskFromParams(buildParams);
          return;
        } else if (intent == 'create_event') {
          // Required fields for event: title, start
          final title = (params['title'] as String?)?.trim();
          final startStr = (params['start'] as String?)?.trim();
          final endStr = (params['end'] as String?)?.trim();
          final location = (params['location'] as String?) ?? '';
          final description = (params['description'] as String?) ?? '';

          final missing = <String>[];
          if (title == null || title.isEmpty) missing.add('title');
          if (startStr == null || startStr.isEmpty) missing.add('start');

          if (missing.isNotEmpty) {
            // Ask for missing info in sequence
            _pendingAction = {'intent': 'create_event', 'params': params};
            _pendingMissing.clear();
            _pendingMissing.addAll(missing);

            final first = _pendingMissing.first;
            String ask;
            if (first == 'title') {
              ask = 'Okay — what is the title for the event?';
            } else if (first == 'start') {
              ask = 'When should the event start? (date or date and time is fine)';
            } else {
              ask = 'Please provide $first.';
            }

            setState(() {
              _messages
                ..removeLast()
                ..add(_ChatMessage(text: ask, isUser: false));
            });
            await _firestore.collection('users/$_uid/waka_history').add({
              'text': ask,
              'isUser': false,
              'timestamp': FieldValue.serverTimestamp(),
            });
            _scrollToBottom();
            return;
          }

          // All required present -> create
          final buildParams = {
            'title': title!,
            'start': startStr,
            'end': endStr,
            'location': location,
            'description': description,
          };
          await _createEventFromParams(buildParams);
          return;
        }
      }

      // 3) Otherwise, call the conversational model to get an assistant reply.
      // Use the VertexAIService chat session so context is preserved.
      final reply = await VertexAIService.instance.sendMessageToChat('user', text);

      // replace spinner + scroll
      setState(() {
        _messages
          ..removeLast()
          ..add(_ChatMessage(text: reply, isUser: false));
      });
      _scrollToBottom();

      await _firestore.collection('users/$_uid/waka_history').add({
        'text': reply,
        'isUser': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      setState(() {
        _messages
          ..removeLast()
          ..add(_ChatMessage(text: 'Error: $e', isUser: false));
      });
      _scrollToBottom();
    }
  }

  // Create task after all required fields gathered
  Future<void> _createTaskFromParams(Map<String, dynamic> params) async {
    final title = (params['title'] as String?) ?? '';
    final dueStr = (params['due_date'] as String?) ?? '';
    final notes = (params['notes'] as String?) ?? '';

    dynamic storedDue;
    Timestamp? canonicalDate;
    if (dueStr.isNotEmpty) {
      final parsed = _tryParseDate(dueStr.trim());
      if (parsed != null) {
        storedDue = Timestamp.fromDate(parsed);
        canonicalDate = storedDue as Timestamp;
      } else {
        storedDue = dueStr.trim();
      }
    }

    final docRef = await _firestore.collection('users/$_uid/tasks').add({
      'title': title,
      'notes': notes,
      'dueDate': storedDue,
      // write a canonical 'date' field as Timestamp if we have a parsed date to help calendar/home
      if (canonicalDate != null) 'date': canonicalDate,
      'createdAt': FieldValue.serverTimestamp(),
      'completed': false,
      'createdBy': _uid,
      'color': _defaultAiColorHex,
    });

    // Build short success message (no ID)
    String success;
    if (canonicalDate != null) {
      success = 'Task created successfully — \"$title\" (due ${DateFormat.yMMMd().format(canonicalDate.toDate())})';
    } else if (dueStr.isNotEmpty) {
      success = 'Task created successfully — \"$title\" (due $dueStr)';
    } else {
      success = 'Task created successfully — \"$title\"';
    }

    // Replace spinner with confirmation and persist
    setState(() {
      _messages
        ..removeLast()
        ..add(_ChatMessage(text: success, isUser: false));
    });
    await _firestore.collection('users/$_uid/waka_history').add({
      'text': success,
      'isUser': false,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Add notification
    try {
      final notifBody = canonicalDate != null
          ? '$title on ${DateFormat.yMMMd().format(canonicalDate.toDate())}'
          : (dueStr.isNotEmpty ? '$title on $dueStr' : title);
      await _firestore.collection('users/$_uid/notifications').add({
        'title': 'New Task created',
        'body': notifBody,
        'date': FieldValue.serverTimestamp(),
        'unread': true,
      });
    } catch (e) {
      debugPrint('Failed to create notification for task: $e');
    }

    _scrollToBottom();
  }

  // Create event after all required fields gathered
  Future<void> _createEventFromParams(Map<String, dynamic> params) async {
    final title = (params['title'] as String?) ?? '';
    final startStr = (params['start'] as String?) ?? '';
    final endStr = (params['end'] as String?) ?? '';
    final location = (params['location'] as String?) ?? '';
    final description = (params['description'] as String?) ?? '';

    dynamic storedStart;
    dynamic storedEnd;
    Timestamp? canonicalStart;
    if (startStr.isNotEmpty) {
      final ps = _tryParseDate(startStr.trim());
      if (ps != null) {
        storedStart = Timestamp.fromDate(ps);
        canonicalStart = storedStart as Timestamp;
      } else {
        storedStart = startStr.trim();
      }
    }
    if (endStr.isNotEmpty) {
      final pe = _tryParseDate(endStr.trim());
      if (pe != null) {
        storedEnd = Timestamp.fromDate(pe);
      } else {
        storedEnd = endStr.trim();
      }
    }

    final docRef = await _firestore.collection('users/$_uid/events').add({
      'title': title,
      'start': storedStart,
      if (storedEnd != null) 'end': storedEnd,
      'location': location,
      'description': description,
      'completed': false,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _uid,
      'color': _defaultAiColorHex,
      // canonical 'date' for calendar sorting if we have parsed start
      if (canonicalStart != null) 'date': canonicalStart,
    });

    // Short success message with a few details
    String success;
    if (canonicalStart != null) {
      success = 'Event created successfully — \"$title\" on ${DateFormat.yMMMd().format(canonicalStart.toDate())}${location.isNotEmpty ? ' at $location' : ''}';
    } else if (startStr.isNotEmpty) {
      success = 'Event created successfully — \"$title\" on $startStr${location.isNotEmpty ? ' at $location' : ''}';
    } else {
      success = 'Event created successfully — \"$title\"';
    }

    // Replace spinner with confirmation and persist
    setState(() {
      _messages
        ..removeLast()
        ..add(_ChatMessage(text: success, isUser: false));
    });
    await _firestore.collection('users/$_uid/waka_history').add({
      'text': success,
      'isUser': false,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Add notification
    try {
      final notifBody = canonicalStart != null
          ? '$title on ${DateFormat.yMMMd().format(canonicalStart.toDate())}'
          : (startStr.isNotEmpty ? '$title on $startStr' : title);
      await _firestore.collection('users/$_uid/notifications').add({
        'title': 'New Event created',
        'body': notifBody,
        'date': FieldValue.serverTimestamp(),
        'unread': true,
      });
    } catch (e) {
      debugPrint('Failed to create notification for event: $e');
    }

    _scrollToBottom();
  }

  /// Ask the Vertex AI model to extract intent and params.
  /// The model should return a JSON string like: {"intent":"create_task","params":{"title":"Buy milk","due_date":"2025-08-30"}}
  Future<Map<String, dynamic>?> _detectIntent(String userText) async {
    if (userText.trim().isEmpty) return null;

    final prompt = '''
You are an NLU extractor. Given the user's utterance, respond ONLY with a JSON object (no additional text) with keys:
- "intent" : one of ["create_task", "create_event", "other"]
- "params" : an object containing parameters depending on intent.

Rules:
- For create_task, params may include: "title", "due_date" (YYYY-MM-DD or empty), "notes".
- For create_event, params may include: "title", "start" (ISO or YYYY-MM-DD HH:MM), "end", "location", "description".
- For other intents return {"intent":"other","params":{}}.

User utterance:
\"\"\"$userText\"\"\"
''';

    try {
      // Generate the JSON response
      final raw = await VertexAIService.instance.generateTextFromPrompt(prompt, modelName: 'gemini-2.5-flash-lite');
      if (raw.trim().isEmpty) return null;

      // Try to find the first JSON object inside the response
      final jsonStart = raw.indexOf('{');
      final jsonEnd = raw.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
        debugPrint('NLU did not return JSON: $raw');
        return null;
      }
      final jsonStr = raw.substring(jsonStart, jsonEnd + 1);

      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      // Normalize keys
      final intent = (decoded['intent'] as String?) ?? 'other';
      final params = (decoded['params'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      return {'intent': intent, 'params': params};
    } catch (e) {
      debugPrint('Intent detection error: $e');
      return null;
    }
  }

  /// Try parsing a date/time string into a DateTime, returns null on failure.
  DateTime? _tryParseDate(String s) {
    // Quick direct parse (ISO-like)
    var dt = DateTime.tryParse(s);
    if (dt != null) return dt;

    // Try common formats (YYYY-MM-DD)
    try {
      final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
      if (match != null) {
        final y = int.parse(match.group(1)!);
        final m = int.parse(match.group(2)!);
        final d = int.parse(match.group(3)!);
        return DateTime(y, m, d);
      }
    } catch (_) {}

    // Try parsing "d MMM yyyy" or other human formats using intl (best-effort)
    try {
      final f1 = DateFormat.yMMMd();
      final d1 = f1.parseLoose(s);
      if (d1 != null) return d1;
    } catch (_) {}

    // Give up
    return null;
  }

  Future<void> _startListening() async {
    if (!_listening) {
      final available = await _speech.initialize();
      if (!available) return;
      setState(() => _listening = true);
      _speech.listen(onResult: (r) {
        if (r.finalResult) {
          _sendText(r.recognizedWords);
          setState(() => _listening = false);
          _speech.stop();
        }
      });
    } else {
      setState(() => _listening = false);
      _speech.stop();
    }
  }

  /// Scroll helper to animate to bottom
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      try {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      } catch (_) {}
    });
  }

  /// Delete conversation: confirm, delete Firestore docs, clear UI.
  Future<void> _deleteConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation'),
        content: const Text('Are you sure you want to delete this conversation? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;

    // show progress
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      final coll = _firestore.collection('users/$_uid/waka_history');
      final snap = await coll.get();
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // clear UI
      if (mounted) {
        setState(() => _messages.clear());
      }
      Navigator.of(context, rootNavigator: true).pop(); // close loader
      await showStatusModal(context, 'Conversation deleted', icon: Icons.delete_forever, color: Colors.red);
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      debugPrint('Delete conversation error: $e');
      await showStatusModal(context, 'Could not delete conversation', subtitle: e.toString(), icon: Icons.error, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.black),
          onPressed: () =>
              Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (_) => false),
        ),
        title: Row(
          children: [
            Image.asset('assets/images/new.png', height: 32),
            const SizedBox(width: 8),

            const Spacer(),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.black),
              onPressed: _deleteConversation,
              tooltip: 'Delete conversation',
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: AppColors.black),
              onPressed: () => Navigator.pushNamed(context, '/settings'),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Chat history
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, i) {
                  final m = _messages[i];
                  return Align(
                    alignment:
                    m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: m.isUser
                            ? AppColors.blue.withOpacity(0.2)
                            : AppColors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.blue),
                      ),
                      child: Text(m.text, style: AppText.bodyText),
                    ),
                  );
                },
              ),
            ),

            // ——— FLOATING SPINNER BUTTON ———
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/voice-ai',
                    arguments: _controller.text.trim(),
                  ),
                  child: RotationTransition(
                    turns: _spinController,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF001F54), Colors.blue],
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Input row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Type a prompt…',
                        hintStyle:
                        AppText.bodyText.copyWith(color: Colors.grey, fontSize: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onSubmitted: _sendText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    onPressed: _startListening,
                    backgroundColor:
                    _listening ? AppColors.blue.withOpacity(0.6) : AppColors.blue,
                    child: Icon(_listening ? Icons.mic_off : Icons.mic),
                    mini: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}
