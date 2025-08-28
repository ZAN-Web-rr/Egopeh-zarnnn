// file: lib/screens/create_email_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';

import 'subscription.dart'; // local subscription screen (same folder)
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/colors.dart';
import '../constants/text.dart';
import '../services/azure_conversation.dart'; // keep as-is (contains VertexAIService)

/// Generic auto-closing modal used to replace SnackBars.
/// Usage: await showStatusModal(context, 'Title', subtitle: 'Optional', icon: Icons.check, color: Colors.blue);
Future<void> showStatusModal(
    BuildContext context,
    String title, {
      String? subtitle,
      IconData? icon,
      Color? color,
      int durationMs = 1200,
    }) async {
  final modalColor = color ?? Colors.blue;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12)],
            ),
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: modalColor,
                  child: Icon(icon ?? Icons.info, color: Colors.white, size: 26),
                ),
                const SizedBox(height: 12),
                Text(title, style: AppText.bodyText.copyWith(fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle, style: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.6), fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  await Future.delayed(Duration(milliseconds: durationMs));

  // close the modal if still open
  if (Navigator.of(context, rootNavigator: true).canPop()) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}

// -----------------------------
// Global helper to check and consume AI attempts.
// This duplicates the transactional logic but is shared so both Suggest and Summarize use the same rule.
// Free monthly quota changed from 3 -> 15 here.
// -----------------------------
Future<bool> canUseAiAndConsumeGlobal(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    await showStatusModal(context, 'Please sign in to use AI', icon: Icons.lock, color: Colors.blue);
    return false;
  }
  final uid = user.uid;
  final db = FirebaseFirestore.instance;

  final subRef = db.collection('users').doc(uid).collection('meta').doc('subscription');
  final usageRef = db.collection('users').doc(uid).collection('meta').doc('ai_usage');

  try {
    return await db.runTransaction<bool>((tx) async {
      final subSnap = await tx.get(subRef);
      final usageSnap = await tx.get(usageRef);

      // Default plan values
      String plan = 'free';
      Timestamp? expiresTs;
      int? aiQuota; // null => unlimited

      if (subSnap.exists) {
        final data = subSnap.data()!;
        plan = (data['plan'] as String?) ?? 'free';
        expiresTs = data['expiresAt'] as Timestamp?;
        if (data.containsKey('aiQuota')) {
          aiQuota = (data['aiQuota'] is int) ? data['aiQuota'] as int : null;
        } else {
          aiQuota = null;
        }
      }

      final now = DateTime.now();
      bool subActive = false;
      if (expiresTs != null) {
        subActive = expiresTs.toDate().isAfter(now);
      } else {
        subActive = false;
      }

      // read usage
      int count = 0;
      Timestamp periodStartTs = Timestamp.fromDate(now);
      if (usageSnap.exists) {
        final d = usageSnap.data()!;
        count = (d['count'] as int?) ?? 0;
        periodStartTs = (d['periodStart'] as Timestamp?) ?? Timestamp.fromDate(now);
      } else {
        count = 0;
        periodStartTs = Timestamp.fromDate(now);
      }

      // reset period if older than 30 days
      final periodStart = periodStartTs.toDate();
      if (now.difference(periodStart).inDays >= 30) {
        count = 0;
        periodStartTs = Timestamp.fromDate(now);
      }

      // decide effective quota (free quota increased to 15 per month)
      const int freeQuota = 15;
      int? effectiveQuota;
      if (subActive) {
        // if subscription active and aiQuota is null => unlimited
        effectiveQuota = aiQuota; // might be null => unlimited
      } else {
        effectiveQuota = freeQuota;
      }

      // allow or block
      if (effectiveQuota == null) {
        // unlimited: still record usage count for analytics
        final newCount = count + 1;
        tx.set(usageRef, {
          'count': newCount,
          'periodStart': periodStartTs,
          'lastUsed': FieldValue.serverTimestamp(),
        });
        return true;
      } else {
        if (count < effectiveQuota) {
          final newCount = count + 1;
          tx.set(usageRef, {
            'count': newCount,
            'periodStart': periodStartTs,
            'lastUsed': FieldValue.serverTimestamp(),
          });
          return true;
        } else {
          // exhausted
          return false;
        }
      }
    });
  } catch (e) {
    debugPrint('AI usage check error: $e');
    await showStatusModal(context, 'Could not check subscription', icon: Icons.error, color: Colors.red);
    return false;
  }
}

class CreateEmailScreen extends StatefulWidget {
  const CreateEmailScreen({Key? key}) : super(key: key);

  @override
  _CreateEmailScreenState createState() => _CreateEmailScreenState();
}

class _CreateEmailScreenState extends State<CreateEmailScreen> {
  bool _useGoogle = false;
  bool _autoReminder = false;
  bool _attachInvite = false;
  bool _aiLoading = false;

  final _toController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final _aiPromptController = TextEditingController();

  final GoogleSignIn _google = GoogleSignIn(
    scopes: [
      'email',
      'profile',
      'openid',
      'https://www.googleapis.com/auth/gmail.readonly',
      'https://www.googleapis.com/auth/gmail.send',
    ],
  );

  List<SimpleMail> _mails = [];
  bool _loadingMails = false;
  String _selectedTone = 'Professional';
  static const _prefGoogleKey = 'google_connected';

  @override
  void initState() {
    super.initState();
    _restoreGoogleToggle();
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _aiPromptController.dispose();
    super.dispose();
  }

  Future<void> _restoreGoogleToggle() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefGoogleKey) ?? false;
    setState(() => _useGoogle = saved);

    if (saved) {
      try {
        final acc = await _google.signInSilently();
        if (acc != null) {
          debugPrint('Restored Google sign-in for ${acc.email}');
          await _fetchMailsSilently();
        } else {
          debugPrint('Silent sign-in failed - needs re-consent');
        }
      } catch (e) {
        debugPrint('Error restoring google-sign-in: $e');
      }
    }
  }

  Future<void> _toggleGoogle(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    if (!v) {
      try {
        await _google.disconnect();
      } catch (e) {
        debugPrint('Google disconnect error: $e');
      }
      await prefs.setBool(_prefGoogleKey, false);
      setState(() {
        _useGoogle = false;
        _mails = [];
      });
      await showStatusModal(context, 'Google disconnected', icon: Icons.cloud_off, color: Colors.blue);
      return;
    }

    try {
      await _google.signOut();
      final account = await _google.signIn();
      if (account != null) {
        await prefs.setBool(_prefGoogleKey, true);
        setState(() => _useGoogle = true);
        await showStatusModal(context, 'Connected', subtitle: account.email, icon: Icons.check_circle, color: Colors.blue);
        await _fetchMailsSilently();
      } else {
        setState(() => _useGoogle = false);
      }
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      await showStatusModal(context, 'Google sign-in error', subtitle: e.toString(), icon: Icons.error, color: Colors.red);
      setState(() => _useGoogle = false);
    }
  }

  Future<void> _fetchMailsSilently() async {
    setState(() => _loadingMails = true);
    try {
      final account = await _google.signInSilently();
      if (account == null) {
        debugPrint('No google account available to fetch mails');
        setState(() => _loadingMails = false);
        return;
      }

      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null) {
        debugPrint('No access token');
        setState(() => _loadingMails = false);
        return;
      }

      // list messages
      final listRes = await http.get(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=20'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (listRes.statusCode != 200) {
        debugPrint('Failed to list messages: ${listRes.body}');
        setState(() => _loadingMails = false);
        return;
      }

      final listJson = json.decode(listRes.body);
      final messages = (listJson['messages'] as List?) ?? [];

      final List<SimpleMail> mails = [];

      for (final m in messages) {
        final id = m['id'];
        final msgRes = await http.get(
          Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$id?format=full'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (msgRes.statusCode != 200) continue;
        final msgJson = json.decode(msgRes.body);

        final snippet = msgJson['snippet'] ?? '';
        String subject = '';
        String from = '';
        String body = '';
        DateTime? date;

        try {
          final headers = (msgJson['payload']?['headers'] as List?) ?? [];
          for (final h in headers) {
            final name = h['name'] as String? ?? '';
            final value = h['value'] as String? ?? '';
            if (name == 'Subject') subject = value;
            if (name == 'From') from = value;
            if (name == 'Date' && date == null) {
              try {
                date = DateTime.parse(value);
              } catch (_) {
                // ignore parse errors for header Date
              }
            }
          }

          // internalDate is milliseconds since epoch as string
          if (date == null && msgJson['internalDate'] != null) {
            try {
              final millis = int.parse(msgJson['internalDate'].toString());
              date = DateTime.fromMillisecondsSinceEpoch(millis);
            } catch (_) {}
          }

          body = _extractPlainTextFromPayload(msgJson['payload']);
        } catch (e) {
          debugPrint('Error parsing message: $e');
        }

        mails.add(SimpleMail(
          id: id,
          from: from,
          subject: subject,
          snippet: snippet,
          body: body,
          date: date,
        ));
      }

      setState(() {
        _mails = mails;
      });
    } catch (e) {
      debugPrint('Error fetching mails: $e');
    } finally {
      setState(() => _loadingMails = false);
    }
  }

  String _extractPlainTextFromPayload(dynamic payload) {
    if (payload == null) return '';
    final mimeType = payload['mimeType'] as String? ?? '';
    if (mimeType == 'text/plain' && payload['body'] != null && payload['body']['data'] != null) {
      final raw = payload['body']['data'] as String;
      return _decodeGmailBase64(raw);
    }

    final parts = payload['parts'] as List?;
    if (parts != null) {
      for (final p in parts) {
        final mt = p['mimeType'] as String? ?? '';
        if (mt == 'text/plain' && p['body'] != null && p['body']['data'] != null) {
          return _decodeGmailBase64(p['body']['data'] as String);
        }
        // nested parts
        if (p['parts'] != null) {
          final nested = _extractPlainTextFromPayload(p);
          if (nested.isNotEmpty) return nested;
        }
      }
    }

    return '';
  }

  String _decodeGmailBase64(String input) {
    String normalized = input.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) normalized += '=';
    try {
      return utf8.decode(base64.decode(normalized));
    } catch (e) {
      return '';
    }
  }

  Future<bool> _sendEmailViaGmail(String to, String subject, String body) async {
    try {
      final account = await _google.signInSilently();
      if (account == null) {
        await showStatusModal(context, 'Google not signed in', icon: Icons.account_circle, color: Colors.blue);
        return false;
      }
      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null) {
        await showStatusModal(context, 'Missing access token', icon: Icons.lock_clock, color: Colors.blue);
        return false;
      }

      final raw = StringBuffer();
      raw.writeln('To: $to');
      raw.writeln('Subject: $subject');
      raw.writeln('Content-Type: text/plain; charset=utf-8');
      raw.writeln();
      raw.writeln(body);

      final encoded = base64Url.encode(utf8.encode(raw.toString()));
      final res = await http.post(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/send'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'raw': encoded}),
      );

      if (res.statusCode == 200) {
        return true;
      } else {
        debugPrint('Send failed: ${res.statusCode} ${res.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Send exception: $e');
      return false;
    }
  }

  String _summarizeText(String text) {
    if (text.isEmpty) return '';
    final sentences = RegExp(r'[^.!?]+[.!?]').allMatches(text).map((m) => m.group(0)!.trim()).toList();
    if (sentences.isNotEmpty) {
      if (sentences.length >= 2) return sentences.sublist(0, 2).join(' ');
      return sentences.first;
    }
    return text.length <= 160 ? text : '${text.substring(0, 157)}...';
  }

  // -----------------------
  // AI helpers (VertexAI via azure_conversation.dart)
  // -----------------------

  /// Generate email suggestion using Vertex AI.
  Future<String> _generateAiSuggestion(String prompt, String tone, String subject) async {
    if (prompt.trim().isEmpty) return '';

    final composedPrompt = 'Write a $tone email about \"$subject\". User instructions: ${prompt.trim()}';

    try {
      // initialize VertexAI if needed
      await VertexAIService.instance.init(location: 'us-central1', modelName: 'gemini-2.5-flash-lite');

      // Use one-shot prompt generation
      final reply = await VertexAIService.instance.generateTextFromPrompt(composedPrompt, modelName: 'gemini-2.5-flash-lite');
      return reply;
    } catch (e) {
      debugPrint('VertexAI error: $e');
      return 'Suggested ($tone) message about \"$subject\": ${prompt.trim()} - You can expand on this with details about next steps, timelines and contact info.';
    }
  }

  /// Show an AI-produced summary for the given mail (async).
  Future<void> _showAiSummary(SimpleMail m) async {
    final textToSummarize = (m.body.isNotEmpty ? m.body : m.snippet).trim();
    if (textToSummarize.isEmpty) {
      await showStatusModal(context, 'Nothing to summarize', icon: Icons.info_outline, color: Colors.blue);
      return;
    }

    // Check quota and consume
    final allowed = await canUseAiAndConsumeGlobal(context);
    if (!allowed) {
      // Not allowed -> prompt upgrade
      await _showUpgradeDialog();
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Use 'global' location for summarization if your Vertex setup uses global; adjust if different
      await VertexAIService.instance.init(location: 'global', modelName: 'gemini-2.5-flash-lite');

      final aiSummary = await VertexAIService.instance.summarizeEmailThread(textToSummarize);

      // close loading dialog
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // show result
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('AI Summary'),
          content: Text(aiSummary.isNotEmpty ? aiSummary : 'No summary produced.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      debugPrint('AI summarization error: $e');
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await showStatusModal(context, 'AI summarization failed', subtitle: e.toString(), icon: Icons.error, color: Colors.red);
    }
  }

  // open external links
  Future<void> _openLink(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Could not launch $url');
      }
    } catch (e) {
      debugPrint('Open link error: $e');
    }
  }

  /// Shows a small modal confirming send, then clears the compose fields.
  Future<void> _showSentModalAndClear() async {
    // show a centered, non-dismissible modal
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12)],
              ),
              width: 240,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // send badge
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.send, color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 12),
                  Text('Message sent', style: AppText.bodyText.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  // small status chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text('Sent', style: AppText.bodyText.copyWith(color: Colors.blue, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // wait (auto-close)
    await Future.delayed(const Duration(milliseconds: 1200));

    // close the dialog
    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    // clear the compose fields and remove focus
    _toController.clear();
    _subjectController.clear();
    _bodyController.clear();
    FocusScope.of(context).unfocus();

    // optionally reset any other state if needed
    setState(() {});
  }

  void _showInbox() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        minChildSize: 0.25,
        initialChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _useGoogle ? _buildMailList(scrollController) : _buildNotConnectedView(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotConnectedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 48, color: AppColors.black.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('Connect Google to view your emails', style: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.5))),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: () => _toggleGoogle(true), child: const Text('Connect Google')),
        ],
      ),
    );
  }

  Widget _buildMailList(ScrollController scrollController) {
    if (_loadingMails) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_mails.isEmpty) {
      return Center(child: Text('No emails yet', style: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.4))));
    }

    return ListView.builder(
      controller: scrollController,
      itemCount: _mails.length,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemBuilder: (context, i) {
        final m = _mails[i];
        return EmailListItem(
          mail: m,
          onSummarize: () {
            // Use AI summarization when user taps Summarize
            _showAiSummary(m);
          },
          onOpen: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EmailDetailScreen(mail: m, summarizer: _summarizeText, onOpenLink: _openLink)),
            );
          },
          onOpenLink: _openLink,
        );
      },
    );
  }

  Widget _buildInputField({required TextEditingController controller, required String hint}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: TextField(
        controller: controller,
        style: AppText.bodyText,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.4), fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildMultilineField({required TextEditingController controller, required String hint}) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: controller,
        maxLines: null,
        expands: true,
        style: AppText.bodyText,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.4), fontSize: 14),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  // -----------------------
  // FIREBASE AI USAGE HELPERS
  // -----------------------

  /// Checks if the current user can use AI and consumes a single "try" atomically.
  /// Returns true if allowed (and usage consumed), false if quota exhausted or on error.
  Future<bool> _canUseAiAndConsume() async {
    return await canUseAiAndConsumeGlobal(context);
  }

  // Shows a dialog prompting the user to upgrade; navigates to SubscriptionScreen on user confirmation.
  Future<void> _showUpgradeDialog() async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Upgrade required'),
          content: const Text('You have used your free AI attempts. Upgrade to a plan to continue using AI.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                // navigate to subscription screen
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
              },
              child: const Text('Upgrade'),
            ),
          ],
        );
      },
    );
  }

  // -----------------------
  // UI: AI helper + Suggest button (wired to Firebase usage checks)
  // -----------------------
  Widget _buildAiHelper() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI Assist', style: AppText.bodyText.copyWith(color: AppColors.black)),
        const SizedBox(height: 8),
        _buildInputField(controller: _aiPromptController, hint: 'Describe what you want to say (e.g. follow-up, intro, meeting reminder)'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedTone,
                items: const [
                  DropdownMenuItem(value: 'Professional', child: Text('Professional')),
                  DropdownMenuItem(value: 'Casual', child: Text('Casual')),
                  DropdownMenuItem(value: 'Short', child: Text('Short')),
                ],
                onChanged: (v) => setState(() => _selectedTone = v ?? 'Professional'),
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _aiLoading ? null : () async {
                final prompt = _aiPromptController.text.trim();
                final subject = _subjectController.text.trim();
                if (prompt.isEmpty) {
                  await showStatusModal(context, 'Enter a prompt for AI', icon: Icons.info_outline, color: Colors.blue);
                  return;
                }

                setState(() => _aiLoading = true);
                try {
                  // Check quota / subscription (transactionally consumes a try if allowed)
                  final allowed = await _canUseAiAndConsume();
                  if (!allowed) {
                    // Not allowed -> prompt upgrade
                    await _showUpgradeDialog();
                    return;
                  }

                  // proceed with AI request
                  final suggestion = await _generateAiSuggestion(prompt, _selectedTone, subject);
                  if (suggestion.isNotEmpty) {
                    final newBody = '${_bodyController.text}\n\n$suggestion';
                    setState(() {
                      _bodyController.text = newBody;
                      _bodyController.selection = TextSelection.fromPosition(TextPosition(offset: _bodyController.text.length));
                    });
                  } else {
                    await showStatusModal(context, 'AI returned empty suggestion', icon: Icons.info_outline, color: Colors.blue);
                  }
                } catch (e) {
                  debugPrint('AI suggestion error: $e');
                  await showStatusModal(context, 'AI suggestion failed', subtitle: e.toString(), icon: Icons.error, color: Colors.red);
                } finally {
                  if (mounted) setState(() => _aiLoading = false);
                }
              },
              child: _aiLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Suggest'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.bodyText.copyWith(color: AppColors.black)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.blue,
          inactiveThumbColor: AppColors.white,
          inactiveTrackColor: AppColors.black.withOpacity(0.2),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  const SizedBox(width: 8),
                  Text('Email Services', style: AppText.heading2),
                  const Spacer(),
                  Ink(
                    decoration: const ShapeDecoration(
                      color: AppColors.blue,
                      shape: CircleBorder(),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.email, color: AppColors.white),
                      onPressed: _showInbox,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildToggle('Google', _useGoogle, (v) => _toggleGoogle(v)),
              const SizedBox(height: 24),
              _buildToggle('Auto Send Reminder', _autoReminder, (v) => setState(() => _autoReminder = v)),
              const SizedBox(height: 16),
              _buildToggle('Attach Calendar Invite', _attachInvite, (v) => setState(() => _attachInvite = v)),
              const SizedBox(height: 24),
              Text('To', style: AppText.bodyText.copyWith(color: AppColors.black)),
              const SizedBox(height: 8),
              _buildInputField(controller: _toController, hint: 'recipient@example.com'),
              const SizedBox(height: 16),
              Text('Subject', style: AppText.bodyText.copyWith(color: AppColors.black)),
              const SizedBox(height: 8),
              _buildInputField(controller: _subjectController, hint: 'Subject'),
              const SizedBox(height: 16),
              Text('Message', style: AppText.bodyText.copyWith(color: AppColors.black)),
              const SizedBox(height: 8),
              _buildMultilineField(controller: _bodyController, hint: 'Type your message here'),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.attach_file, color: Colors.black45)),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.image, color: Colors.black45)),
                ],
              ),
              const SizedBox(height: 12),
              _buildAiHelper(),
              const SizedBox(height: 20),
              // Send button: updated onTap to show progress + success modal
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final to = _toController.text.trim();
                        final subject = _subjectController.text.trim();
                        final body = _bodyController.text.trim();
                        if (to.isEmpty) {
                          await showStatusModal(context, 'Enter recipient', icon: Icons.person, color: Colors.blue);
                          return;
                        }
                        if (_useGoogle) {
                          // show a small progress affordance while sending
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const Center(child: CircularProgressIndicator()),
                          );

                          final ok = await _sendEmailViaGmail(to, subject, body);

                          // close progress indicator
                          if (mounted) Navigator.of(context, rootNavigator: true).pop();

                          if (ok) {
                            // show success modal + clear fields
                            await _showSentModalAndClear();
                            // already shown via modal; no snackbar
                          } else {
                            await showStatusModal(context, 'Failed to send', icon: Icons.error, color: Colors.red);
                          }
                        } else {
                          await showStatusModal(context, 'Connect Google to send', icon: Icons.cloud_off, color: Colors.blue);
                        }
                      },
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF6EC1E4), Color(0xFF007ACC)]),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        alignment: Alignment.center,
                        child: Text('Send', style: AppText.bodyText.copyWith(color: AppColors.white)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: AppText.bodyText.copyWith(color: Colors.red)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------
// Compact list item widget
// -----------------------------
class EmailListItem extends StatefulWidget {
  final SimpleMail mail;
  final VoidCallback onSummarize;
  final VoidCallback onOpen;
  final Future<void> Function(String) onOpenLink;

  const EmailListItem({
    Key? key,
    required this.mail,
    required this.onSummarize,
    required this.onOpen,
    required this.onOpenLink,
  }) : super(key: key);

  @override
  State<EmailListItem> createState() => _EmailListItemState();
}

class _EmailListItemState extends State<EmailListItem> {
  bool _hover = false;

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) {
      final hour = dt.hour == 0 || dt.hour == 12 ? 12 : dt.hour % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      final suffix = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$min $suffix';
    } else if (dt.year == now.year) {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}';
    } else {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mail;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: _hover ? Colors.grey.shade50 : Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: InkWell(
          onTap: widget.onOpen,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.blue.withOpacity(0.12),
                child: Text(
                  m.from.isNotEmpty ? m.from.trim()[0].toUpperCase() : 'U',
                  style: AppText.bodyText.copyWith(color: AppColors.blue),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // top row: subject and timestamp
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            m.subject.isNotEmpty ? m.subject : '(no subject)',
                            style: AppText.bodyText.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTimestamp(m.date),
                          style: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.45), fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            m.from,
                            style: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.6), fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      m.snippet.isNotEmpty ? m.snippet : (m.body.isNotEmpty ? _summarizeSnippet(m.body) : ''),
                      style: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.8), fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: widget.onSummarize,
                            child: const Text('Summarize'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: widget.onOpen,
                          child: const Text('Open'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _summarizeSnippet(String text) {
    if (text.isEmpty) return '';
    final sentences = RegExp(r'[^.!?]+[.!?]').allMatches(text).map((m) => m.group(0)!.trim()).toList();
    if (sentences.isNotEmpty) {
      return sentences.first;
    }
    return text.length <= 120 ? text : '${text.substring(0, 117)}...';
  }
}

// -----------------------------
// Simple model for UI convenience (added date)
// -----------------------------
class SimpleMail {
  final String id;
  final String from;
  final String subject;
  final String snippet;
  final String body;
  final DateTime? date;

  SimpleMail({
    required this.id,
    required this.from,
    required this.subject,
    required this.snippet,
    required this.body,
    this.date,
  });
}

// -----------------------------
// Detail screen with paragraphs + linkify
// -----------------------------
class EmailDetailScreen extends StatelessWidget {
  final SimpleMail mail;
  final String Function(String) summarizer;
  final Future<void> Function(String)? onOpenLink;

  const EmailDetailScreen({
    Key? key,
    required this.mail,
    required this.summarizer,
    this.onOpenLink,
  }) : super(key: key);

  static List<String> _splitIntoParagraphs(String text) {
    final parts = text.split(RegExp(r'\n\s*\n'));
    if (parts.length <= 1) {
      return text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return parts.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final body = mail.body.isNotEmpty ? mail.body : mail.snippet;
    final paragraphs = _splitIntoParagraphs(body);
    final summary = summarizer(body);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: const BackButton(color: AppColors.black),
        title: Text(mail.subject.isNotEmpty ? mail.subject : 'Email', style: AppText.heading2),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('From: ${mail.from}', style: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.6))),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in paragraphs) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Linkify(
                          text: p,
                          onOpen: (link) async {
                            if (onOpenLink != null) {
                              await onOpenLink!(link.url);
                            } else {
                              final uri = Uri.parse(link.url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            }
                          },
                          options: const LinkifyOptions(humanize: true),
                          style: AppText.bodyText,
                          linkStyle: AppText.bodyText.copyWith(decoration: TextDecoration.underline, color: AppColors.blue),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () async {
                    // Check quota and consume (same rules as CreateEmailScreen)
                    final allowed = await canUseAiAndConsumeGlobal(context);
                    if (!allowed) {
                      // prompt user to upgrade by opening subscription screen
                      showDialog(
                        context: context,
                        barrierDismissible: true,
                        builder: (ctx) {
                          return AlertDialog(
                            title: const Text('Upgrade required'),
                            content: const Text('You have used your free AI attempts. Upgrade to a plan to continue using AI.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Not now')),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
                                },
                                child: const Text('Upgrade'),
                              ),
                            ],
                          );
                        },
                      );
                      return;
                    }

                    // Show loading
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );

                    try {
                      await VertexAIService.instance.init(location: 'global', modelName: 'gemini-2.5-flash-lite');
                      final aiSummary = await VertexAIService.instance.summarizeEmailThread(body);

                      if (Navigator.of(context, rootNavigator: true).canPop()) {
                        Navigator.of(context, rootNavigator: true).pop();
                      }

                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('AI Summary'),
                          content: Text(aiSummary.isNotEmpty ? aiSummary : 'No summary produced.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                        ),
                      );
                    } catch (e) {
                      if (Navigator.of(context, rootNavigator: true).canPop()) {
                        Navigator.of(context, rootNavigator: true).pop();
                      }
                      debugPrint('AI summarization error (detail): $e');
                      await showStatusModal(context, 'AI summarization failed', subtitle: e.toString(), icon: Icons.error, color: Colors.red);
                    }
                  },
                  child: const Text('Summarize'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    await showStatusModal(context, 'Reply using main compose screen', icon: Icons.reply, color: AppColors.blue);
                  },
                  child: const Text('Reply'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
