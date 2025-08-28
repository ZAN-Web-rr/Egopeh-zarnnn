import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/text.dart';
import '../services/authService.dart';

class RoleScreen extends StatefulWidget {
  const RoleScreen({Key? key}) : super(key: key);

  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  final AuthService _authService = AuthService();
  String? _selectedRole;
  bool _isSaving = false;

  Future<void> _next() async {
    if (_selectedRole == null) return;
    setState(() => _isSaving = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      await _authService.saveRole(uid, _selectedRole!);
      Navigator.pushReplacementNamed(context, '/dashboard');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save role: ${e.toString()}')),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = [
      {'icon': Icons.account_balance, 'label': 'Finance'},
      {'icon': Icons.show_chart, 'label': 'Sales'},
      {'icon': Icons.person_outline, 'label': 'Customer Access'},
      {'icon': Icons.code, 'label': 'Developer'},
    ];

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              // Top bar with logo only (removed arrow)
              Row(
                children: [
                  Image.asset('assets/images/new.png', height: 60),
                  const SizedBox(width: 8),
                ],
              ),
              const SizedBox(height: 32),

              // Heading
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'What is your role?',
                  style: AppText.heading2.copyWith(color: AppColors.black),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Understanding your role will help us set up your first scheduling link.',
                  style: AppText.bodyText,
                ),
              ),
              const SizedBox(height: 32),

              // Role options inside a row
              Row(
                children: [
                  Expanded(
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
                        children: roles.map((r) {
                          final label = r['label'] as String;
                          final icon = r['icon'] as IconData;
                          final selected = _selectedRole == label;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _OptionButton(
                              icon: icon,
                              label: label,
                              selected: selected,
                              onTap: () => setState(() => _selectedRole = label),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 124), // space between row and buttons

              // Bottom navigation with gradient Next
              SafeArea(
                top: false,
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: AppColors.blue),
                      label: Text('Back', style: AppText.bodyText.copyWith(color: AppColors.blue)),
                    ),
                    const Spacer(),
                    Container(
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
                        onPressed: (_selectedRole != null && !_isSaving) ? _next : null,
                        style: ElevatedButton.styleFrom(
                          iconColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                          backgroundColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : Text('Next', style: AppText.subtitle1.copyWith(color: AppColors.white)),
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
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        minimumSize: const Size.fromHeight(56),
        backgroundColor: selected ? AppColors.blue.withOpacity(0.1) : AppColors.white,
        side: BorderSide(color: selected ? AppColors.blue : AppColors.black.withOpacity(0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(icon, color: selected ? AppColors.blue : AppColors.black.withOpacity(0.3)),
          const SizedBox(width: 12),
          Text(label, style: AppText.bodyText.copyWith(color: AppColors.black)),
        ],
      ),
    );
  }
}
