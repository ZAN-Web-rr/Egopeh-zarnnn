import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../constants/colors.dart';
import '../constants/text.dart';

// Add to pubspec.yaml:
// dependencies:
//   flutter_localizations:
//     sdk: flutter
//   intl: ^0.17.0

class LanguageScreen extends StatefulWidget {
  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;

  const LanguageScreen({
    Key? key,
    required this.currentLocale,
    required this.onLocaleChanged,
  }) : super(key: key);

  @override
  _LanguageScreenState createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  late Locale _selected;

  final _languages = const [
    Locale('en', 'US'),
    Locale('es', 'ES'),
    Locale('fr', 'FR'),
    Locale('de', 'DE'),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.currentLocale;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(color: AppColors.black),
        title: Text('Language', style: AppText.heading2),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Select your preferred language',
              style: AppText.bodyText.copyWith(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          ..._languages.map((loc) {
            final name = LocLanguage.of(loc.languageCode) ?? loc.languageCode;
            return RadioListTile<Locale>(
              value: loc,
              groupValue: _selected,
              title: Text(name, style: AppText.bodyText),
              onChanged: (locale) {
                if (locale == null) return;
                setState(() => _selected = locale);
                widget.onLocaleChanged(locale);
              },
            );
          }).toList(),
        ],
      ),
    );
  }
}

class LocLanguage {
  static String? of(String code) {
    switch (code) {
      case 'en': return 'English';
      case 'es': return 'Español';
      case 'fr': return 'Français';
      case 'de': return 'Deutsch';
      default: return null;
    }
  }
}

// In your MaterialApp:
// MaterialApp(
//   localizationsDelegates: [
//     GlobalMaterialLocalizations.delegate,
//     GlobalWidgetsLocalizations.delegate,
//     GlobalCupertinoLocalizations.delegate,
//   ],
//   supportedLocales: [
//     Locale('en', 'US'),
//     Locale('es', 'ES'),
//     Locale('fr', 'FR'),
//     Locale('de', 'DE'),
//   ],
//   locale: _currentLocale,
//   onLocaleChanged: (loc) => setState(() => _currentLocale = loc),
// )
