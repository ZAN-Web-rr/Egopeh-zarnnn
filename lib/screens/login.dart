import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/text.dart';
import '../services/authService.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
final _formKey = GlobalKey<FormState>();
final TextEditingController emailController = TextEditingController();
final TextEditingController passwordController = TextEditingController();
final AuthService _authService = AuthService();
bool _isLoading = false;

Future<void> _handleLogin() async {
if (!_formKey.currentState!.validate()) return;
setState(() => _isLoading = true);


try {
final email = emailController.text.trim();
final password = passwordController.text;
await _authService.loginWithEmail(email, password);
Navigator.pushReplacementNamed(context, '/dashboard');
} catch (e) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
);
} finally {
setState(() => _isLoading = false);
}


}

Future<void> _handleGoogleLogin() async {
setState(() => _isLoading = true);
try {
// Ensure any previous Google session is signed out to force account picker
await _authService.signOutFromGoogle();
final cred = await _authService.signInWithGoogle(forcePrompt: true);
if (cred.user == null) throw Exception('Google login returned no user');
Navigator.pushReplacementNamed(context, '/dashboard');
} catch (e) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
);
} finally {
setState(() => _isLoading = false);
}
}

@override
Widget build(BuildContext context) {
return Scaffold(
backgroundColor: Colors.white,
resizeToAvoidBottomInset: true,
body: SingleChildScrollView(
padding: const EdgeInsets.all(20),
child: Form(
key: _formKey,
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const SizedBox(height: 60),
Image.asset('assets/images/new\.png', height: 60),
const SizedBox(height: 40),
Text(
'Welcome Back',
style: AppText.heading2.copyWith(color: AppColors.black, fontSize: 24),
),
const SizedBox(height: 12),
Text(
"Let's log you in!",
style: AppText.bodyText.copyWith(color: AppColors.black, fontSize: 16),
),
const SizedBox(height: 32),


// Email field
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
if (value == null || value.trim().isEmpty) return 'Field is required';
const pattern = r"^[^@\s]+@[^@\s]+\.[^@\s]+$";
if (!RegExp(pattern).hasMatch(value.trim())) return 'Enter a valid email';
return null;
},
enabled: !_isLoading,
),
const SizedBox(height: 16),

// Password field
TextFormField(
controller: passwordController,
obscureText: true,
decoration: InputDecoration(
hintText: 'Password',
filled: true,
fillColor: const Color(0xFFF0F4F8),
border: OutlineInputBorder(borderRadius: BorderRadius.circular(32)),
contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
),
validator: (value) => value == null || value.isEmpty ? 'Password is required' : null,
enabled: !_isLoading,
),

const SizedBox(height: 12),
Align(
alignment: Alignment.centerRight,
child: TextButton(
onPressed: () => Navigator.pushNamed(context, '/forgotPassword'),
child: Text('Forgot Password?', style: AppText.bodyText.copyWith(color: AppColors.blue)),
),
),
const SizedBox(height: 16),

// Login button
Container(
decoration: BoxDecoration(
gradient: AppColors.splashGradient,
borderRadius: BorderRadius.circular(32),
),
child: ElevatedButton(
onPressed: _isLoading ? null : _handleLogin,
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
    : Text('Login', style: AppText.subtitle1.copyWith(color: AppColors.white, fontWeight: FontWeight.w600)),
),
),
),
),
const SizedBox(height: 24),

// OR divider
Row(
children: [
const Expanded(child: Divider(color: Color(0xFFD9D9D9))),
Padding(
padding: const EdgeInsets.symmetric(horizontal: 8.0),
child: Text('Or Login With', style: AppText.bodyText.copyWith(color: AppColors.black)),
),
const Expanded(child: Divider(color: Color(0xFFD9D9D9))),
],
),
const SizedBox(height: 24),

// Google login button
Row(
mainAxisAlignment: MainAxisAlignment.center,
children: [
_buildSocialButton(
icon: 'assets/images/google.png',
label: 'Google',
onTap: _isLoading ? () {} : _handleGoogleLogin,
),
],
),
const SizedBox(height: 34),

// Navigate to signup
Center(
child: TextButton(
onPressed: () => Navigator.pushNamed(context, '/signup'),
child: RichText(
text: TextSpan(
text: "Don't have an account? ",
style: AppText.bodyText.copyWith(color: AppColors.black),
children: [
TextSpan(text: 'Signup', style: AppText.bodyText.copyWith(color: AppColors.blue, fontWeight: FontWeight.w600)),
],
),
),
),
),
],
),
),
),
);


}

Widget _buildSocialButton({
required String icon,
required String label,
required VoidCallback onTap,
}) {
return GestureDetector(
onTap: onTap,
child: Container(
padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
decoration: BoxDecoration(
color: Colors.white,
borderRadius: BorderRadius.circular(40),
boxShadow: [
BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 4, offset: const Offset(0, 2)),
],
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
