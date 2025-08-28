import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/colors.dart';

class SuccessScreen extends StatefulWidget {
  final String nextRoute;
  const SuccessScreen({Key? key, required this.nextRoute}) : super(key: key);

  @override
  _SuccessScreenState createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate after 5 seconds
    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacementNamed(context, widget.nextRoute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/sucess.png', // replace with your success image
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 24),
            Text(
              'Account Created Successfully!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.black,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
