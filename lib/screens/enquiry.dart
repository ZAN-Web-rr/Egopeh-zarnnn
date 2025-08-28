import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/text.dart';
import '../services/authService.dart';

class EnquiryScreen extends StatefulWidget {
  const EnquiryScreen({Key? key}) : super(key: key);

  @override
  State<EnquiryScreen> createState() => _EnquiryScreenState();
}

class _EnquiryScreenState extends State<EnquiryScreen> {
  final AuthService _authService = AuthService();
  bool _onMyOwn = false;
  bool _withMyTeam = false;
  bool _isSaving = false;
  String _firstName = '';

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      String name = '';
      if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
        name = user.displayName!;
      } else if (user.email != null && user.email!.isNotEmpty) {
        name = user.email!.split('@').first;
      }
      if (name.isNotEmpty) {
        _firstName = name.split(' ').first;
      }
    }
  }

  Future<void> _next() async {
    setState(() => _isSaving = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not signed in')),
      );
      setState(() => _isSaving = false);
      return;
    }

    final usage = _onMyOwn ? 'on_my_own' : 'with_team';

    try {
      await _authService.saveEnquiry(user.uid, usage);
      Navigator.pushReplacementNamed(context, '/role');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: ${e.toString()}')),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final welcomeText = _firstName.isNotEmpty
        ? 'Welcome $_firstName,\nHow do you plan to use Zarn?'
        : 'How do you plan to use Zarn?';

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              Row(
                children: [
                  Image.asset('assets/images/new.png', height: 60),
                  const SizedBox(width: 8),
                ],
              ),
              const SizedBox(height: 32),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  welcomeText,
                  style: AppText.heading2.copyWith(color: AppColors.black),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Your response will help us tailor your experience to your needs.',
                  style: AppText.bodyText.copyWith(color: AppColors.black),
                ),
              ),
              const SizedBox(height: 42),

              Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _OptionButton(
                              icon: Icons.person_outline,
                              label: 'On my Own',
                              selected: _onMyOwn,
                              onTap: () => setState(() {
                                _onMyOwn = true;
                                _withMyTeam = false;
                              }),
                            ),
                            const SizedBox(height: 16),
                            _OptionButton(
                              icon: Icons.people,
                              label: 'With my Team',
                              selected: _withMyTeam,
                              onTap: () => setState(() {
                                _withMyTeam = true;
                                _onMyOwn = false;
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 150),
              SafeArea(
                top: false,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: AppColors.splashGradient,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: (_onMyOwn || _withMyTeam) && !_isSaving
                        ? _next
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            'Next',
                            style: AppText.subtitle1.copyWith(color: AppColors.white),
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
}

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        backgroundColor: selected ? AppColors.blue.withOpacity(0.1) : AppColors.white,
        side: BorderSide(color: selected ? AppColors.blue : AppColors.black.withOpacity(0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28, color: selected ? AppColors.blue : AppColors.black.withOpacity(0.3)),
          const SizedBox(width: 16),
          Text(label, style: AppText.bodyText.copyWith(color: AppColors.black)),
        ],
      ),
    );
  }
}
