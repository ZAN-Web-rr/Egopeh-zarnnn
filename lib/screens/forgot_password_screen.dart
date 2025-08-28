import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/text.dart';
import 'verification.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccess = false;

  /// Try common phone field names in user doc
  String? _extractPhoneFromDocData(Map<String, dynamic> data) {
    final candidates = ['phone', 'phoneNumber', 'phone_number', 'mobile', 'mobileNumber', 'telephone'];
    for (final k in candidates) {
      if (data.containsKey(k) && data[k] != null && data[k].toString().trim().isNotEmpty) {
        return data[k].toString().trim();
      }
    }
    return null;
  }

  Future<void> _startOtpReset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final email = emailController.text.trim();

      // Lookup user doc in Firestore by email
      final firestore = FirebaseFirestore.instance;
      final query = await firestore.collection('users').where('email', isEqualTo: email).limit(1).get();

      if (query.docs.isEmpty) {
        setState(() {
          _isSuccess = false;
          _statusMessage = 'No account found for that email.';
        });
        return;
      }

      final doc = query.docs.first;
      final data = doc.data();
      final phone = _extractPhoneFromDocData(data);

      if (phone == null || phone.isEmpty) {
        setState(() {
          _isSuccess = false;
          _statusMessage = 'No phone number registered for this account. Contact support.';
        });
        return;
      }

      // Optional: normalize phone? Here we assume phone stored with country code.
      // Navigate to verification screen and pass mode = 'reset'
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const VerificationScreen(),
          settings: RouteSettings(
            arguments: {'phone': phone, 'mode': 'reset'},
          ),
        ),
      );

      setState(() {
        _isSuccess = true;
        _statusMessage = 'OTP sent to the phone associated with this email.';
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _statusMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text('Forgot Password', style: AppText.heading2.copyWith(color: AppColors.black)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text(
                'Reset Your Password',
                style: AppText.heading2.copyWith(color: AppColors.black, fontSize: 24),
              ),
              const SizedBox(height: 12),
              Text(
                "Enter the email you registered with. We'll send an OTP to the phone number linked to that account.",
                style: AppText.bodyText.copyWith(color: AppColors.black, fontSize: 16),
              ),
              const SizedBox(height: 32),

              // Email field
              TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'you@example.com',
                  filled: true,
                  fillColor: const Color(0xFFF0F4F8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(32)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Email is required';
                  const pattern = r"^[^@\s]+@[^@\s]+\.[^@\s]+$";
                  if (!RegExp(pattern).hasMatch(value.trim())) return 'Enter a valid email';
                  return null;
                },
                enabled: !_isLoading,
              ),
              const SizedBox(height: 24),

              // Start OTP Button
              Container(
                decoration: BoxDecoration(
                  gradient: AppColors.splashGradient,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _startOtpReset,
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
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Text('Send OTP', style: AppText.subtitle1.copyWith(color: AppColors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Status Message
              if (_statusMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _isSuccess ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(_isSuccess ? Icons.check_circle : Icons.error, color: _isSuccess ? Colors.green : Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(color: _isSuccess ? Colors.green : Colors.red),
                        ),
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
}
