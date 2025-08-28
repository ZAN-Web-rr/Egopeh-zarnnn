import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/text.dart';

/// Multi-purpose VerificationScreen
/// Expects Route arguments:
///  { 'phone': '+234...'(String), 'mode': 'signup'|'reset' (String) }
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  String? _verificationId;
  String _phone = '';
  String _mode = 'signup'; // default

  @override
  void initState() {
    super.initState();

    // Read args and start verification after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _phone = args['phone'] as String? ?? '';
        _mode = args['mode'] as String? ?? 'signup';
      }
      if (_phone.isEmpty) {
        // Defensive: if no phone provided, pop back
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No phone number provided')));
        Navigator.of(context).pop();
        return;
      }
      _verifyPhoneNumber(_phone);
    });

    // auto-advance on input
    for (int i = 0; i < _focusNodes.length - 1; i++) {
      _focusNodes[i].addListener(() {
        if (!_focusNodes[i].hasFocus && _otpControllers[i].text.isNotEmpty) {
          FocusScope.of(context).requestFocus(_focusNodes[i + 1]);
        }
      });
    }
  }

  @override
  void dispose() {
    for (var c in _otpControllers) c.dispose();
    for (var n in _focusNodes) n.dispose();
    super.dispose();
  }

  void _verifyPhoneNumber(String phone) {
    setState(() {
      _verificationId = null;
    });

    FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Called in some cases automatically - reuse same handler
        await _signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Verification failed: ${e.message}')));
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _verificationId = verificationId;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP sent')));
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = cred.user;
      if (user == null) throw Exception('No user returned');

      if (_mode == 'reset') {
        // For password reset: navigate to new password screen (keeps user signed-in)
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => NewPasswordScreen(),
        ));
        return;
      }

      // signup/default: navigate to the success / dashboard route
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/success');
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _submitOtp() {
    if (_verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No verification in progress')));
      return;
    }
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the 6-digit code')));
      return;
    }
    final cred = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: code);
    _signInWithCredential(cred);
  }

  @override
  Widget build(BuildContext context) {
    final displayPhone = _phone.isNotEmpty ? _phone : '(hidden number)';
    final title = _mode == 'reset' ? 'Verify to Reset Password' : 'Verify Your Phone';

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset('assets/images/new.png', height: 60),
              const SizedBox(height: 40),
              Text(title, style: AppText.heading2.copyWith(color: AppColors.black)),
              const SizedBox(height: 8),
              Text('Enter the 6-digit code sent to $displayPhone', style: AppText.bodyText.copyWith(color: AppColors.black)),
              const SizedBox(height: 32),

              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 48,
                      child: TextFormField(
                        controller: _otpControllers[index],
                        focusNode: _focusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0xFFF0F4F8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDAE9F8))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDAE9F8))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.blue, width: 2)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            // auto advance
                            if (index < 5) FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
                          } else {
                            // if empty and not first, go back
                            if (index > 0) FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
                          }
                        },
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 32),

              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(32), gradient: AppColors.splashGradient),
                child: ElevatedButton(
                  onPressed: _isLoading || _verificationId == null ? null : _submitOtp,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32))),
                  child: SizedBox(width: double.infinity, child: Center(child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text('Verify', style: AppText.subtitle1.copyWith(color: AppColors.white)))),
                ),
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Didn't receive code? ", style: AppText.bodyText.copyWith(color: AppColors.black)),
                  GestureDetector(
                    onTap: () {
                      // resend
                      _verifyPhoneNumber(_phone);
                    },
                    child: Text('Resend', style: AppText.bodyText.copyWith(color: AppColors.blue, decoration: TextDecoration.underline)),
                  )
                ],
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen that lets the user set a new password after OTP verification (used in 'reset' mode).
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({Key? key}) : super(key: key);

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitNewPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final newPassword = _passwordCtrl.text.trim();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No signed-in user. OTP verification required.');

      await user.updatePassword(newPassword);

      // Optionally refresh token or sign out to force re-login
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated — please log in with your new password.')));
      // go to login screen
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Failed to update password')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Set New Password', style: AppText.heading2.copyWith(color: AppColors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 20),
            Text('Choose a secure password', style: AppText.heading2.copyWith(color: AppColors.black)),
            const SizedBox(height: 12),
            Text('Password must be at least 6 characters.', style: AppText.bodyText.copyWith(color: AppColors.black)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: InputDecoration(hintText: 'New password', filled: true, fillColor: const Color(0xFFF0F4F8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Password required';
                if (v.trim().length < 6) return 'Minimum 6 characters';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: InputDecoration(hintText: 'Confirm password', filled: true, fillColor: const Color(0xFFF0F4F8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Confirm password';
                if (v.trim() != _passwordCtrl.text.trim()) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(32), gradient: AppColors.splashGradient),
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitNewPassword,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32))),
                child: SizedBox(width: double.infinity, child: Center(child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : Text('Set Password', style: AppText.subtitle1.copyWith(color: AppColors.white)))),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
