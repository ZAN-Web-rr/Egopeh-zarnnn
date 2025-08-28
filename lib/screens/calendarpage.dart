// lib/screens/calendar.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';
import '../constants/colors.dart';
import '../constants/text.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({Key? key}) : super(key: key);

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarFormat _format = CalendarFormat.week;
  DateTime _focusedDay = DateTime.now();
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  final Set<String> _animatingCompleted = {};

  // Default fallback color hex (same as used elsewhere)
  static const String _defaultColorHex = '#FF42A5F5';

  /// Compute a canonical Timestamp from a document map.
  /// Preference order: 'date' -> 'dueDate' -> 'start' -> 'createdAt'
  /// Accepts Timestamp, DateTime, int (ms since epoch), or ISO-like strings.
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

    // Timestamp
    if (raw is Timestamp) return raw;

    // DateTime
    if (raw is DateTime) return Timestamp.fromDate(raw);

    // integer milliseconds
    if (raw is int) {
      try {
        return Timestamp.fromMillisecondsSinceEpoch(raw);
      } catch (_) {}
    }

    // numeric string (milliseconds)
    if (raw is String) {
      // try ISO parse first
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return Timestamp.fromDate(parsed);

      // try numeric millis
      try {
        final millis = int.parse(raw);
        return Timestamp.fromMillisecondsSinceEpoch(millis);
      } catch (_) {}
    }

    // Last resort: now
    return Timestamp.now();
  }

  /// Combine tasks + events into a single list, computing canonical dates locally.
  Stream<List<Map<String, dynamic>>> get _itemsStream {
    final tasks$ = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('tasks')
        .where('completed', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['id'] = d.id;
      data['type'] = 'task';
      // compute canonical date and inject as 'date' (Timestamp)
      try {
        data['date'] = _canonicalTimestampFromMap(data);
      } catch (_) {
        data['date'] = Timestamp.now();
      }
      // ensure color fallback
      data['color'] = (data['color'] as String?) ?? _defaultColorHex;
      return data;
    }).toList());

    final events$ = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('events')
        .where('completed', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['id'] = d.id;
      data['type'] = 'event';
      try {
        data['date'] = _canonicalTimestampFromMap(data);
      } catch (_) {
        data['date'] = Timestamp.now();
      }
      data['color'] = (data['color'] as String?) ?? _defaultColorHex;
      return data;
    }).toList());

    return CombineLatestStream.list([tasks$, events$]).map((lists) {
      final tasks = lists[0] as List<Map<String, dynamic>>;
      final events = lists[1] as List<Map<String, dynamic>>;
      final all = <Map<String, dynamic>>[...tasks, ...events];
      all.sort((a, b) {
        final aTs = a['date'] as Timestamp? ?? Timestamp.now();
        final bTs = b['date'] as Timestamp? ?? Timestamp.now();
        return aTs.compareTo(bTs);
      });
      return all;
    });
  }

  Future<void> _markCompleted(String docId, {bool isEvent = false}) async {
    if (_animatingCompleted.contains(docId)) return;
    setState(() => _animatingCompleted.add(docId));
    await Future.delayed(const Duration(milliseconds: 400));

    final col = isEvent ? 'events' : 'tasks';
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection(col)
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
        style: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.6)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    const double padding = 16.0;

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
                    icon: const Icon(Icons.notifications_none, color: AppColors.black),
                    onPressed: () => Navigator.pushNamed(context, '/notifications'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: AppColors.black),
                    onPressed: () => Navigator.pushNamed(context, '/settings'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _itemsStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];

          // Group items by DateTime (year-month-day) using the canonical 'date' (Timestamp).
          final grouped = <DateTime, List<Map<String, dynamic>>>{};
          for (var item in items) {
            final rawDate = item['date'];
            Timestamp ts;
            if (rawDate is Timestamp) {
              ts = rawDate;
            } else if (rawDate is DateTime) {
              ts = Timestamp.fromDate(rawDate);
            } else {
              // fallback to canonical parser
              ts = _canonicalTimestampFromMap(item);
            }
            final d = DateTime(ts.toDate().year, ts.toDate().month, ts.toDate().day);
            grouped.putIfAbsent(d, () => []).add(item);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action buttons
                Row(
                  children: [
                    Expanded(child: _ActionButton(label: 'Task', onTap: () => Navigator.pushNamed(context, '/task'))),
                    const SizedBox(width: 8),
                    Expanded(child: _ActionButton(label: 'Event', onTap: () => Navigator.pushNamed(context, '/event'))),
                    const SizedBox(width: 8),
                    Expanded(child: _ActionButton(label: 'Mail', onTap: () => Navigator.pushNamed(context, '/mail'))),
                  ],
                ),

                const SizedBox(height: 32),

                // Date + toggle
                Row(
                  children: [
                    Text(
                      DateFormat.yMMMMd().format(DateTime.now()),
                      style: AppText.heading2.copyWith(color: AppColors.black, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        _format == CalendarFormat.week ? Icons.calendar_view_month : Icons.calendar_view_week,
                        size: 24,
                        color: AppColors.black,
                      ),
                      onPressed: () => setState(() => _format = _format == CalendarFormat.week ? CalendarFormat.month : CalendarFormat.week),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Calendar
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.black.withOpacity(0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(8),
                  child: TableCalendar<Map<String, dynamic>>(
                    firstDay: DateTime.utc(2000, 1, 1),
                    lastDay: DateTime.utc(2100, 12, 31),
                    focusedDay: _focusedDay,
                    calendarFormat: _format,
                    headerVisible: false,
                    daysOfWeekVisible: true,
                    onFormatChanged: (f) => setState(() => _format = f),
                    onPageChanged: (d) => _focusedDay = d,
                    calendarStyle: CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: AppColors.blue.withOpacity(0.8),
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle: const TextStyle(color: AppColors.black),
                    ),
                    // Use grouped map to load events for each day
                    eventLoader: (day) {
                      final key = DateTime(day.year, day.month, day.day);
                      return grouped[key] ?? [];
                    },
                    calendarBuilders: CalendarBuilders(
                      markerBuilder: (ctx, day, events) {
                        if (events.isEmpty) return const SizedBox();
                        return Positioned(
                          bottom: 1,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              events.length.clamp(0, 3),
                                  (i) {
                                final ev = events[i];
                                final isEvent = (ev['type'] == 'event');
                                final colorHex = (ev['color'] as String?) ?? _defaultColorHex;
                                Color dotColor;
                                try {
                                  dotColor = Color(int.parse(colorHex.replaceFirst('#', '0x')));
                                } catch (_) {
                                  dotColor = isEvent ? Colors.red : AppColors.blue;
                                }
                                return Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Next Actions
                Text('Next Actions', style: AppText.heading2.copyWith(color: AppColors.black, fontSize: 18)),
                const SizedBox(height: 16),

                if (items.isEmpty)
                  _buildEmptyCard()
                else
                  Column(
                    children: items.map((item) {
                      final title = item['title'] ?? '';
                      final details = item['details'] ?? item['notes'] ?? '';
                      final location = item['location'] ?? '';
                      final colorHex = (item['color'] as String?) ?? _defaultColorHex;
                      Color color;
                      try {
                        color = Color(int.parse(colorHex.replaceFirst('#', '0x')));
                      } catch (_) {
                        color = AppColors.blue;
                      }
                      final isTask = item['type'] == 'task';
                      final isEvent = item['type'] == 'event';
                      final isAnimating = _animatingCompleted.contains(item['id']);

                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: isAnimating ? 0.2 : 1,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title, style: AppText.bodyText.copyWith(fontWeight: FontWeight.bold)),
                                    if (details.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(details, style: AppText.bodyText.copyWith(fontSize: 13)),
                                      ),
                                    if (location.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text('📍 $location', style: AppText.bodyText.copyWith(fontSize: 13, color: Colors.black87)),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.check_circle, color: isAnimating ? color : Colors.white),
                                onPressed: () => _markCompleted(item['id'], isEvent: isEvent),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: AppColors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(label, style: AppText.bodyText.copyWith(color: AppColors.black, fontSize: 13), overflow: TextOverflow.ellipsis),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: AppColors.splashGradient),
              child: const Icon(Icons.add, size: 16, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
