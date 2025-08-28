import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/colors.dart';
import '../constants/text.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({Key? key}) : super(key: key);

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  final _auth = FirebaseAuth.instance;
  final _appAuth = FlutterAppAuth();

  final _google = GoogleSignIn(
    scopes: ['email', 'profile', 'openid'],
  );

  static const _msalClientId = '68eedf3c-6708-43f0-8254-0009be23aacf';
  static const _redirectUri = 'msauth://com.example.zarn/redirect';
  static const _discoveryUrl = 'https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration';
  static const _outlookScopes = ['openid', 'email', 'profile', 'User.Read'];

  final Map<String, bool> _connected = {
    'Google': false,
    'Outlook': false,
  };

  // keys for SharedPreferences
  static const _prefGoogleKey = 'google_connected';
  static const _prefOutlookKey = 'outlook_connected';

  @override
  void initState() {
    super.initState();

    // require signed in user for the screen
    if (_auth.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/login');
      });
      return;
    }

    // restore connection state
    _restoreConnections();
  }

  Future<void> _restoreConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final googleSaved = prefs.getBool(_prefGoogleKey) ?? false;
      final outlookSaved = prefs.getBool(_prefOutlookKey) ?? false;

      // Try to silently restore Google if we previously saved it as connected
      if (googleSaved) {
        try {
          final account = await _google.signInSilently();
          if (account != null) {
            debugPrint('🔁 Restored Google sign-in for ${account.email}');
            setState(() => _connected['Google'] = true);
          } else {
            // silent restore failed; clear saved flag
            await prefs.setBool(_prefGoogleKey, false);
            setState(() => _connected['Google'] = false);
          }
        } catch (e) {
          debugPrint('❌ Error restoring Google sign-in: $e');
          await prefs.setBool(_prefGoogleKey, false);
          setState(() => _connected['Google'] = false);
        }
      } else {
        setState(() => _connected['Google'] = false);
      }

      // For Outlook we just trust the saved flag (you can extend this to refresh tokens)
      setState(() => _connected['Outlook'] = outlookSaved);
    } catch (e) {
      debugPrint('❌ _restoreConnections error: $e');
    }
  }

  Future<void> _connectGoogle() async {
    final currentlyConnected = _connected['Google'] ?? false;

    final prefs = await SharedPreferences.getInstance();

    if (currentlyConnected) {
      // Disconnect
      try {
        await _google.disconnect(); // revoke access and sign out
        await prefs.setBool(_prefGoogleKey, false);
        setState(() => _connected['Google'] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google disconnected')),
        );
        debugPrint('🔌 Google disconnected');
      } catch (e) {
        debugPrint('❌ Error disconnecting Google: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to disconnect Google: $e')),
        );
      }
      return;
    }

    // Connect
    try {
      // Force account picker by signing out first (optional)
      await _google.signOut();

      final account = await _google.signIn();
      if (account == null) {
        // user cancelled
        debugPrint('⚠️ Google sign-in cancelled by user');
        return;
      }

      // At this point you have the Google account. We do not change the app's Firebase auth session.
      // If you prefer to link the Google account to the existing Firebase user, use linkWithCredential.
      debugPrint('✅ Google signed in: ${account.email}');

      await prefs.setBool(_prefGoogleKey, true);
      setState(() => _connected['Google'] = true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to Google as ${account.email}')),
      );
    } catch (e) {
      debugPrint('❌ Google sign-in error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sign-in error: $e')),
      );
    }
  }

  Future<void> _connectOutlook() async {
    final currentlyConnected = _connected['Outlook'] ?? false;
    final prefs = await SharedPreferences.getInstance();

    if (currentlyConnected) {
      // "Disconnect" outlook: currently we just clear persisted flag.
      // For full sign-out/revoke implement MSAL revocation if needed.
      await prefs.setBool(_prefOutlookKey, false);
      setState(() => _connected['Outlook'] = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Outlook disconnected')),
      );
      return;
    }

    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _msalClientId,
          _redirectUri,
          discoveryUrl: _discoveryUrl,
          scopes: _outlookScopes,
          promptValues: ['select_account'],
        ),
      );

      if (result?.accessToken != null) {
        final profileRes = await http.get(
          Uri.parse('https://graph.microsoft.com/v1.0/me'),
          headers: {'Authorization': 'Bearer ${result!.accessToken}'},
        );

        if (profileRes.statusCode == 200) {
          final profile = json.decode(profileRes.body);
          final email = profile['mail'] ?? profile['userPrincipalName'];
          debugPrint('✅ Outlook email: $email');

          await prefs.setBool(_prefOutlookKey, true);
          setState(() => _connected['Outlook'] = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connected to Outlook as $email')),
          );
        } else {
          debugPrint('❌ Failed to fetch Outlook email: ${profileRes.body}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to fetch Outlook profile: ${profileRes.statusCode}')),
          );
        }
      } else {
        debugPrint('❌ No access token from MSAL result');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Outlook sign-in failed')),
        );
      }
    } catch (e) {
      debugPrint('❌ Outlook sign-in error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Outlook error: $e')),
      );
    }
  }

  Widget _buildRow(String name, IconData icon, VoidCallback onTap) {
    final connected = _connected[name] ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 28, color: AppColors.black),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: AppText.bodyText)),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              backgroundColor:
              connected ? Colors.red.withOpacity(0.1) : AppColors.blue.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(
              connected ? 'Disconnect' : 'Connect',
              style: AppText.bodyText.copyWith(color: connected ? Colors.red : AppColors.blue),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.black),
        title: Text('Integrations', style: AppText.heading2),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('Connected apps', style: AppText.bodyText.copyWith(color: Colors.grey)),
          ),
          const SizedBox(height: 8),
          _buildRow('Google', Icons.account_circle, _connectGoogle),
          _buildRow('Outlook', Icons.mail_outline, _connectOutlook),
        ],
      ),
    );
  }
}
