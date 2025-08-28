import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/text.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _onboardingData = [
    {
      'image': 'assets/images/illustration1.png',
      'title': 'Smarter Scheduling Starts Here',
      'subtitle': 'Get a clear view of your day, automate your routine, and manage your time with ease using your smart AI-powered planner.',
    },
    {
      'image': 'assets/images/illustration2.png',
      'title': 'Stay Focused & In Control',
      'subtitle': ' Worried about a meeting? Use built-in focus tools to Stay in control by automating messages for when you’re away, distraction-free.',
    },
    {
      'image': 'assets/images/illustration3.png',
      'title': 'Just Say It – We’ll Handle It',
      'subtitle': 'Use voice commands to quickly add events, set reminders, and control your day—hands-free and hassle-free.  ',
    },
  ];

  void _nextPage() {
    if (_currentPage < _onboardingData.length - 1) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut
      );
    } else {
      Navigator.pushReplacementNamed(context, '/signup');
    }
  }

  void _skip() {
    Navigator.pushReplacementNamed(context, '/signup');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _onboardingData.length,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
              },
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Skip button
                      Align(
                        alignment: Alignment.topRight,
                        child: TextButton(
                          onPressed: _skip,
                          child: Text(
                            'Skip',
                            style: AppText.subtitle2.copyWith(
                                color: AppColors.black,
                                fontWeight: FontWeight.w400
                            ),
                          ),
                        ),
                      ),

                      // Illustration
                      const SizedBox(height: 40),
                      Image.asset(
                        _onboardingData[index]['image']!,
                        height: 300,
                      ),

                      // Title

                      Text(
                        _onboardingData[index]['title']!,
                        textAlign: TextAlign.center,
                        style: AppText.heading2.copyWith(
                          color: AppColors.black,
                          fontSize: 24,
                        ),
                      ),

                      // Subtitle
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          _onboardingData[index]['subtitle']!,
                          textAlign: TextAlign.center,
                          style: AppText.bodyText.copyWith(
                            color: AppColors.black,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Page Indicators with Gradient
            Positioned(
              bottom: 150,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _onboardingData.length,
                      (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 8 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: _currentPage == index
                          ? AppColors.splashGradient
                          : null,
                      color: _currentPage != index
                          ? const Color(0xFFD9D9D9)
                          : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),

            // Full-width Gradient Button
            Positioned(
              bottom: 40,
              left: 24,
              right: 24,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.splashGradient,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(40),
                    ),
                  ),
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    child: Text(
                      _currentPage == _onboardingData.length - 1
                          ? 'Get Started'
                          : 'Continue',
                      style: AppText.subtitle1.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}