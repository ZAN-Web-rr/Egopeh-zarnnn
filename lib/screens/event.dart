import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants/colors.dart';
import '../constants/text.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({Key? key}) : super(key: key);

  @override
  _CreateEventScreenState createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _titleController        = TextEditingController();
  final _detailsController      = TextEditingController();
  final _peopleController       = TextEditingController();
  final _notifNumberController  = TextEditingController();
  final _locationController     = TextEditingController();

  bool _allDay   = false;
  bool _repeat   = false;
  DateTime _selectedDate = DateTime.now();
  Color _selectedColor   = AppColors.blue;

  final List<Color> _colors = [
    AppColors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.red,
  ];

  // notification settings
  String   _notifyBefore = 'day';
  TimeOfDay _notifTime   = TimeOfDay.now();
  String   _notifChannel = 'Notification';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _notifTime);
    if (t != null) setState(() => _notifTime = t);
  }

  void _showPeopleOverlay() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Add People', style: AppText.heading2),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
              ),
              child: TextField(
                controller: _peopleController,
                decoration: const InputDecoration(
                  hintText: 'Enter name or email',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Suggestions',
                  style: AppText.bodyText.copyWith(fontSize: 12, color: AppColors.black.withOpacity(0.6))),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: Center(
                child: Text('No suggestions',
                    style: AppText.bodyText.copyWith(fontSize: 12, color: AppColors.black.withOpacity(0.4))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showNotificationOverlay() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Add Notification', style: AppText.heading2),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                ),
                child: TextField(
                  controller: _notifNumberController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Number',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              RadioListTile<String>(
                title: const Text('A day before'),
                value: 'day',
                groupValue: _notifyBefore,
                onChanged: (v) => setModalState(() => _notifyBefore = v!),
              ),
              RadioListTile<String>(
                title: const Text('A week before'),
                value: 'week',
                groupValue: _notifyBefore,
                onChanged: (v) => setModalState(() => _notifyBefore = v!),
              ),
              ListTile(
                title: const Text('Notification Time'),
                trailing: Text(_notifTime.format(context)),
                onTap: () => _pickTime().then((_) => setModalState(() {})),
              ),
              RadioListTile<String>(
                title: const Text('Notification'),
                value: 'Notification',
                groupValue: _notifChannel,
                onChanged: (v) => setModalState(() => _notifChannel = v!),
              ),
              RadioListTile<String>(
                title: const Text('Email'),
                value: 'Email',
                groupValue: _notifChannel,
                onChanged: (v) => setModalState(() => _notifChannel = v!),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Top bar
            Row(children: [
              Image.asset('assets/images/new.png', height: 32),
              const SizedBox(width: 8),

              const Spacer(),
            ]),
            const SizedBox(height: 24),
            Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.arrow_back, size: 28)),
            ]),
            const SizedBox(height: 24),

            // Title
            _buildCardTextField(controller: _titleController, hint: 'Add Title'),

            const SizedBox(height: 24),
            // Toggles
            _buildSwitchRow('All Day', _allDay, (v) => setState(() => _allDay = v)),
            const SizedBox(height: 16),
            _buildSwitchRow('Repeat', _repeat, (v) => setState(() => _repeat = v)),
            const SizedBox(height: 24),

            // Date picker
            GestureDetector(
              onTap: _pickDate,
              child: Row(children: [
                Text('Date', style: AppText.bodyText.copyWith(color: AppColors.black)),
                const Spacer(),
                Text(DateFormat('d MMM yyyy').format(_selectedDate),
                    style: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.1))),
                const SizedBox(width: 8),
                const Icon(Icons.calendar_today, size: 20, color: Colors.black12),
              ]),
            ),
            const SizedBox(height: 16),

            // People & Notifications
            ListTile(
              title: Text('Add People', style: AppText.bodyText),
              trailing: const Icon(Icons.person_add, color: Colors.black12),
              onTap: _showPeopleOverlay,
            ),
            ListTile(
              title: Text('Add Notification', style: AppText.bodyText),
              trailing: const Icon(Icons.notifications, color: Colors.black12),
              onTap: _showNotificationOverlay,
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
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: sel ? Border.all(color: AppColors.black, width: 2) : null,
                    ),
                    child: sel ? const Icon(Icons.check, color: Colors.white) : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Location
            Text('Location', style: AppText.bodyText.copyWith(color: AppColors.black)),
            const SizedBox(height: 8),
            _buildCardTextField(controller: _locationController, hint: 'Enter location'),
            const SizedBox(height: 24),

            // Details & mic
            Row(children: [
              Expanded(child: Text('Add Details', style: AppText.bodyText.copyWith(fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.mic, color: AppColors.blue), onPressed: () {}),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: _buildCardTextField(controller: _detailsController, hint: 'Type here', expands: true),
            ),
            const SizedBox(height: 24),

            // Save
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(colors: [Color(0xFF6EC1E4), Color(0xFF007ACC)]),
              ),
              child: TextButton(
                onPressed: () async {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;
                  try {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .collection('events')
                        .add({
                      'title': _titleController.text.trim(),
                      'details': _detailsController.text.trim(),
                      'people': _peopleController.text.trim(),
                      'notifNumber': _notifNumberController.text.trim(),
                      'notifyBefore': _notifyBefore,
                      'notifTime': _notifTime.format(context),
                      'notifChannel': _notifChannel,
                      'date': Timestamp.fromDate(_selectedDate),
                      'allDay': _allDay,
                      'repeat': _repeat,
                      'location': _locationController.text.trim(),  // ← here
                      'completed': false, // so it shows in Next Actions
                      'color': '#${_selectedColor.value.toRadixString(16).padLeft(8, '0')}',
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


                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Event saved successfully")),
                    );
                    Navigator.pop(context);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error saving event: $e")),
                    );
                  }
                },
                child: Text('Save', style: AppText.bodyText.copyWith(color: AppColors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildCardTextField({
    required TextEditingController controller,
    required String hint,
    bool expands = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      ),
      child: TextField(
        controller: controller,
        expands: expands,
        maxLines: expands ? null : 1,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          contentPadding:
          expands ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildSwitchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.bodyText.copyWith(color: AppColors.black)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.blue,
          inactiveTrackColor: AppColors.black.withOpacity(0.1),
        ),
      ],
    );
  }
}
