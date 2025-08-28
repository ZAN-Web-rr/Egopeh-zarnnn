import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants/colors.dart';
import '../constants/text.dart';
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final notes$ = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('date', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(color: AppColors.black),
        title: Text('Notifications', style: AppText.heading2),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: notes$,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return _EmptyNotifications();

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final d = docs[i];
              final date = (d['date'] as Timestamp).toDate();
              return Dismissible(
                key: Key(d.id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) {
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('notifications')
                      .doc(d.id)
                      .delete();
                },
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: ListTile(
                  title: Text(d['title'] as String, style: AppText.subtitle1),
                  subtitle: Text(d['body'] as String, style: AppText.bodyText),
                  trailing: Text(
                    DateFormat.Hm().format(date),
                    style: AppText.bodyText.copyWith(color: Colors.grey),
                  ),
                  onTap: () {
                    // mark read?
                    d.reference.update({'unread': false});
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
class _EmptyNotifications extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No notifications yet',
              style: AppText.subtitle1.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Once you get an update, it’ll show up here.',
              style: AppText.bodyText.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

