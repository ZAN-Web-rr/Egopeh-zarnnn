import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../constants/colors.dart';
import '../constants/text.dart';

class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({Key? key}) : super(key: key);

  @override
  _CreateTaskScreenState createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> with SingleTickerProviderStateMixin {
  final _titleController   = TextEditingController();
  final _detailsController = TextEditingController();
  bool _allDay   = false;
  bool _repeat   = false;
  DateTime _selectedDate = DateTime.now();
  Color _selectedColor   = AppColors.blue;
  late stt.SpeechToText _speech;
  bool _listening = false;

  final List<Color> _colors = [
    AppColors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.red,
  ];

  @override
  void initState() {
    super.initState();
    if (FirebaseAuth.instance.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/login');
      });
    }
    _speech = stt.SpeechToText();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _startListening() async {
    if (!_listening) {
      final available = await _speech.initialize();
      if (!available) return;
      setState(() => _listening = true);
      _speech.listen(onResult: (r) {
        if (r.finalResult) {
          _detailsController.text = r.recognizedWords;
          setState(() => _listening = false);
          _speech.stop();
        }
      });
    } else {
      setState(() => _listening = false);
      _speech.stop();
    }
  }

  Future<void> _saveTask() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .add({
      'title': _titleController.text.trim(),
      'details': _detailsController.text.trim(),
      'date': Timestamp.fromDate(_selectedDate),
      'allDay': _allDay,
      'repeat': _repeat,
      'color': '#${_selectedColor.value.toRadixString(16).padLeft(8, '0')}',
      'completed': false, // ✅ Needed to show up in the Next Actions list
      'createdAt': FieldValue.serverTimestamp(),
    });
    // after adding the task…
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .add({
      'title': 'New Task created',
      'body': '${_titleController.text.trim()} on ${DateFormat.yMMMd().format(_selectedDate)}',
      'date': FieldValue.serverTimestamp(),
      'unread': true,
    });



    // Show confirmation modal
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: AppColors.blue),
            const SizedBox(height: 16),
            Text('Task created',
                style: AppText.heading2.copyWith(color: AppColors.black)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back to previous screen
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top bar
                    Row(
                      children: [
                        Image.asset('assets/images/new.png', height: 32),
                        const SizedBox(width: 8),

                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: const Icon(Icons.arrow_back, size: 28),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Title
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0,4))],
                      ),
                      child: TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          hintText: 'Add Title', border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Toggles
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('All Day', style: AppText.bodyText.copyWith(color: AppColors.black)),
                        Switch(
                          value: _allDay,
                          onChanged: (v) => setState(() => _allDay = v),
                          activeColor: AppColors.blue,
                          inactiveTrackColor: AppColors.black.withOpacity(0.1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Repeat', style: AppText.bodyText.copyWith(color: AppColors.black)),
                        Switch(
                          value: _repeat,
                          onChanged: (v) => setState(() => _repeat = v),
                          activeColor: AppColors.blue,
                          inactiveTrackColor: AppColors.black.withOpacity(0.1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Date picker
                    GestureDetector(
                      onTap: _pickDate,
                      child: Row(
                        children: [
                          Text('Date', style: AppText.bodyText.copyWith(color: AppColors.black)),
                          const Spacer(),
                          Text(DateFormat('d MMM yyyy').format(_selectedDate),
                              style: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.1))),
                          const SizedBox(width: 8),
                          const Icon(Icons.calendar_today, size: 20, color: Colors.black12),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Color picker
                    Text('Theme', style: AppText.bodyText.copyWith(color: AppColors.black)),
                    const SizedBox(height: 12),
                    Row(
                      children: _colors.map((c) {
                        final sel = c == _selectedColor;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedColor = c),
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: c, shape: BoxShape.circle,
                              border: sel ? Border.all(color: AppColors.black, width: 2) : null,
                            ),
                            child: sel ? const Icon(Icons.check, size: 20, color: Colors.white) : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Details header
                    Row(
                      children: [
                        Expanded(child: Text('Add Details', style: AppText.bodyText.copyWith(fontWeight: FontWeight.bold))),
                        IconButton(
                          icon: const Icon(Icons.mic, color: AppColors.blue),
                          onPressed: _startListening,
                        ),
                      ],
                    ),

                    // Details field
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0,4))],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          controller: _detailsController,
                          maxLines: null,
                          expands: true,
                          decoration: const InputDecoration(
                            hintText: 'Type here', border: InputBorder.none, contentPadding: EdgeInsets.all(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save button
                    Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(colors: [Color(0xFF6EC1E4), Color(0xFF007ACC)]),
                      ),
                      child: TextButton(
                        onPressed: _saveTask,
                        child: Text('Save', style: AppText.bodyText.copyWith(color: AppColors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
