import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../constants/colors.dart';
import '../constants/text.dart';
import '../services/authService.dart';

class UserInfoScreen extends StatefulWidget {
  const UserInfoScreen({super.key});

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  String _fullPhone = '';
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _agreeToTerms = false;
  bool _is12HourFormat = true;
  bool _isLoading = false;
  final AuthService _authService = AuthService();

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate() || !_agreeToTerms) return;

    setState(() => _isLoading = true);

    // receive args from signup
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final signupMethod = args['signupMethod'] as String; // 'email' or 'google'
    final email         = args['email'] as String;
    final initialName   = args['displayName'] as String?;
    late String userId;

    try {
      if (signupMethod == 'email') {
        // actually create user
        final cred = await _authService.signupWithEmail(
          email,
          passwordController.text.trim(),
        );
        userId = cred.user!.uid;
      } else {
        // google user already signed in
        userId = FirebaseAuth.instance.currentUser!.uid;
      }

      // chosen display name
      final chosenName = nameController.text.trim().isNotEmpty
          ? nameController.text.trim()
          : (initialName ?? '');

      // update FirebaseAuth profile
      // ...
// update FirebaseAuth profile
      await _authService.updateProfile(displayName: chosenName);

// save user info in Firestore
      await _authService.saveUserInfo(
        uid: userId,
        name: chosenName,
        email: email,
        phone: _fullPhone,
        is12Hour: _is12HourFormat,
      );

// navigate to verification
      Navigator.pushNamed(
        context,
        '/verification',
        arguments: {
          'userId': userId,
          'phone':  _fullPhone,
        },
      );

    } catch (e, st) {
      debugPrint('UserInfo submission error: $e');
      debugPrintStack(stackTrace: st);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit info: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset('assets/images/new.png', height: 60),
                const SizedBox(height: 20),
                Text('Setup Your Profile', style: AppText.heading2.copyWith(color: AppColors.black)),
                const SizedBox(height: 8),
                Text("Let's Finish Your Journey!", style: AppText.bodyText.copyWith(color: AppColors.black)),
                const SizedBox(height: 32),

                // Full Name
                Text('Full Name', style: AppText.subtitle2.copyWith(color: AppColors.black)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: nameController,
                  decoration: _inputDecoration('John Doe'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter full name' : null,
                ),
                const SizedBox(height: 24),

                // Phone
                Text('Phone Number', style: AppText.subtitle2.copyWith(color: AppColors.black)),
                const SizedBox(height: 6),
                IntlPhoneField(
                  decoration: _inputDecoration('Phone Number'),
                  initialCountryCode: 'NG',
                  onChanged: (p) => _fullPhone = p.completeNumber,
                  validator: (v) => (v == null || v.number.isEmpty) ? 'Enter phone' : null,
                ),
                const SizedBox(height: 24),

                // Password
                Text('Password', style: AppText.subtitle2.copyWith(color: AppColors.black)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: passwordController,
                  obscureText: !_isPasswordVisible,
                  decoration: _inputDecoration(
                    '********',
                    suffixIcon: IconButton(
                      icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.black.withOpacity(0.4)),
                      onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6) ? 'Min 6 chars' : null,
                ),
                const SizedBox(height: 24),

                // Confirm
                Text('Confirm Password', style: AppText.subtitle2.copyWith(color: AppColors.black)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: confirmPasswordController,
                  obscureText: !_isConfirmPasswordVisible,
                  decoration: _inputDecoration(
                    '********',
                    suffixIcon: IconButton(
                      icon: Icon(_isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.black.withOpacity(0.4)),
                      onPressed: () => setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
                    ),
                  ),
                  validator: (v) => v != passwordController.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 24),

                // Terms
                CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.blue,
                  contentPadding: EdgeInsets.zero,
                  value: _agreeToTerms,
                  onChanged: (v) => setState(() => _agreeToTerms = v!),
                  title: RichText(
                    text: TextSpan(
                      text: 'I agree to the ',
                      style: AppText.bodyText.copyWith(color: AppColors.black),
                      children: [ TextSpan(
                        text: 'Terms & Conditions',
                        style: AppText.bodyText.copyWith(
                          color: AppColors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Time format
                Text('Time Format', style: AppText.subtitle2.copyWith(color: AppColors.black)),
                RadioListTile<bool>(
                  title: Text('12-hour', style: AppText.bodyText.copyWith(color: AppColors.black)),
                  value: true,
                  groupValue: _is12HourFormat,
                  onChanged: (v) => setState(() => _is12HourFormat = v!),
                ),
                RadioListTile<bool>(
                  title: Text('24-hour', style: AppText.bodyText.copyWith(color: AppColors.black)),
                  value: false,
                  groupValue: _is12HourFormat,
                  onChanged: (v) => setState(() => _is12HourFormat = v!),
                ),
                const SizedBox(height: 40),

                // Submit
                Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.splashGradient,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: ElevatedButton(
                    onPressed: !_agreeToTerms || _isLoading ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text('Submit', style: AppText.subtitle1.copyWith(color: AppColors.white)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.bodyText.copyWith(color: AppColors.black.withOpacity(0.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      suffixIcon: suffixIcon,
    );
  }
}
