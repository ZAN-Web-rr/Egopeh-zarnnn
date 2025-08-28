import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/colors.dart';
import '../constants/text.dart';
import 'subscription.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _picker = ImagePicker();

  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;

  String? _photoURL;
  String _uid = '';
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser!;
    _uid = user.uid;
    _photoURL = user.photoURL;

    _nameCtrl  = TextEditingController(text: user.displayName);
    _emailCtrl = TextEditingController(text: user.email);
    _phoneCtrl = TextEditingController();

    _firestore.collection('users').doc(_uid).get().then((snap) {
      final data = snap.data();
      if (data != null && data['phone'] != null) {
        _phoneCtrl.text = data['phone'];
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setState(() => _uploading = true);
    final file = File(picked.path);
    final ref = FirebaseStorage.instance
        .ref()
        .child('profile_pics')
        .child('$_uid.jpg');

    await ref.putFile(file);
    final url = await ref.getDownloadURL();

    // 1. Update the Auth profile
    await _auth.currentUser!.updatePhotoURL(url);

// 2. Mirror into Firestore
    await _firestore
        .collection('users')
        .doc(_uid)
        .set({'photoURL': url}, SetOptions(merge: true));

// 3. Reload & update local state
    await _auth.currentUser!.reload();
    setState(() {
      _photoURL = url;
      _uploading = false;
    });

  }
  Future<void> _changePassword() async {
    final TextEditingController _newPassCtrl = TextEditingController();
    final TextEditingController _confirmPassCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _newPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password'),
            ),
            TextField(
              controller: _confirmPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPassword = _newPassCtrl.text.trim();
              final confirmPassword = _confirmPassCtrl.text.trim();

              if (newPassword.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password must be at least 6 characters')),
                );
                return;
              }

              if (newPassword != confirmPassword) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passwords do not match')),
                );
                return;
              }

              try {
                await _auth.currentUser?.updatePassword(newPassword);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password updated successfully')),
                );
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: ${e.toString()}')),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog({
    required String title,
    required TextEditingController controller,
    required Future<void> Function() onSave,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await onSave();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(color: AppColors.black),
        title: Text('Profile', style: AppText.heading2),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: _photoURL != null
                        ? NetworkImage(_photoURL!) as ImageProvider
                        : null,
                    child: _photoURL == null
                        ? Icon(Icons.person, size: 60, color: AppColors.black.withOpacity(0.3))
                        : null,
                  ),
                ),
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: FloatingActionButton(
                    onPressed: _uploading ? null : _pickAndUploadImage,
                    mini: true,
                    backgroundColor: AppColors.white,
                    child: _uploading
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Icon(Icons.edit, color: AppColors.blue, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: ListView(
                children: [
                  const SizedBox(height: 16),
                  _buildField(
                    label: 'Name',
                    value: _nameCtrl.text,
                    onEdit: () => _showEditDialog(
                      title: 'Edit Name',
                      controller: _nameCtrl,
                      onSave: () async {
                        // 1. Update the Auth profile
                        await _auth.currentUser!.updateDisplayName(_nameCtrl.text);

// 2. Mirror into Firestore so HomePage picks it up
                        await _firestore
                            .collection('users')
                            .doc(_uid)
                            .set({'name': _nameCtrl.text}, SetOptions(merge: true));

                        setState(() {});

                        setState(() {});
                      },
                    ),
                  ),
                  _buildField(
                    label: 'Phone Number',
                    value: _phoneCtrl.text,
                    onEdit: () => _showEditDialog(
                      title: 'Edit Phone',
                      controller: _phoneCtrl,
                      onSave: () async {
                        await _firestore.collection('users').doc(_uid).set(
                          {'phone': _phoneCtrl.text},
                          SetOptions(merge: true),
                        );
                        setState(() {});
                      },
                    ),
                  ),
                  _buildField(
                    label: 'Email',
                    value: _emailCtrl.text,
                    onEdit: () {}, // Disable editing
                  ),

                  _buildField(
                    label: 'Password',
                    value: '••••••••',
                    onEdit: _changePassword,
                  ),

                  const SizedBox(height: 24),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SubscriptionScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'Upgrade to Pro',
                        style: AppText.bodyText.copyWith(color: AppColors.blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextButton(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text("Reset Account"),
                          content: const Text("Are you sure you want to reset your profile data?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Reset")),
                          ],
                        ),
                      );

                      if (confirm != true) return;

                      try {
                        // Clear name and photo
                        await _auth.currentUser?.updateDisplayName(null);
                        await _auth.currentUser?.updatePhotoURL(null);

                        // Clear Firestore fields
                        await _firestore.collection('users').doc(_uid).set(
                          {'phone': FieldValue.delete()},
                          SetOptions(merge: true),
                        );

                        setState(() {
                          _nameCtrl.text = '';
                          _phoneCtrl.text = '';
                          _photoURL = null;
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Account reset successfully')),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: ${e.toString()}')),
                        );
                      }
                    },

                    child: Text(
                      'Reset Account',
                      style: AppText.bodyText.copyWith(color: AppColors.black),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text("Delete Account"),
                          content: const Text("This will permanently delete your account. Are you sure?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
                          ],
                        ),
                      );

                      if (confirm != true) return;

                      try {
                        // Delete Firestore user data
                        await _firestore.collection('users').doc(_uid).delete();

                        // Delete user account
                        await _auth.currentUser?.delete();

                        // Navigate to login or splash screen
                        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: ${e.toString()}')),
                        );
                      }
                    },

                    child: Text(
                      'Delete Account',
                      style: AppText.bodyText.copyWith(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required String value,
    required VoidCallback onEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.bodyText.copyWith(color: Colors.grey)),
                const SizedBox(height: 4),
                Text(value, style: AppText.bodyText),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit, color: AppColors.blue),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}
