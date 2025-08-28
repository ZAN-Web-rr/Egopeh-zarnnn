import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/text.dart';

class AutomationPage extends StatelessWidget {
  const AutomationPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
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
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.build_circle, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Automation Coming Soon',
              style: AppText.heading2.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Stay tuned for new automation features.',
              style: AppText.bodyText.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
