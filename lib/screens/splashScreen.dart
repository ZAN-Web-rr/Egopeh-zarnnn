import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants/colors.dart';
import '../constants/text.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();

    // Wait 2-3 seconds for the splash, but also wait for the first auth state event.
    Future.delayed(const Duration(seconds: 3), () async {
      try {
        // Wait for the first auth state event (completes immediately if auth already initialized)
        final user = await _auth.authStateChanges().first;

        if (mounted) {
          if (user != null) {
            Navigator.pushReplacementNamed(context, '/dashboard');
          } else {
            Navigator.pushReplacementNamed(context, '/onboarding');
          }
        }
      } catch (e) {
        // Fallback: go to onboarding if anything goes wrong
        if (mounted) Navigator.pushReplacementNamed(context, '/onboarding');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/logoo.png', width: 120),
              Text(
                'Zarn',
                style: AppText.heading1.copyWith(
                  color: AppColors.white,
                  fontSize: 48,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Best bet to productivity',
                style: AppText.subtitle1.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
