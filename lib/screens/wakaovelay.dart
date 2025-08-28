// // lib/screens/wakaovelay.dart
//
// import 'dart:async';
// import 'dart:convert';
// import 'dart:io';
// import 'dart:typed_data';
//
// import 'package:flutter/material.dart';
// import 'package:uuid/uuid.dart';
// import 'package:record/record.dart'; // AudioRecorder
// import 'package:flutter_tts/flutter_tts.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:connectivity_plus/connectivity_plus.dart';
//
// import '../constants/colors.dart';
// import '../constants/text.dart';
// import '../services/voiceai.dart';
//
// class WakaOverlayScreen extends StatefulWidget {
//   final String initialPrompt;
//   const WakaOverlayScreen({Key? key, required this.initialPrompt}) : super(key: key);
//
//   @override
//   State<WakaOverlayScreen> createState() => _WakaOverlayScreenState();
// }
//
// class _WakaOverlayScreenState extends State<WakaOverlayScreen>
//     with SingleTickerProviderStateMixin {
//   // Speech + UI
//   late final FlutterTts _tts;
//   late final AnimationController _spinController;
//
//   // Recorder (record package v5+)
//   final AudioRecorder _recorder = AudioRecorder();
//
//   // Connectivity
//   final Connectivity _connectivity = Connectivity();
//
//   // Session & state
//   String? _sessionId;
//   bool _isDisposed = false;
//   bool _recording = false;
//   bool _sending = false;
//   String _status = 'Initializing…';
//   String _serverText = '';
//   String _audioPath = '';
//   Timer? _recordingTimer;
//
//   // Settings
//   static const int _maxRecordingSeconds = 6; // keep short for latency
//   static const int _sampleRate = 16000; // Azure Voice Live likes 16k PCM16
//   static const int _numChannels = 1;
//
//   // ---- Logging helper
//   void _log(String msg) {
//     debugPrint('[Waka][${DateTime.now().toIso8601String()}] $msg');
//   }
//
//   @override
//   void initState() {
//     super.initState();
//     _tts = FlutterTts();
//     _spinController =
//     AnimationController(vsync: this, duration: const Duration(seconds: 2))
//       ..repeat();
//
//     _safeInit();
//   }
//
//   Future<void> _safeInit() async {
//     try {
//       // Initial debug line
//       _log('Screen initialized with initialPrompt: ${widget.initialPrompt}');
//
//       // TTS setup
//       await _setupTts();
//
//       // Start the first cycle after build
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (!_isDisposed) {
//           setState(() => _status = 'Starting…');
//           _startRecordingCycle();
//         }
//       });
//     } catch (e, st) {
//       _log('init error: $e\n$st');
//     }
//   }
//
//   Future<void> _setupTts() async {
//     try {
//       await _tts.setLanguage('en-US');
//       await _tts.setSpeechRate(0.5);
//       await _tts.setVolume(1.0);
//       await _tts.setPitch(1.0);
//       await _tts.awaitSpeakCompletion(true);
//       _log('TTS setup complete');
//     } catch (e) {
//       _log('TTS setup failed: $e');
//     }
//   }
//
//   @override
//   void dispose() {
//     _isDisposed = true;
//     _recordingTimer?.cancel();
//
//     // Stop recorder safely
//     try {
//       _recorder.isRecording().then((r) async {
//         if (r) {
//           _log('dispose(): stopping active recorder…');
//           await _recorder.stop();
//         }
//       });
//     } catch (_) {}
//     // Dispose recorder
//     _recorder.dispose().catchError((_) {});
//
//     // Stop TTS
//     _tts.stop().catchError((_) {});
//     // Dispose animation
//     _spinController.dispose();
//     super.dispose();
//   }
//
//   // ====== RECORDING CYCLE ======
//   Future<void> _startRecordingCycle() async {
//     if (_recording || _sending || _isDisposed) {
//       _log('startRecordingCycle skipped: rec=$_recording send=$_sending disposed=$_isDisposed');
//       return;
//     }
//
//     // Connectivity
//     final conn = await _connectivity.checkConnectivity();
//     _log('Connectivity: $conn');
//     if (conn == ConnectivityResult.none) {
//       if (mounted) setState(() => _status = 'No internet connection');
//       Future.delayed(const Duration(seconds: 3), () {
//         if (!_isDisposed) _startRecordingCycle();
//       });
//       return;
//     }
//
//     // Permission
//     // Permission
//     final perm = await Permission.microphone.request();
//     _log('Microphone permission: $perm');
//     if (perm != PermissionStatus.granted) {
//       if (mounted) setState(() => _status = 'Microphone permission denied');
//       return;
//     }
//
// // Start recording
//     await _recorder.start(
//       RecordConfig(
//         encoder: AudioEncoder.pcm16bits, // RAW PCM16 (no RIFF/WAV header)
//         sampleRate: _sampleRate,
//         numChannels: _numChannels,
//       ),
//       path: _audioPath,
//     );
//
//
//     // Prepare file path (we use .pcm since we are recording headerless PCM16)
//     final tmp = await getTemporaryDirectory();
//     _audioPath =
//     '${tmp.path}/waka_${DateTime.now().millisecondsSinceEpoch}.pcm';
//     _log('Recording will be saved to: $_audioPath');
//
//     // Start recording (RAW PCM16, mono, 16k)
//     try {
//       await _recorder.start(
//         const RecordConfig(
//           encoder: AudioEncoder.pcm16bits, // RAW PCM16 (no RIFF/WAV header)
//           sampleRate: _sampleRate,
//           numChannels: _numChannels,
//           // bitRate is ignored for PCM
//         ),
//         path: _audioPath,
//       );
//
//       final isRec = await _recorder.isRecording();
//       _log('Recorder started: isRecording=$isRec');
//
//       if (mounted) {
//         setState(() {
//           _recording = true;
//           _serverText = '';
//           _status = 'Recording…';
//         });
//       }
//     } catch (e, st) {
//       _log('Recorder start FAILED: $e\n$st');
//       if (mounted) {
//         setState(() {
//           _recording = false;
//           _status = 'Recording failed';
//         });
//       }
//       Future.delayed(const Duration(seconds: 2), () {
//         if (!_isDisposed) _startRecordingCycle();
//       });
//       return;
//     }
//
//     // Auto-stop timer
//     _recordingTimer?.cancel();
//     _recordingTimer = Timer(const Duration(seconds: _maxRecordingSeconds), () {
//       if (_recording && !_isDisposed) {
//         _log('Auto-stop after $_maxRecordingSeconds s');
//         _stopAndSend();
//       }
//     });
//   }
//
//   Future<void> _stopAndSend() async {
//     if (!_recording || _isDisposed) {
//       _log('stopAndSend aborted: rec=$_recording disposed=$_isDisposed');
//       return;
//     }
//     _recordingTimer?.cancel();
//
//     if (mounted) {
//       setState(() {
//         _recording = false;
//         _sending = true;
//         _status = 'Stopping & sending…';
//       });
//     }
//
//     // Stop recorder
//     String? path;
//     try {
//       path = await _recorder.stop();
//       _log('Recorder stopped, path returned: $path');
//       if (path != null && path.isNotEmpty) {
//         _audioPath = path;
//       }
//     } catch (e, st) {
//       _log('Recorder stop FAILED: $e\n$st');
//       if (mounted) {
//         setState(() {
//           _sending = false;
//           _status = 'Stop failed';
//         });
//       }
//       Future.delayed(const Duration(seconds: 1), () {
//         if (!_isDisposed) _startRecordingCycle();
//       });
//       return;
//     }
//
//     // Verify file
//     final f = File(_audioPath);
//     try {
//       final exists = await f.exists();
//       final size = exists ? await f.length() : 0;
//       _log('Audio file exists: $exists size=$size bytes');
//       if (!exists || size == 0) {
//         throw Exception('Empty or missing audio file');
//       }
//     } catch (e) {
//       _log('Audio verify failed: $e');
//       if (mounted) {
//         setState(() {
//           _sending = false;
//           _status = 'No audio';
//         });
//       }
//       Future.delayed(const Duration(seconds: 1), () {
//         if (!_isDisposed) _startRecordingCycle();
//       });
//       return;
//     }
//
//     // Read PCM bytes (already headerless PCM16)
//     late Uint8List pcmBytes;
//     try {
//       pcmBytes = await f.readAsBytes();
//       _log('PCM bytes read: ${pcmBytes.length}');
//     } catch (e, st) {
//       _log('Read audio bytes FAILED: $e\n$st');
//       if (mounted) {
//         setState(() {
//           _sending = false;
//           _status = 'Read failed';
//         });
//       }
//       Future.delayed(const Duration(seconds: 1), () {
//         if (!_isDisposed) _startRecordingCycle();
//       });
//       return;
//     }
//
//     // Encode base64 for backend
//     final base64Audio = base64Encode(pcmBytes);
//     _sessionId ??= const Uuid().v4();
//     _log(
//         'Session ID: $_sessionId — sending ${base64Audio.length} base64 chars to backend');
//
//     // POST to backend
//     Map<String, dynamic> res;
//     try {
//       res = await VoiceApiService.processVoice(
//         audioBase64: base64Audio,
//         sessionId: _sessionId!,
//         timeout: const Duration(seconds: 120),
//       );
//
//       _log('Backend response: $res');
//
//       // Extract text (backend returns either json{text} or raw)
//       final text = (res['json'] != null && res['json']['text'] is String)
//           ? (res['json']['text'] as String)
//           : (res['raw'] is String ? res['raw'] as String : '');
//
//       if (mounted) {
//         setState(() {
//           _serverText = text;
//           _status = 'Ready';
//         });
//       }
//
//       if (text.isEmpty) {
//         _log('Backend returned empty text');
//       } else {
//         _log('Assistant text (${text.length} chars): ${text.length > 200 ? text.substring(0, 200) + '…' : text}');
//       }
//
//       // Speak out the response text (if any)
//       if (text.isNotEmpty) {
//         try {
//           await _tts.speak(text);
//         } catch (e) {
//           _log('TTS speak failed: $e');
//         }
//       }
//     } catch (e, st) {
//       _log('Voice process error: $e\n$st');
//       if (mounted) setState(() => _status = 'Error sending');
//       try {
//         await _tts.speak('Sorry, something went wrong sending audio');
//       } catch (_) {}
//     } finally {
//       if (mounted) {
//         setState(() {
//           _sending = false;
//           // _status already set above; keep as is
//         });
//       }
//
//       // Clean up file
//       try {
//         if (await f.exists()) {
//           await f.delete();
//           _log('Temporary file deleted: $_audioPath');
//         }
//       } catch (e) {
//         _log('Failed to delete temp file: $e');
//       }
//
//       // Restart the listening loop quickly
//       Future.delayed(const Duration(milliseconds: 500), () {
//         if (!_isDisposed) _startRecordingCycle();
//       });
//     }
//   }
//
//   // ====== UI ======
//   void _onTapMic() {
//     _log('Mic tapped: recording=$_recording sending=$_sending');
//     if (_recording) {
//       _stopAndSend();
//     } else if (!_sending) {
//       _startRecordingCycle();
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: AppColors.white,
//       appBar: AppBar(
//         backgroundColor: AppColors.white,
//         elevation: 0,
//         leading: BackButton(color: AppColors.black),
//         title: Text('Voice Assistant', style: AppText.heading2),
//       ),
//       body: Center(
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             RotationTransition(
//               turns: _spinController,
//               child: SizedBox(
//                 width: 100,
//                 height: 100,
//                 child: CustomPaint(painter: _GradientCirclePainter()),
//               ),
//             ),
//             const SizedBox(height: 20),
//             Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 16),
//               child: Text(
//                 _status,
//                 style: AppText.subtitle1,
//                 textAlign: TextAlign.center,
//               ),
//             ),
//             const SizedBox(height: 8),
//             if (_serverText.isNotEmpty)
//               Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 16),
//                 child: Text(
//                   _serverText,
//                   style: AppText.subtitle2,
//                   textAlign: TextAlign.center,
//                 ),
//               ),
//             const SizedBox(height: 24),
//             GestureDetector(
//               onTap: _onTapMic,
//               child: Container(
//                 width: 88,
//                 height: 88,
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   color: _recording ? Colors.red : AppColors.blue,
//                   boxShadow: const [
//                     BoxShadow(
//                       blurRadius: 16,
//                       offset: Offset(0, 8),
//                       color: Color(0x22000000),
//                     )
//                   ],
//                 ),
//                 child: Icon(
//                   _recording ? Icons.stop : Icons.mic,
//                   size: 44,
//                   color: AppColors.white,
//                 ),
//               ),
//             ),
//             const SizedBox(height: 12),
//             Text(
//               _recording ? 'Listening — tap to stop' : 'Tap mic to (re)start',
//               style: AppText.bodyText,
//             ),
//             if (_sending) ...[
//               const SizedBox(height: 16),
//               const CircularProgressIndicator(),
//             ],
//             const SizedBox(height: 12),
//           ],
//         ),
//       ),
//     );
//   }
// }
//
// class _GradientCirclePainter extends CustomPainter {
//   @override
//   void paint(Canvas canvas, Size size) {
//     final rect = Offset.zero & size;
//     final paint = Paint()
//       ..shader = SweepGradient(
//         colors: [AppColors.blue, AppColors.blue.withOpacity(0.3)],
//       ).createShader(rect)
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 8
//       ..strokeCap = StrokeCap.round;
//     canvas.drawCircle(rect.center, size.width / 2 - 4, paint);
//   }
//
//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
// }
