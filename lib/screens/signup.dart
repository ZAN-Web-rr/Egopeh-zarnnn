import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/text.dart';
import '../services/authService.dart';

enum _SignupView { form, terms, privacy }

/// SignupScreen allows user to enter their email and sign up using AuthService
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _signupError;

  // NEW: which view to show
  _SignupView _view = _SignupView.form;

  /// Full text extracted from uploaded PDFs (Privacy Policy and Terms of Use).
  /// Source: the PDFs you uploaded. :contentReference[oaicite:2]{index=2} :contentReference[oaicite:3]{index=3}
  final String _privacyText = '''
Zarn – Privacy Policy
Last Updated: 8/21/2025

1. Introduction
This Privacy Policy explains how Zanite, Inc. (“we,” “our,” or “us”) collects, uses, and protects information when you use Zarn.

2. Information We Collect
• Account Data: Name, email, login credentials.
• Usage Data: Interactions, preferences, logs.
• Content Data: Text, voice, or other inputs.
• Technical Data: Device identifiers, IP, crash logs.
• Cookies/Tracking: For functionality, analytics, and marketing (with consent where required).

3. How We Use Data
• To provide and improve Zarn.
• To personalize user experience.
• To ensure security and prevent misuse.
• To comply with law.

GDPR Legal Bases
• Contractual necessity
• Consent
• Legitimate interests
• Legal obligations

4. Sharing of Data
• With service providers (cloud, analytics, payments).
• With legal authorities if required.
• During business transfers (e.g., merger or acquisition).

We do not sell personal data.

5. AI and Data Usage
• Inputs and outputs may be stored for improvement.
• Sensitive personal data should not be submitted.
• Under GDPR: no legally binding automated decisions without human oversight.
• Under CCPA: we do not sell data; you can opt out of sharing.

6. Security
We use reasonable measures to protect data, though no system is 100% secure.

7. Retention
Data is retained as long as needed for service delivery or legal compliance, then securely deleted/anonymized.

8. Children
Not directed to children under 13. We do not knowingly collect data from them.

9. International Data Transfers
• Data may be processed in the U.S.
• For EEA/UK/Switzerland, transfers rely on Standard Contractual Clauses (SCCs).

10. User Rights

GDPR (EU/UK)
• Access, correct, delete data
• Restrict or object to processing
• Data portability
• Withdraw consent
• File a complaint with Data Protection Authority

CCPA (California)
• Right to know
• Right to delete
• Right to opt out of data sharing
• Right to non-discrimination

Requests can be made via [Insert Email].

11. Cookies Policy
We use cookies for:
• Essential features
• Analytics
• Marketing (with consent where applicable)

Users can control cookies via browser settings.

12. Data Protection Officer (DPO)
For GDPR, contact our DPO:
support@zarnite.com

13. Updates
We may update this Policy. Users will be notified of significant changes.

14. Contact
Zanite, Inc.
1111B S Governors Ave STE 21630 Dover, DE, 19904 US
support@zarnite.com
''';

  final String _termsText = '''
Zarn – Terms of Use
Last Updated: 8/21/2025

1. Introduction
Welcome to Zarn, an AI-powered productivity application developed by Zanite, Inc., a Delaware corporation (“Zarnite,” “we,” “our,” or “us”).
By using Zarn, you (“you,” “user”) agree to these Terms of Use (“Terms”). If you do not agree, you may not use the app.

2. Eligibility
• You must be at least 13 years old (or the minimum age of digital consent in your jurisdiction) to use Zarn.
• If used on behalf of an organization, you represent you have authority to bind that organization.

3. Services Provided
Zarn provides AI-driven productivity and automation tools. Features may evolve. Zarn is not a substitute for professional advice (legal, medical, financial, or otherwise).

4. Accounts
• You may need an account to access certain features.
• You’re responsible for your login credentials and activities under your account.

5. Acceptable Use
You agree not to:
• Use Zarn unlawfully or abusively.
• Attempt to reverse engineer, copy, or exploit our models or tech.
• Upload harmful, infringing, or offensive content.
• Interfere with Zarn’s operation or security.

6. Intellectual Property
• Zarnite owns all rights to its software, trademarks, and platform.
• You retain rights to your inputs but grant Zarnite a worldwide, royalty-free license to process and use them to provide and improve services.

7. AI Outputs
• AI outputs may be inaccurate or incomplete.
• Zarnite is not responsible for reliance on outputs.

8. Termination
We may suspend or terminate your account for violations. You may stop using Zarn anytime.

9. Disclaimers
Zarn is provided “as is” without warranties. We do not guarantee uptime, accuracy, or suitability for purpose.

10. Limitation of Liability
• Zarnite is not liable for indirect, incidental, or consequential damages.
• Our total liability will not exceed what you paid us in the last 12 months, if any.

11. Indemnification
You agree to indemnify and hold harmless Zarnite, its officers, employees, and affiliates from claims or damages arising from your use of Zarn.

12. Governing Law & Dispute Resolution
• Governed by Delaware law.
• Disputes resolved via binding arbitration in Delaware under AAA rules.
• No class actions permitted.
• EU users may use Online Dispute Resolution (ODR).

13. Updates
We may update these Terms. Continued use means acceptance.

14. Contact
Zarnite, Inc.
1111B S Governors Ave STE 21630 Dover, DE, 19904 US
support@zarnite.com
''';

  /// Handles email signup by forwarding email to UserInfoScreen
  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _signupError = null;
    });

    try {
      final email = emailController.text.trim();

      // You can check for existence here by attempting to create a user with a dummy password
      final existingUser = await _authService.checkIfEmailInUse(email);
      if (existingUser) {
        setState(() {
          _signupError = 'Email is already in use';
        });
        return;
      }

      Navigator.pushNamed(
        context,
        '/userinfo',
        arguments: {'email': email, 'signupMethod': 'email'},
      );
    } catch (e, st) {
      debugPrint('Signup error: $e');
      debugPrintStack(stackTrace: st);
      setState(() {
        _signupError = 'Signup failed. Try again later.';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Handles Google Sign-In and forwards user info to UserInfoScreen
  Future<void> _handleGoogleSignup() async {
    setState(() => _isLoading = true);
    try {
      // 1. Force logout of any existing Google session
      await _authService.signOutFromGoogle();

      // 2. Sign in and force account selection
      final cred = await _authService.signInWithGoogle(forcePrompt: true);
      final user = cred.user;
      if (user == null) throw Exception('Google sign-in returned no user');

      final email = user.email!.trim();

      // 3. Check if that email is already in use
      final alreadyUsed = await _authService.checkIfEmailInUse(email);
      if (alreadyUsed) {
        // if it's already registered, show the same error and abort
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email is already in use')),
        );
        // optional: sign out the just‐created Firebase session
        await _authService.signOutFromGoogle();
        return;
      }

      // 4. Otherwise, proceed to your user info screen
      Navigator.pushNamed(
        context,
        '/userinfo',
        arguments: {
          'email': email,
          'displayName': user.displayName,
          'signupMethod': 'google',
        },
      );
    } catch (e, st) {
      debugPrint('Google signup error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google signup failed: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showTerms() => setState(() => _view = _SignupView.terms);
  void _showPrivacy() => setState(() => _view = _SignupView.privacy);
  void _showForm() => setState(() => _view = _SignupView.form);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      // If we're showing policy views, render them inside the same scaffold body
      body: _view == _SignupView.form ? _buildFormView(context) : _buildPolicyView(context),
    );
  }

  Widget _buildFormView(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 60),
            Image.asset('assets/images/new.png', height: 60),
            const SizedBox(height: 40),
            Text(
              'Create Your Account',
              style: AppText.heading2.copyWith(color: AppColors.black, fontSize: 24),
            ),
            const SizedBox(height: 12),
            Text(
              "Let's Begin Your Journey!",
              style: AppText.bodyText.copyWith(color: AppColors.black, fontSize: 16),
            ),
            const SizedBox(height: 32),

            // Email field with validation
            TextFormField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'example@gmail.com',
                filled: true,
                fillColor: const Color(0xFFF0F4F8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(32)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Field is required';
                }
                const pattern = r"^[^@\s]+@[^@\s]+\.[^@\s]+$";
                if (!RegExp(pattern).hasMatch(value.trim())) {
                  return 'Enter a valid email';
                }
                return null;
              },
              enabled: !_isLoading,
            ),
            const SizedBox(height: 24),

            // Signup button
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.splashGradient,
                borderRadius: BorderRadius.circular(32),
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSignup,
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
                        ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                        : Text('Signup', style: AppText.subtitle1.copyWith(color: AppColors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
            if (_signupError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _signupError!,
                  style: TextStyle(color: Colors.red, fontSize: 14),
                ),
              ),

            const SizedBox(height: 12),

            // NEW: small consent text with tappable Terms & Privacy links (keeps UI compact)
            Center(
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  text: 'By signing up you agree to our ',
                  style: AppText.bodyText.copyWith(color: AppColors.black, fontSize: 13),
                  children: [
                    TextSpan(
                      text: 'Terms of Use',
                      style: AppText.bodyText.copyWith(color: AppColors.blue, fontWeight: FontWeight.w600),
                      recognizer: TapGestureRecognizer()..onTap = _showTerms,
                    ),
                    TextSpan(text: ' and ', style: AppText.bodyText.copyWith(color: AppColors.black, fontSize: 13)),
                    TextSpan(
                      text: 'Privacy Policy.',
                      style: AppText.bodyText.copyWith(color: AppColors.blue, fontWeight: FontWeight.w600),
                      recognizer: TapGestureRecognizer()..onTap = _showPrivacy,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // OR divider
            Row(
              children: [
                const Expanded(child: Divider(color: Color(0xFFD9D9D9))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text('Or Signup With', style: AppText.bodyText.copyWith(color: AppColors.black)),
                ),
                const Expanded(child: Divider(color: Color(0xFFD9D9D9))),
              ],
            ),
            const SizedBox(height: 24),

            // Google signup button centered
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSocialButton(
                  icon: 'assets/images/google.png',
                  label: 'Google',
                  onTap: _isLoading ? () {} : _handleGoogleSignup,
                ),
              ],
            ),
            const SizedBox(height: 34),

            // Navigate to login
            Center(
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: RichText(
                  text: TextSpan(
                    text: "Already have an account? ",
                    style: AppText.bodyText.copyWith(color: AppColors.black),
                    children: [
                      TextSpan(text: 'Login', style: AppText.bodyText.copyWith(color: AppColors.blue, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Policy / Terms view (shared)
  Widget _buildPolicyView(BuildContext context) {
    final bool isTerms = _view == _SignupView.terms;
    final String title = isTerms ? 'Terms of Use' : 'Privacy Policy';
    final String content = isTerms ? _termsText : _privacyText;

    return SafeArea(
      child: Column(
        children: [
          // header with back button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: _showForm,
                  icon: const Icon(Icons.arrow_back, size: 24),
                ),
                const SizedBox(width: 8),
                Text(title, style: AppText.heading2.copyWith(fontSize: 20)),
                const Spacer(),
                // lightweight "Close" affordance
                TextButton(
                  onPressed: _showForm,
                  child: Text('Close', style: AppText.bodyText.copyWith(color: AppColors.blue)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE6E6E6)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Document header
                  Text(
                    title,
                    style: AppText.heading2.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 10),
                  // Full text content
                  SelectableText(content, style: AppText.bodyText.copyWith(color: AppColors.black, fontSize: 14)),
                  const SizedBox(height: 18),
                  Text(
                    'Full documents sourced from uploaded PDFs.',
                    style: AppText.bodyText.copyWith(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a social login button (Google, etc.)
  Widget _buildSocialButton({required String icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(icon, height: 24, width: 24),
            const SizedBox(width: 8),
            Text(label, style: AppText.subtitle2.copyWith(color: AppColors.black, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
