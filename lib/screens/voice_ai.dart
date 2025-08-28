// lib/screens/voice_ai_screen.dart
// Simplified voice-only flow: direct PCM16 -> base64 -> HTTP POST to /voice/process
// Behavior changes made per request:
//  - No periodic chunk uploads (no "chunks" shown or sent). Only final sends on end-of-speech or manual "Send Now".
//  - Suppressed non-error debug prints (only errors shown when widget.debug=true).
//  - Reduced recorder progress frequency to reduce frame rate.
//  - Goal: Simply capture user's voice, send to backend when speech ends (VAD), play voice reply.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';

class VoiceAiScreen extends StatefulWidget {
  final String apiBaseUrl;
  final String? initialSessionId;
  final bool debug;

  const VoiceAiScreen({
    Key? key,
    required this.apiBaseUrl,
    this.initialSessionId,
    this.debug = true,
  }) : super(key: key);

  @override
  State<VoiceAiScreen> createState() => _VoiceAiScreenState();
}

class _VoiceAiScreenState extends State<VoiceAiScreen> with SingleTickerProviderStateMixin {
  // flutter_sound recorder
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderInitialized = false;

  final AudioPlayer _player = AudioPlayer();

  // recording / processing state
  bool _isRecording = false; // recorder actively capturing
  bool _isProcessing = false; // AI/server processing / responding
  String _transcript = '';
  String? _sessionId;

  // streaming controllers for direct PCM
  StreamController<Uint8List>? _pcmController; // preferred typed controller
  StreamController<dynamic>? _rawPcmController; // fallback raw controller
  StreamSubscription<dynamic>? _pcmSubscription;
  bool _usingRawController = false;

  // Buffer to gather PCM bytes to send on final
  final List<int> _collectedPcm = [];

  // Buffer capping to avoid runaway memory usage
  // Reduced default to avoid large memory growth on devices that emit many frames.
  final int _maxBufferBytes = 64 * 1024; // 64 KB (was ~192KB)
  final int _minChunkBytes = 1024; // minimal bytes to consider a final send

  // limit bytes sent in a single HTTP request (helps prevent server side payload limits/timeouts)
  // lowered to reduce likelihood of server aborts on large POSTs
  final int _maxSendBytes = 32 * 1024; // 32 KB of raw PCM (~43KB base64); // 48 KB of raw PCM (will base64 -> ~64KB payload)

  // UI animation
  late final AnimationController _pulseController;
  final Duration _httpTimeout = const Duration(seconds: 30); // reduced timeout to avoid long UI blocking

  // Debug inspector (kept minimal)
  int? _lastResponseStatus;
  String? _lastResponseBody;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.initialSessionId;
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);

    _initRecorder();
  }

  /// Initialize recorder with fallback to openAudioSession() if available.
  Future<void> _initRecorder() async {
    try {
      await _recorder.openRecorder();
      _recorderInitialized = true;

      // Try to open audio session if available (some flutter_sound versions expose this).
      try {
        ( _recorder as dynamic ).openAudioSession();
      } catch (_) {}

      // reduce subscription frequency to lower frame rate / callbacks
      try {
        await _recorder.setSubscriptionDuration(const Duration(milliseconds: 400));
      } catch (_) {}

      if (widget.debug) {
        // keep only an informational debug when debug=true
        debugPrint('Recorder initialized (reduced subscription frequency).');
      }
    } catch (e, st) {
      debugPrint('Recorder init error: $e\n$st');
      _recorderInitialized = false;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _player.dispose();
    _stopRecording();
    try {
      if (_recorderInitialized) _recorder.closeRecorder();
    } catch (_) {}
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Cancel existing controllers/subscriptions
  Future<void> _cleanupControllers() async {
    try {
      await _pcmSubscription?.cancel();
    } catch (_) {}
    _pcmSubscription = null;

    try {
      await _pcmController?.close();
    } catch (_) {}
    _pcmController = null;

    try {
      await _rawPcmController?.close();
    } catch (_) {}
    _rawPcmController = null;

    _usingRawController = false;
  }

  /// Create a typed controller & subscription (Uint8List frames expected).
  void _createTypedControllerAndListener() {
    _pcmController = StreamController<Uint8List>();
    _usingRawController = false;

    _pcmSubscription = _pcmController!.stream.listen((dynamic frame) async {
      await _handleIncomingFrame(frame);
    }, onError: (err) {
      debugPrint('PCM stream error (typed): $err');
    }, onDone: () {
      if (widget.debug) debugPrint('PCM typed stream done');
    });
  }

  /// Create a raw controller & subscription (dynamic frames).
  void _createRawControllerAndListener() {
    _rawPcmController = StreamController<dynamic>();
    _usingRawController = true;

    _pcmSubscription = _rawPcmController!.stream.listen((dynamic frame) async {
      await _handleIncomingFrame(frame);
    }, onError: (err) {
      debugPrint('PCM stream error (raw): $err');
    }, onDone: () {
      if (widget.debug) debugPrint('PCM raw stream done');
    });
  }

  /// Universal handler - robustly extracts bytes from multiple frame types.
  Future<void> _handleIncomingFrame(dynamic frame) async {
    if (_isProcessing) {
      // drop frames while processing
      return;
    }

    // Extract bytes robustly
    Uint8List? bytes;
    try {
      if (frame is Uint8List) {
        bytes = frame;
      } else if (frame is List<int>) {
        bytes = Uint8List.fromList(frame);
      } else {
        final dynamic f = frame;
        if (f is Map && f['data'] != null) {
          final dyn = f['data'];
          if (dyn is Uint8List) bytes = dyn;
          else if (dyn is List<int>) bytes = Uint8List.fromList(List<int>.from(dyn));
        } else {
          try {
            final dynData = f.data;
            if (dynData is Uint8List) bytes = dynData;
            else if (dynData is List<int>) bytes = Uint8List.fromList(List<int>.from(dynData));
          } catch (_) {
            // not accessible
          }
        }
      }
    } catch (e, st) {
      if (widget.debug) debugPrint('Frame extraction error: $e\n$st');
      return;
    }

    if (bytes == null) {
      if (widget.debug) debugPrint('Unknown PCM frame type: ${frame.runtimeType} (ignored)');
      return;
    }

    // Simply collect all bytes while recording
    _collectedPcm.addAll(bytes);

    // Trim buffer if it grows above max
    if (_collectedPcm.length > _maxBufferBytes) {
      final drop = _collectedPcm.length - _maxBufferBytes;
      _collectedPcm.removeRange(0, drop);
      if (widget.debug) debugPrint('Buffer capped: dropped $drop bytes, buffered=${_collectedPcm.length}');
    }
  }

  /// Try to start recorder using typed controller first; fallback to raw controller if runtime type error occurs.
  Future<void> _startRecorderWithController() async {
    // Clean up any existing controllers/subscriptions
    await _cleanupControllers();

    // Create typed controller + listener first
    _createTypedControllerAndListener();

    try {
      // Try to start recorder with typed Uint8List sink
      await _recorder.startRecorder(
        toStream: _pcmController!.sink,
        codec: Codec.pcm16,
        sampleRate: 16000,
        numChannels: 1,
      );
      _usingRawController = false;
      return;
    } catch (e, st) {
      // If this fails (runtime type issues / some flutter_sound platforms), try the raw fallback
      debugPrint('startRecorder (typed) failed: $e\n$st');
      // ensure we close typed controller
      try {
        await _pcmSubscription?.cancel();
      } catch (_) {}
      try {
        await _pcmController?.close();
      } catch (_) {}
      _pcmController = null;

      // Fallback: create a raw controller and pass its sink as dynamic to startRecorder
      _createRawControllerAndListener();
      try {
        // Cast the sink to dynamic to bypass static typing when calling startRecorder
        await _recorder.startRecorder(
          toStream: (_rawPcmController!.sink as dynamic),
          codec: Codec.pcm16,
          sampleRate: 16000,
          numChannels: 1,
        );
        _usingRawController = true;
        return;
      } catch (e2, st2) {
        // If fallback fails too, surface error
        debugPrint('startRecorder (raw fallback) failed: $e2\n$st2');
        try {
          await _rawPcmController?.close();
        } catch (_) {}
        _rawPcmController = null;
        rethrow; // let caller handle
      }
    }
  }

  /// Starts recording
  Future<void> _startRecording() async {
    if (_isRecording) return;

    if (!await _requestPermissions()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission required')));
      return;
    }
    if (!_recorderInitialized) {
      await _initRecorder();
      if (!_recorderInitialized) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recorder failed to initialize')));
        return;
      }
    }

    // Clear previous recording
    _collectedPcm.clear();

    try {
      await _startRecorderWithController();
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('startRecording - startRecorder error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Recording start error: $e')));
      return;
    }

    if (widget.debug) debugPrint('Recording started.');
  }

  /// Stop recording and send the audio
  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    // stop recorder (this closes the toStream sink)
    if (_recorder.isRecording) {
      try {
        await _recorder.stopRecorder();
      } catch (e) {
        debugPrint('stopRecorder error: $e');
      }
    }

    // cleanup stream controller/subscription
    await _cleanupControllers();
    if (mounted) setState(() => _isRecording = false);

    // send the recorded PCM
    if (_collectedPcm.isNotEmpty) {
      await _sendCurrentPcmChunk(finalize: true);
    }

    if (widget.debug) debugPrint('Recording stopped.');
  }

  /// Send the snapshot of current PCM buffer via HTTP to /voice/process.
  Future<void> _sendCurrentPcmChunk({required bool finalize}) async {
    if (_isProcessing) return;
    if (mounted) {
      setState(() => _isProcessing = true);
    } else {
      _isProcessing = true;
    }
    try {
      // copy & clear buffer atomically
      final List<int> sendBytes = List<int>.from(_collectedPcm);
      _collectedPcm.clear();

      if (sendBytes.isEmpty || sendBytes.length < _minChunkBytes) {
        // nothing meaningful to send
        _isProcessing = false;
        return;
      }

      // Ensure even length (16-bit samples)
      if (sendBytes.length % 2 != 0) sendBytes.add(0);

      // If sendBytes too big for a single HTTP request, keep only the most recent _maxSendBytes
      // and requeue the older leftover so we don't lose it.
      if (sendBytes.length > _maxSendBytes) {
        final int start = sendBytes.length - _maxSendBytes;
        final List<int> trimmed = sendBytes.sublist(start);
        sendBytes
          ..clear()
          ..addAll(trimmed);
      }

      final b64 = base64Encode(sendBytes);

      // Always use HTTP in voice-only mode
      await _sendAudioViaHttp(b64, finalize: finalize);
    } catch (e, st) {
      debugPrint('sendCurrentPcmChunk error: $e\n$st');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      } else {
        _isProcessing = false;
      }
    }
  }

  // ---------------------------
  // HTTP send & play helpers
  // ---------------------------

  Future<void> _sendAudioViaHttp(String audioBase64, {required bool finalize}) async {
    try {
      Future<http.Response> doPost(String? sessionId) {
        final url = Uri.parse('${widget.apiBaseUrl.replaceAll(RegExp(r'\/\$'), '')}/voice/process');
        final payload = jsonEncode({
          'audio_data': audioBase64,
          if (sessionId != null) 'session_id': sessionId,
          'final': finalize,
          // helpful metadata so backend can properly decode & handle
          'encoding': 'pcm16',
          'sample_rate': 16000,
          'channels': 1,
        });
        return http.post(url, headers: {'Content-Type': 'application/json'}, body: payload).timeout(_httpTimeout);
      }

      // First attempt using current session id (if any)
      final response = await doPost(_sessionId);

      _lastResponseStatus = response.statusCode;
      _lastResponseBody = response.body;

      // If server 5xx, try clearing session_id and retry once
      if (response.statusCode >= 500) {
        final prevSession = _sessionId;
        _sessionId = null;
        try {
          final retryResp = await doPost(_sessionId);
          _lastResponseStatus = retryResp.statusCode;
          _lastResponseBody = retryResp.body;
          if (retryResp.statusCode == 200) {
            final Map<String, dynamic> body = jsonDecode(retryResp.body);
            if (!mounted) return;
            setState(() {
              _transcript = body['text'] ?? _transcript;
              _sessionId = body['session_id'] ?? _sessionId;
            });
            final audioData = body['audio_data'];
            if (audioData != null && audioData is String && audioData.isNotEmpty) {
              await _playBase64Audio(audioData);
            }
            return;
          } else {
            // still not OK — restore prev session id and show error.
            _sessionId = prevSession;
            if (!mounted) return;
            await showDialog(context: context, builder: (_) => AlertDialog(
              title: Text('API Error ${retryResp.statusCode}'),
              content: SingleChildScrollView(child: Text(_truncate(retryResp.body, 4000))),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
            ));
            return;
          }
        } catch (retryErr) {
          debugPrint('Retry after 5xx failed: $retryErr');
          _sessionId = prevSession;
          if (retryErr is http.ClientException) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error sending audio')));
            return;
          }
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request failed (server error) — retry failed')));
          return;
        }
      }

      // Normal 200 path
      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _transcript = body['text'] ?? _transcript;
          _sessionId = body['session_id'] ?? _sessionId;
        });
        final audioData = body['audio_data'];
        if (audioData != null && audioData is String && audioData.isNotEmpty) {
          await _playBase64Audio(audioData);
        }
      } else {
        if (!mounted) return;
        await showDialog(context: context, builder: (_) => AlertDialog(
          title: Text('API Error ${response.statusCode}'),
          content: SingleChildScrollView(child: Text(_truncate(response.body, 4000))),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ));
      }
    } on TimeoutException catch (e) {
      debugPrint('HTTP timeout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request timed out (HTTP)')));
        setState(() => _isProcessing = false);
      } else {
        _isProcessing = false;
      }
    } catch (e, st) {
      debugPrint('HTTP send error: $e\n$st');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send error: $e')));
    }
  }

  Future<void> _playBase64Audio(String base64Audio) async {
    try {
      final bytes = base64Decode(base64Audio);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/zarn_response_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await file.writeAsBytes(bytes, flush: true);
      await _player.stop();
      await _player.play(DeviceFileSource(file.path));
    } catch (e, st) {
      debugPrint('Play audio error: $e\n$st');
    }
  }

  String _truncate(String? s, int max) {
    if (s == null) return '';
    if (s.length <= max) return s;
    return s.substring(0, max) + '...';
  }

  void _openDebugInspector() {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Debug Inspector'),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Last Response (status & body):', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Status: ${_lastResponseStatus ?? '-'}'),
        const SizedBox(height: 6),
        SelectableText(_lastResponseBody ?? '(none)'),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  Widget _buildAiAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0D47A1), Color(0xFF42A5F5)]),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.2), blurRadius: 12, offset: const Offset(0,6))],
      ),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [
        Icon(Icons.smart_toy, size: 40, color: Colors.white),
        SizedBox(height: 6),
        Text('Zarn', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ])),
    );
  }

  Widget _buildStatusChip() {
    if (_isProcessing) return Chip(label: const Text('AI Responding'), backgroundColor: Colors.blue.shade100);
    if (_isRecording) return Chip(label: const Text('Recording'), backgroundColor: Colors.green.shade100);
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zarn — Voice AI', style: TextStyle(color: Colors.blue)),
        backgroundColor: Colors.white, elevation: 0, iconTheme: const IconThemeData(color: Colors.blue),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.bug_report, color: Colors.blue), tooltip: 'Open debug inspector', onPressed: _openDebugInspector)],
      ),
      backgroundColor: Colors.white,
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, children: [
        _buildAiAvatar(120),
        const SizedBox(height: 18),
        Text(_isRecording ? 'Recording — speak now' : (_isProcessing ? 'AI is responding' : 'Ready to record'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.black87)),
        const SizedBox(height: 18),
        _buildStatusChip(),
        const SizedBox(height: 24),
        Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 2, child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Transcript', style: TextStyle(fontWeight: FontWeight.bold)),
                if (_sessionId != null) Text('session: ${_sessionId!.substring(0,8)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
              const SizedBox(height: 12),
              SizedBox(height: 140, child: SingleChildScrollView(child: Text(_transcript.isEmpty ? 'No transcript yet. Record to get started.' : _transcript, style: const TextStyle(fontSize: 16)))),
            ]))),
        const SizedBox(height: 30),
        SizedBox(width: 160, height: 160, child: Stack(alignment: Alignment.center, children: [
          ScaleTransition(scale: Tween(begin: 0.9, end: 1.05).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)), child: Container(
            width: 160, height: 160,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
              boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.12), blurRadius: 20, offset: const Offset(0,10))],
            ),
          )),
          // mic indicator / manual toggle
          FloatingActionButton(
            onPressed: () async {
              if (_isProcessing) return; // Don't allow interaction while processing

              if (_isRecording) {
                await _stopRecording();
              } else {
                await _startRecording();
              }
            },
            backgroundColor: _isProcessing ? Colors.grey : (_isRecording ? Colors.green : Colors.blue),
            child: Icon(_isProcessing ? Icons.pause : (_isRecording ? Icons.mic : Icons.mic_none), size: 36),
            elevation: 6,
          ),
        ])),
        const SizedBox(height: 18),
        if (_isProcessing) const CircularProgressIndicator(),
        const SizedBox(height: 16),

        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(onPressed: () => setState(() => _transcript = ''), icon: const Icon(Icons.clear, color: Colors.blue), label: const Text('Clear', style: TextStyle(color: Colors.blue))),
            TextButton.icon(onPressed: () async {
              await showDialog(context: context, builder: (_) => AlertDialog(
                title: const Text('API Endpoint'),
                content: Text('Using: ${widget.apiBaseUrl}\n\nMake sure your backend exposes POST /voice/process that accepts JSON {audio_data: "<base64>", session_id?: "...", final?: bool, encoding:, sample_rate:, channels: } and returns {text, session_id, audio_data}.'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
              ));
            }, icon: const Icon(Icons.info_outline, color: Colors.blue), label: const Text('API Info', style: TextStyle(color: Colors.blue))),
          ],
        ),

        const SizedBox(height: 16),
        const SizedBox(height: 20),
      ],
      ))),
    );
  }
}