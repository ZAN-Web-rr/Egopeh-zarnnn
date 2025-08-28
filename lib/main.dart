import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // added
import 'package:google_fonts/google_fonts.dart';
// add this import:
import 'package:flutter_localizations/flutter_localizations.dart';

// ---------- ADDED: import the Voice AI screen you created ----------
// Make sure this file exists at lib/screens/voice_ai_screen.dart
// and that the class is named `VoiceAiScreen` with a constructor:
//   const VoiceAiScreen({ Key? key, required String apiBaseUrl, String? initialSessionId })
// If you placed the file elsewhere, update this import path accordingly.
import 'screens/forgot_password_screen.dart';
import 'screens/voice_ai.dart';

import 'constants/colors.dart';
import 'screens/splashScreen.dart';
import 'screens/onboarding.dart';
import 'screens/signup.dart';
import 'screens/login.dart';               // import LoginScreen
import 'screens/userinfo.dart';
import 'screens/verification.dart';
import 'screens/success.dart';
import 'screens/enquiry.dart';
import 'screens/role.dart';
import 'screens/dashboard.dart';
import 'screens/task.dart';
import 'screens/event.dart';
import 'screens/mail.dart';
import 'screens/notification.dart';
import 'screens/settings.dart';
import 'screens/note.dart';
import 'screens/language.dart';  // import your LanguageScreen
import 'screens/wakaovelay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // added
  await Firebase.initializeApp();           // added
  runApp(const ZarnApp());
}

// CHANGED: StatefulWidget so we can call setState when locale changes
class ZarnApp extends StatefulWidget {
  const ZarnApp({Key? key}) : super(key: key);

  @override
  _ZarnAppState createState() => _ZarnAppState();
}

class _ZarnAppState extends State<ZarnApp> {
  // ADDED: keep track of the selected locale
  Locale _currentLocale = const Locale('en', 'US');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zarn Tool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: AppColors.splashGradient.colors.first,
        scaffoldBackgroundColor: AppColors.white,
        fontFamily: GoogleFonts.poppins().fontFamily,
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.blue,
        ).copyWith(
          primary: AppColors.splashGradient.colors.first,
          secondary: AppColors.blue,
        ),
      ),

      // CHANGED: add localization delegates
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('es', 'ES'),
        Locale('fr', 'FR'),
        Locale('de', 'DE'),
      ],
      // CHANGED: wire up the current locale
      locale: _currentLocale,

      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        //'/forgotPassword': (context) =>  ForgotPasswordScreen(),
        //  '/resetVerification': (context) =>  ResetVerificationScreen(),
        '/userinfo': (context) => const UserInfoScreen(),
        '/verification': (context) => const VerificationScreen(),
        '/success': (context) => const SuccessScreen(nextRoute: '/enquiry'),
        '/enquiry': (context) => const EnquiryScreen(),
        '/role': (context) => const RoleScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/home':       (ctx) => const DashboardScreen(),
        '/task': (context) => const CreateTaskScreen(),
        '/event': (context) => const CreateEventScreen(),
        '/mail': (context) => const CreateEmailScreen(),
        // '/wakaoverlay': (ctx)=>  const WakaOverlayScreen(initialPrompt: '',),
        '/notifications': (context) => const NotificationsScreen(),
        '/settings': (context) => SettingsScreen(
          currentLocale: _currentLocale,
          onLocaleChanged: (loc) {
            setState(() {
              _currentLocale = loc;
            });
          },
        ),
        '/voice-to-text': (context) => const NoteTakingScreen(),
        '/forgotPassword': (context) => const ForgotPasswordScreen(),
        '/voice-ai': (context) => const VoiceAiScreen(
          apiBaseUrl:
          'https://voice-live-api.onrender.com', // <-- REPLACE this URL
        ),
      },
    );
  }
}
