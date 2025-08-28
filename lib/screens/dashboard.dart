import 'package:flutter/material.dart';
import 'package:zarn/screens/wakapage.dart';
import '../constants/colors.dart';
import '../constants/text.dart';
import 'automatiopage.dart';
import 'calendarpage.dart';
import 'focuspage.dart';
import 'homepage.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomePage(),
    const CalendarPage(),
    const WakaPage(),
    const FocusPage(),
    const AutomationPage(),
  ];

  void _onTap(int idx) {
    setState(() => _currentIndex = idx);
  }

  @override
  Widget build(BuildContext context) {
    // If AI page selected, show it full screen without nav
    if (_currentIndex == 2) {
      return _pages[2];
    }

    const fabSize = 56.0;
    return Scaffold(
      backgroundColor: AppColors.white,
      body: _pages[_currentIndex],
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Container(
        width: fabSize,
        height: fabSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.splashGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () => _onTap(2),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.mic, size: 28, color: Colors.white),
        ),
      ),
      bottomNavigationBar: Container(
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.white,
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(child: _NavItem(icon: Icons.home, label: 'Home', index: 0, current: _currentIndex, onTap: _onTap)),
            Expanded(child: _NavItem(icon: Icons.calendar_today, label: 'Calendar', index: 1, current: _currentIndex, onTap: _onTap)),
            Expanded(child: const SizedBox()),
            Expanded(child: _NavItem(icon: Icons.timer, label: 'Focus', index: 3, current: _currentIndex, onTap: _onTap)),
            Expanded(child: _NavItem(icon: Icons.autorenew, label: 'Automation', index: 4, current: _currentIndex, onTap: _onTap)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int current;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == current;
    return GestureDetector(
      onTap: () => onTap(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: isActive ? AppColors.blue : AppColors.black.withOpacity(0.6)),
          const SizedBox(height: 4),
          Text(label, style: AppText.subtitle2.copyWith(color: isActive ? AppColors.blue : AppColors.black.withOpacity(0.6), fontSize: 10)),
        ],
      ),
    );
  }
}
