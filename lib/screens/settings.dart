import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/text.dart';
import 'profile.dart';          // external ProfileScreen
import 'integrations.dart';    // external IntegrationsScreen
import 'subscription.dart';    // external SubscriptionPlanScreen
import 'language.dart';        // external LanguageScreen

class SettingsScreen extends StatelessWidget {
  final Locale currentLocale;                             // ADDED
  final ValueChanged<Locale> onLocaleChanged;             // ADDED

  const SettingsScreen({
    Key? key,
    required this.currentLocale,                          // ADDED
    required this.onLocaleChanged,                        // ADDED
  }) : super(key: key);

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(color: AppColors.black),
        title: Text('Settings', style: AppText.heading2),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  title: Text('Profile', style: AppText.bodyText),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _navigateTo(context, const ProfileScreen()),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  title: Text('Integrations', style: AppText.bodyText),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _navigateTo(context, const IntegrationsScreen()),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  title: Text('Subscription Plan', style: AppText.bodyText),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Free plan', style: AppText.bodyText.copyWith(color: Colors.grey)),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => _navigateTo(context,  SubscriptionScreen()),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  title: Text('Language', style: AppText.bodyText),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _navigateTo(
                    context,
                    LanguageScreen(
                      currentLocale: currentLocale,                // FIXED
                      onLocaleChanged: onLocaleChanged,            // FIXED
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 32.0),
            child: TextButton(

                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                },


              child: Text(
                'Logout',
                style: AppText.bodyText.copyWith(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
