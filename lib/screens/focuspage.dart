import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/colors.dart';
import '../constants/text.dart';

enum FocusState { setup, enteringTitle, running, breakModal, finishModal }

class FocusPage extends StatefulWidget {
  const FocusPage({Key? key}) : super(key: key);

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  FocusState _state = FocusState.setup;

  // User settings
  String _selectedDuration = '1 min';
  String _breakAfter = '30 sec';
  bool _autoBreak = false;
  bool _notificationSound = false;
  bool _doNotDisturb = false;
  final List<String> _breakOptions = ['30 sec', '1 min', '5 min'];
  final TextEditingController _titleController = TextEditingController();

  // Runtime
  late Stopwatch _stopwatch;
  late Timer _ticker;
  double _progress = 0;

  // Auto break control
  int _breakSecondsLeft = 0;
  bool _breakTaken = false;
  bool _inAutoBreak = false;
  int _totalSeconds = 60;

  // Firestore & Auth
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  String get _userId => _auth.currentUser?.uid ?? 'anonymous';

  // History list (loaded from Firestore)
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch();
    _totalSeconds = _toSeconds(_selectedDuration);
    _loadHistory();
  }

  @override
  void dispose() {
    if (_ticker.isActive) _ticker.cancel();
    _stopwatch.stop();
    _titleController.dispose();
    super.dispose();
  }

  // Load history from Firestore for this user
  Future<void> _loadHistory() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('focus_history')
          .orderBy('completedAt', descending: true)
          .get();

      setState(() {
        _history = snapshot.docs
            .map((doc) => doc.data() as Map<String, dynamic>)
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading history: $e');
    }
  }

  // Save a completed timer session to Firestore
  Future<void> _saveHistoryEntry() async {
    if (_titleController.text.trim().isEmpty) return;
    try {
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('focus_history')
          .add({
        'title': _titleController.text.trim(),
        'duration': _selectedDuration,
        'breakAfter': _breakAfter,
        'autoBreak': _autoBreak,
        'completedAt': Timestamp.now(),
      });
      await _loadHistory(); // Refresh history list locally
    } catch (e) {
      debugPrint('Error saving history: $e');
    }
    await _firestore
        .collection('users')
        .doc(_userId)
        .collection('notifications')
        .add({
      'title': 'Focus session completed',
      'body': '${_titleController.text.trim()} (${_selectedDuration})',
      'date': FieldValue.serverTimestamp(),
      'unread': true,
    });

  }


  int _toSeconds(String label) {
    if (label.contains('min')) return int.parse(label.split(' ')[0]) * 60;
    return int.parse(label.split(' ')[0]);
  }

  void _showTitleOverlay() => setState(() => _state = FocusState.enteringTitle);

  void _startRunning() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a focus title before starting')),
      );
      return;
    }

    setState(() {
      _state = FocusState.running;
      _inAutoBreak = false;
      _breakTaken = false;                      // reset the flag
      _totalSeconds = _toSeconds(_selectedDuration);
      _progress = 0;
    });

    final workThreshold  = _toSeconds(_selectedDuration);
    final breakThreshold = _toSeconds(_breakAfter);

    _stopwatch
      ..reset()
      ..start();

    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      final elapsed = _stopwatch.elapsed.inSeconds;

      // 1) fire auto-break once at the break threshold
      if (_autoBreak && !_inAutoBreak && !_breakTaken && elapsed >= breakThreshold) {
        _breakTaken = true;
        _pauseForAutoBreak(t);
        return;
      }

      // 2) finish when workThreshold reached
      if (elapsed >= workThreshold) {
        t.cancel();
        _stopwatch.stop();
        setState(() => _state = FocusState.finishModal);
        _saveHistoryEntry();
        return;
      }

      // 3) otherwise update progress
      setState(() => _progress = elapsed / workThreshold);
    });
  }


  void _pauseForAutoBreak(Timer t) {
    t.cancel();
    _stopwatch.stop();
    setState(() {
      _inAutoBreak = true;        // if you check this elsewhere
      _state       = FocusState.breakModal;
    });
  }



  void _resumeAfterBreak(Timer t) {
    _inAutoBreak = false;

    // if, by the end of the break, we've already hit (or passed) our work duration,
    // go straight to finishModal instead of resuming.
    if (_stopwatch.elapsed.inSeconds >= _totalSeconds) {
      _stopwatch.stop();
      t.cancel();
      setState(() => _state = FocusState.finishModal);
      _saveHistoryEntry();
    } else {
      _stopwatch.start();
      setState(() => _state = FocusState.running);
    }
  }


  void _pause() {
    if (_ticker.isActive) _ticker.cancel();
    _stopwatch.stop();
    setState(() => _state = FocusState.breakModal);
  }

  void _resumeRunning() {
    if (_ticker.isActive) _ticker.cancel();
    _stopwatch.start();
    setState(() => _state = FocusState.running);

    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      final elapsed = _stopwatch.elapsed.inSeconds;
      if (elapsed >= _totalSeconds) {
        _stopwatch.stop();
        t.cancel();
        setState(() => _state = FocusState.finishModal);
        _saveHistoryEntry();
      } else {
        setState(() => _progress = elapsed / _totalSeconds);
      }
    });
  }

  void _reset() {
    if (_ticker.isActive) _ticker.cancel();
    _stopwatch.reset();
    _stopwatch.stop();
    _progress = 0;
    _titleController.clear();
    _breakTaken = false;
    setState(() => _state = FocusState.setup);
  }

  void _showCustomDurationDialog() {
    final TextEditingController _customController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Custom Duration'),
          content: TextField(
            controller: _customController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Enter duration in minutes',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final input = _customController.text;
                final minutes = int.tryParse(input);
                if (minutes != null && minutes > 0) {
                  setState(() {
                    _selectedDuration = '$minutes min';
                    _totalSeconds = minutes * 60;
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Set'),
            ),
          ],
        );
      },
    );
  }

  // Draggable history bottom sheet
  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        if (_history.isEmpty) {
          return SizedBox(
            height: 300,
            child: Center(
              child: Text('No completed timers yet.',
                  style: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.5))),
            ),
          );
        }
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = _history[index];
                final date = (item['completedAt'] as Timestamp).toDate();
                final formattedDate =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
                    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                return ListTile(
                  title: Text(item['title'] ?? 'Untitled', style: AppText.heading1),
                  subtitle: Text(
                      'Duration: ${item['duration'] ?? '?'}\nCompleted: $formattedDate'),
                  isThreeLine: true,
                  trailing: item['autoBreak'] == true
                      ? const Icon(Icons.timer, color: AppColors.blue)
                      : null,
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: _buildAppBar(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // MAIN CONTENT + History Button
          Positioned.fill(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showHistorySheet,
                    child: Text('History',
                        style: AppText.bodyText.copyWith(color: AppColors.blue)),
                  ),
                ),
                Expanded(child: _buildMainContent()),
              ],
            ),
          ),

          // Overlays
          if (_state == FocusState.enteringTitle) _buildTitleOverlay(),
          if (_state == FocusState.breakModal) _buildBreakOverlay(),
          if (_state == FocusState.finishModal) _buildFinishOverlay(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Image.asset('assets/images/new.png', height: 32),
          const SizedBox(width: 8),

          const Spacer(),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: AppColors.black),
            onPressed: () => Navigator.pushNamed(context, '/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: AppColors.black),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return _state == FocusState.setup ? _buildSetup() : _runningView();
  }

  Widget _buildSetup() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTimerDisplay('00:00'),
          const SizedBox(height: 24),
          _buildPlayResetRow(),
          const SizedBox(height: 24),
          _buildDurationSelector(),
          const SizedBox(height: 24),
          _buildBreakSelector(),
          const SizedBox(height: 24),
          _buildSwitch('Auto Break', _autoBreak, (v) => setState(() => _autoBreak = v)),
          _buildSwitch('Notification Sound', _notificationSound,
                  (v) => setState(() => _notificationSound = v)),
          _buildSwitch(
              'Do Not Disturb', _doNotDisturb, (v) => setState(() => _doNotDisturb = v)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _runningView() {
    final elapsed = _stopwatch.elapsed.inSeconds;
    final minutes = (elapsed ~/ 60).toString().padLeft(2, '0');
    final seconds = (elapsed % 60).toString().padLeft(2, '0');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Title & Settings Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: AppColors.black.withOpacity(0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_titleController.text, style: AppText.heading2),
                const SizedBox(height: 8),
                Text('Duration: $_selectedDuration', style: AppText.bodyText),
                const SizedBox(height: 4),
                Text('Break after: $_breakAfter', style: AppText.bodyText),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildTimerDisplay('$minutes:$seconds'),
          const SizedBox(height: 24),
          _buildPauseResetRow(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildTimerDisplay(String label) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 180,
            height: 180,
            child: CircularProgressIndicator(
              value: _progress,
              strokeWidth: 10,
              backgroundColor: AppColors.black.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(AppColors.blue),
            ),
          ),
          Text(label,
              style: AppText.heading2.copyWith(color: AppColors.black, fontSize: 32)),
        ],
      ),
    );
  }

  Widget _buildPlayResetRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _showTitleOverlay,
          child: Container(
            width: 56,
            height: 56,
            decoration:
            BoxDecoration(shape: BoxShape.circle, gradient: AppColors.splashGradient),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(width: 32),
        GestureDetector(
          onTap: _reset,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.blue),
            child: const Icon(Icons.refresh, color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }

  Widget _buildPauseResetRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _pause,
          child: Container(
            width: 56,
            height: 56,
            decoration:
            BoxDecoration(shape: BoxShape.circle, gradient: AppColors.splashGradient),
            child: const Icon(Icons.pause, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(width: 32),
        GestureDetector(
          onTap: _reset,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.blue),
            child: const Icon(Icons.refresh, color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }

  Widget _buildDurationSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Timer Duration', style: AppText.subtitle1.copyWith(color: AppColors.black)),
        const SizedBox(height: 8),
        Row(
          children: ['1 min', '5 mins', 'Custom'].map((label) {
            final isActive = _selectedDuration == label;
            return Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: GestureDetector(
                onTap: () {
                  if (label == 'Custom') {
                    _showCustomDurationDialog();
                  } else {
                    setState(() {
                      _selectedDuration = label;
                      _totalSeconds = _toSeconds(label);
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: isActive ? AppColors.splashGradient : null,
                    color: isActive ? null : AppColors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: isActive
                        ? null
                        : Border.all(color: AppColors.black.withOpacity(0.3)),
                  ),
                  child: Text(label,
                      style: AppText.bodyText.copyWith(
                          color: isActive ? AppColors.white : AppColors.black)),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBreakSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Break Duration', style: AppText.subtitle1.copyWith(color: AppColors.black)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.black.withOpacity(0.3)),
          ),
          child: DropdownButton<String>(
            dropdownColor: AppColors.white,
            value: _breakAfter,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            onChanged: (String? value) {
              if (value != null) {
                setState(() => _breakAfter = value);
              }
            },
            items: _breakOptions
                .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitch(String label, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: AppText.bodyText.copyWith(color: AppColors.black)),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            // these two control the “off” colors:
            inactiveTrackColor: Colors.black.withOpacity(0.4),
            inactiveThumbColor: Colors.white.withOpacity(0.4),
            // you can still customize the “on” colors if you like:
            activeColor: AppColors.blue,
            activeTrackColor: AppColors.blue.withOpacity(0.5),
          ),
        ],
      ),
    );
  }


  // Overlay to enter title before starting timer
  Widget _buildTitleOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter Focus Title', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Focus title',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _state = FocusState.setup),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        if (_titleController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Title cannot be empty')),
                          );
                          return;
                        }
                        _startRunning();
                      },
                      child: const Text('Start'),
                    )
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Break overlay
  Widget _buildBreakOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Take a Break!', style: AppText.heading2),
                const SizedBox(height: 12),
                Text(
                  'You’ve hit your break point. Ready to get back to work?',
                  textAlign: TextAlign.center,
                  style: AppText.bodyText,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    // Resume the timer loop
                    _resumeRunning();
                  },
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  // Finish overlay
  Widget _buildFinishOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Well done!', style: AppText.heading2),
                const SizedBox(height: 12),
                Text(
                    'You focused for $_selectedDuration with a break of $_breakAfter.',
                    textAlign: TextAlign.center,
                    style: AppText.bodyText),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _reset,
                  child: const Text('Done'),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
