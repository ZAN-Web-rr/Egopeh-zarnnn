// lib/screens/home_page.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import '../constants/colors.dart';
import '../constants/text.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  // 1) Completed tasks
  Stream<int> get _completedTasks$ => FirebaseFirestore.instance
      .collection('users/$_uid/tasks')
      .where('completed', isEqualTo: true)
      .snapshots()
      .map((snap) => snap.size);

  // 2) Completed events
  Stream<int> get _completedEvents$ => FirebaseFirestore.instance
      .collection('users/$_uid/events')
      .where('completed', isEqualTo: true)
      .snapshots()
      .map((snap) => snap.size);

  // 3) Total focus sessions (each history entry = a completed focus)
  Stream<int> get _focusSessions$ => FirebaseFirestore.instance
      .collection('users/$_uid/focus_history')
      .snapshots()
      .map((snap) => snap.size);

  // 4) Sent emails: best-effort client-side filter of a common collection path
  Stream<int> get _sentEmails$ => FirebaseFirestore.instance
      .collection('users/$_uid/emails')
      .snapshots()
      .map((snap) {
    int count = 0;
    for (final d in snap.docs) {
      final raw = d.data();
      final Map<String, dynamic> data =
      raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

      bool isSent = false;
      if (data['sent'] == true) {
        isSent = true;
      } else {
        final direction = (data['direction'] as String?)?.toLowerCase();
        final type = (data['type'] as String?)?.toLowerCase();
        final status = (data['status'] as String?)?.toLowerCase();
        final folder = (data['folder'] as String?)?.toLowerCase();

        if (direction == 'outgoing' ||
            type == 'sent' ||
            status == 'sent' ||
            folder == 'sent') {
          isSent = true;
        }
      }

      if (isSent) count++;
    }
    return count;
  });

  // Helper: compute a canonical Timestamp-like value from doc data.
  // Preference order: 'date' -> 'dueDate' -> 'start' -> 'createdAt'
  // If string, attempt DateTime.parse; else fallback to server time (Timestamp.now()).
  Timestamp _canonicalTimestampFromMap(Map<String, dynamic> d) {
    dynamic raw;
    if (d.containsKey('date') && d['date'] != null) {
      raw = d['date'];
    } else if (d.containsKey('dueDate') && d['dueDate'] != null) {
      raw = d['dueDate'];
    } else if (d.containsKey('start') && d['start'] != null) {
      raw = d['start'];
    } else if (d.containsKey('createdAt') && d['createdAt'] != null) {
      raw = d['createdAt'];
    } else {
      raw = null;
    }

    if (raw is Timestamp) return raw;
    if (raw is DateTime) return Timestamp.fromDate(raw);

    if (raw is int) {
      try {
        return Timestamp.fromMillisecondsSinceEpoch(raw);
      } catch (_) {}
    }

    if (raw is String) {
      try {
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) return Timestamp.fromDate(parsed);
      } catch (_) {}
      try {
        final millis = int.parse(raw);
        return Timestamp.fromMillisecondsSinceEpoch(millis);
      } catch (_) {}
    }

    return Timestamp.now();
  }

  // 5) Combined Next Actions: tasks + events (both uncompleted)
  Stream<List<Map<String, dynamic>>> get _calendarItemsStream {
    final tasks$ = FirebaseFirestore.instance
        .collection('users/$_uid/tasks')
        .where('completed', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['id'] = d.id;
      data['type'] = 'task';
      final canonical = _canonicalTimestampFromMap(data);
      data['date'] = canonical;
      return data;
    }).toList());

    final events$ = FirebaseFirestore.instance
        .collection('users/$_uid/events')
        .where('completed', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['id'] = d.id;
      data['type'] = 'event';
      final canonical = _canonicalTimestampFromMap(data);
      data['date'] = canonical;
      return data;
    }).toList());

    return CombineLatestStream.list([tasks$, events$]).map((lists) {
      final tasks = lists[0] as List<Map<String, dynamic>>;
      final events = lists[1] as List<Map<String, dynamic>>;
      final combined = <Map<String, dynamic>>[];
      combined.addAll(tasks);
      combined.addAll(events);

      combined.sort((a, b) {
        final aDate = a['date'] as Timestamp? ?? Timestamp.now();
        final bDate = b['date'] as Timestamp? ?? Timestamp.now();
        return aDate.compareTo(bDate);
      });

      return combined;
    });
  }

  // 6) Generic markCompleted for both tasks & events
  final Set<String> _animatingCompleted = {};
  Future<void> _markCompleted(String docId, {required bool isEvent}) async {
    if (_animatingCompleted.contains(docId)) return;
    setState(() => _animatingCompleted.add(docId));
    await Future.delayed(const Duration(milliseconds: 400));
    final col = isEvent ? 'events' : 'tasks';
    await FirebaseFirestore.instance
        .collection('users/$_uid/$col')
        .doc(docId)
        .update({'completed': true});
    setState(() => _animatingCompleted.remove(docId));
  }

  Widget _buildEmptyCard() => Container(
    height: 150,
    width: double.infinity,
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.black.withOpacity(0.1)),
    ),
    child: Center(
      child: Text(
        'No new tasks or events',
        style:
        AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.6)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    String firstName = '';
    if (user != null) {
      if (user.displayName?.trim().isNotEmpty ?? false) {
        firstName = user.displayName!.split(' ').first;
      } else if (user.email != null) {
        firstName = user.email!.split('@').first;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: AppColors.white.withOpacity(0.8),
              elevation: 0,
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  Image.asset('assets/images/new.png', height: 32),
                  const SizedBox(width: 8),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.notifications_none,
                          color: AppColors.black),
                      onPressed: () =>
                          Navigator.pushNamed(context, '/notifications')),
                  IconButton(
                      icon: const Icon(Icons.settings, color: AppColors.black),
                      onPressed: () => Navigator.pushNamed(context, '/settings')),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Greeting + subtitle
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome${firstName.isNotEmpty ? ' $firstName' : ''}',
                      style: AppText.heading2.copyWith(
                          color: AppColors.black, fontSize: 20),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Let's get productive!",
                      style: AppText.bodyText
                          .copyWith(color: AppColors.black.withOpacity(0.7)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: user?.photoURL != null
                    ? NetworkImage(user!.photoURL!)
                    : null,
                child: user?.photoURL == null
                    ? Icon(
                  Icons.person,
                  size: 28,
                  color: AppColors.black.withOpacity(0.6),
                )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // GRID: Tasks / Focus / Events / Email
          StreamBuilder<List<int>>(
            stream: Rx.combineLatest4(
                _completedTasks$, _focusSessions$, _completedEvents$, _sentEmails$,
                    (t, f, e, s) => [t, f, e, s]),
            builder: (ctx, snap) {
              // defensive extraction in case the stream yields a shorter list
              final vals = snap.data ?? [0, 0, 0, 0];
              final completedTasks = vals.length > 0 ? vals[0] as int : 0;
              final totalFocus = vals.length > 1 ? vals[1] as int : 0;
              final completedEvents = vals.length > 2 ? vals[2] as int : 0;
              final sentEmails = vals.length > 3 ? vals[3] as int : 0;

              final cards = [
                {
                  'title': 'Tasks',
                  'icon': Icons.check_box,
                  'value': completedTasks,
                  'suffix': 'Completed',
                  'bg': AppColors.blue.withOpacity(0.4),
                },
                {
                  'title': 'Focus',
                  'icon': Icons.timer,
                  'value': totalFocus,
                  'suffix': 'Sessions',
                  'bg': AppColors.white,
                },
                {
                  'title': 'Events',
                  'icon': Icons.event,
                  'value': completedEvents,
                  'suffix': 'Completed',
                  'bg': AppColors.white,
                },
                {
                  'title': 'Email',
                  'icon': Icons.email,
                  'value': sentEmails,
                  'suffix': 'Sent',
                  'bg': AppColors.blue.withOpacity(0.4),
                },
              ];

              return GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1,
                children: cards.map((item) {
                  return Container(
                    decoration: BoxDecoration(
                      color: item['bg'] as Color,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.black.withOpacity(0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(item['title'] as String,
                                  style: AppText.subtitle1.copyWith(
                                      color: AppColors.black))),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                                color: AppColors.white, shape: BoxShape.circle),
                            child: Icon(item['icon'] as IconData,
                                size: 20, color: AppColors.black),
                          )
                        ]),
                        const Spacer(),
                        Text(
                          (item['value'] as int).toString(),
                          style: AppText.heading2.copyWith(
                              color: AppColors.black, fontSize: 24),
                        ),
                        const SizedBox(height: 4),
                        Text(item['suffix'] as String,
                            style: AppText.bodyText.copyWith(
                                color: AppColors.black.withOpacity(0.7))),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 32),

          // Overview (tasks+events completed, focus sessions)
          StreamBuilder<List<int>>(
            stream: Rx.combineLatest3(
                _completedTasks$, _completedEvents$, _focusSessions$,
                    (t, e, f) => [t + e, f, 0]),
            builder: (ctx, snap) {
              final ov = snap.data ?? [0, 0, 0];
              return _buildOverview(ov[0], ov[1]);
            },
          ),

          // --- NEW: Note-taking session button (matches app design) ---
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/voice-to-text'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue.withOpacity(0.6),
                shadowColor: Colors.transparent,
                padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Icon(Icons.mic, color: Colors.black),
                  const SizedBox(width: 10),
                  Text(
                    'Start Note Session',
                    style: AppText.bodyText.copyWith(
                        color: Colors.black, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Next Actions heading + “+”
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Next Actions',
                  style:
                  AppText.heading2.copyWith(color: AppColors.black, fontSize: 18)),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/task'),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, gradient: AppColors.splashGradient),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Combined next actions list
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _calendarItemsStream,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator());
              final items = snap.data ?? [];
              if (items.isEmpty) return _buildEmptyCard();
              return Column(
                children: items.map((item) {
                  final title = item['title'] ?? '';
                  final details = item['details'] ?? item['notes'] ?? '';
                  final location = item['location'] ?? '';
                  final color = Color(int.parse(
                      (item['color'] ?? '#FF42A5F5').replaceFirst('#', '0x')));
                  final isTask = item['type'] == 'task';
                  final isAnimating = _animatingCompleted.contains(item['id']);

                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isAnimating ? 0.2 : 1,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: AppText.bodyText.copyWith(
                                      fontWeight: FontWeight.bold)),
                              if (details.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(details,
                                      style: AppText.bodyText.copyWith(
                                          fontSize: 13)),
                                ),
                              if (location.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('📍 $location',
                                      style: AppText.bodyText.copyWith(
                                          fontSize: 13,
                                          color: Colors.black87)),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.check_circle,
                            color: isAnimating ? color : Colors.white,
                          ),
                          onPressed: () => _markCompleted(item['id'],
                              isEvent: !isTask /* event if not task */),
                        ),
                      ]),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildOverview(int completedAll, int sessions) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.black.withOpacity(0.1)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Overview',
            style: AppText.heading2.copyWith(color: AppColors.black, fontSize: 18)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _overviewItem('Completed', completedAll)),
          const SizedBox(width: 16),
          Expanded(child: _overviewItem('Focus Sessions', sessions)),
        ]),
      ]),
    );
  }

  Widget _overviewItem(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: AppColors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 4))
          ]),
      child: Row(children: [
        Expanded(child: Text(label, style: AppText.bodyText.copyWith(color: AppColors.black))),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: AppColors.blue.withOpacity(0.6)),
          child: Center(
              child: Text('$count',
                  style:
                  AppText.bodyText.copyWith(color: AppColors.black, fontSize: 10))),
        ),
      ]),
    );
  }
}
