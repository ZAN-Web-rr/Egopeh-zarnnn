import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../constants/colors.dart';
import '../constants/text.dart';

enum NoteState { recording, review, saved }

class NoteTakingScreen extends StatefulWidget {
  const NoteTakingScreen({Key? key}) : super(key: key);
  @override
  _NoteTakingScreenState createState() => _NoteTakingScreenState();
}

class _NoteTakingScreenState extends State<NoteTakingScreen> {
  late stt.SpeechToText _speech;
  bool _speechAvailable = false;
  NoteState _state = NoteState.recording;
  String _transcript = '';
  bool _isListening = false;
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done') _stopRecording();
      },
      onError: (_) => _stopRecording(),
    );
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speech recognition unavailable', style: AppText.bodyText)),
      );
    }
  }

  Future<List<File>> _fetchNoteFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf') || f.path.endsWith('.doc') || f.path.endsWith('.txt'))
        .toList();
  }

  void _openFile(File file) => OpenFile.open(file.path);

  void _startRecording() {
    if (!_speechAvailable) return;
    setState(() {
      _state = NoteState.recording;
      _transcript = '';
      _seconds = 0;
      _isListening = true;
    });
    _speech.listen(
      onResult: (res) => setState(() { _transcript = res.recognizedWords; }),
      listenFor: const Duration(minutes: 5),
      partialResults: true,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
    });
  }

  Future<void> _stopRecording() async {
    await _speech.stop();
    _timer?.cancel();
    setState(() {
      _isListening = false;
      _state = NoteState.review;
    });
  }

  Future<void> _saveAsPdf() async {
    final pdf = pw.Document()..addPage(pw.Page(build: (_) => pw.Text(_transcript)));
    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/notes_${DateTime.now().millisecondsSinceEpoch}.pdf')
      ..writeAsBytesSync(bytes);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF saved at ${file.path}', style: AppText.bodyText)),
    );
    setState(() => _state = NoteState.saved);
  }

  Future<void> _saveAsDoc() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/notes_${DateTime.now().millisecondsSinceEpoch}.doc')
      ..writeAsStringSync(_transcript);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('DOC saved at ${file.path}', style: AppText.bodyText)),
    );
    setState(() => _state = NoteState.saved);
  }

  void _showNotesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        builder: (_, controller) {
          return FutureBuilder<List<File>>(
            future: _fetchNoteFiles(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final files = snapshot.data!;
              if (files.isEmpty) {
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.note, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text('No notes yet', style: AppText.subtitle1),
                        const SizedBox(height: 8),
                        Text('Tap the record button to create your first note.',
                            style: AppText.bodyText, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                );
              }
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: ListView.builder(
                  controller: controller,
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    final name = file.path.split('/').last;
                    return ListTile(
                      title: Text(name, style: AppText.bodyText),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.share, color: AppColors.blue),
                            onPressed: () async {
                              await Share.shareXFiles([
                                XFile(file.path)
                              ], text: 'Sharing note $name');
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('Delete Note', style: AppText.heading2),
                                  content: Text('Are you sure you want to delete "$name"?', style: AppText.bodyText),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(false),
                                      child: Text('Cancel', style: AppText.bodyText),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(true),
                                      child: Text('Delete', style: AppText.bodyText.copyWith(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await file.delete();
                                setState(() {});
                                Navigator.of(context).pop();
                                _showNotesSheet();
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () => _openFile(file),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    switch (_state) {
      case NoteState.recording:
        content = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_formatTime(_seconds), style: AppText.heading2.copyWith(fontSize: 48)),
              const SizedBox(height: 24),
              Icon(Icons.mic, size: 80, color: _isListening ? Colors.red : Colors.grey),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isListening ? _stopRecording : _startRecording,
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(24),
                  backgroundColor: _isListening ? Colors.red : AppColors.blue,
                  elevation: 6,
                ),
                child: Icon(
                  _isListening ? Icons.stop : Icons.fiber_manual_record,
                  size: 36,
                  color: AppColors.white,
                ),
              ),
            ],
          ),
        );
        break;
      case NoteState.review:
        content = Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(_transcript, style: AppText.bodyText),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton.extended(
                  onPressed: _saveAsDoc,
                  icon: const Icon(Icons.description),
                  label: const Text('Save DOC'),
                  backgroundColor: AppColors.blue,
                ),
                FloatingActionButton.extended(
                  onPressed: _saveAsPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Save PDF'),
                  backgroundColor: AppColors.blue,
                ),
              ],
            ),
          ],
        );
        break;
      case NoteState.saved:
        content = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/sucess.png', width: 120, height: 120),
              const SizedBox(height: 24),
              Text('Note Saved!', style: AppText.heading2),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => setState(() => _state = NoteState.recording),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.white),
                child: const Text('New Note'),
              ),
            ],
          ),
        );
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Take Notes'),

        actions: [
          TextButton(
            onPressed: _showNotesSheet,
            child: Text('Notes', style: AppText.bodyText.copyWith(color: AppColors.blue)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: content,
      ),
    );
  }

  String _formatTime(int seconds) {
    final min = (seconds ~/ 60).toString().padLeft(2, '0');
    final sec = (seconds % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }
}

/*
Ensure pubspec.yaml includes:

dependencies:
  open_file: ^3.2.1
  speech_to_text: ^5.4.0
  pdf: ^3.10.0
  path_provider: ^2.0.15
  share_plus: ^6.3.0
*/
