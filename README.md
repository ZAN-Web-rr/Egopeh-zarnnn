# Zarn - Smart Note-Taking App 📝

A comprehensive Flutter application for note-taking with advanced features including PDF export, voice recording, and multi-language support.

## 🚀 Features

- **📝 Rich Note-Taking**: Create and manage notes with rich text editing
- **📄 PDF/DOC Export**: Export notes to PDF and DOC formats
- **🎤 Voice Recording**: Record audio notes with speech-to-text functionality
- **🔐 Phone Verification**: Secure user authentication via phone number
- **🌍 Multi-Language Support**: Internationalization with language switching
- **☁️ Cloud Sync**: Firebase integration for data synchronization
- **📱 Cross-Platform**: Supports Android, iOS, Windows, macOS, Linux, and Web

## 🛠️ Tech Stack

- **Framework**: Flutter 3.x
- **Language**: Dart
- **Backend**: Firebase (Auth, Firestore, Storage)
- **Build System**: Gradle with Kotlin DSL
- **Architecture**: Clean Architecture with Provider/Bloc pattern

## 📋 Prerequisites

Before running this project, ensure you have:

- Flutter SDK (3.0.0 or higher)
- Dart SDK (2.18.0 or higher)
- Android Studio / VS Code with Flutter extensions
- Firebase project setup
- Git

## 🔧 Installation & Setup

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/zarn.git
cd zarn
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Firebase Configuration

#### Android Setup:
1. Create a Firebase project at [Firebase Console](https://console.firebase.google.com)
2. Add an Android app with package name: `com.zarnite.zarn`
3. Download `google-services.json` and place it in `android/app/`
4. Generate SHA1 fingerprint:
   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```
5. Add the SHA1 fingerprint to your Firebase project

#### iOS Setup:
1. Add an iOS app to your Firebase project
2. Download `GoogleService-Info.plist` and place it in `ios/Runner/`

### 4. Environment Configuration
Create these files (they're gitignored for security):

#### `android/app/google-services.json`
```json
{
  "project_info": {
    "project_id": "your-project-id"
    // ... your Firebase configuration
  }
}
```

#### `lib/config/api_keys.dart` (if needed)
```dart
class ApiKeys {
  static const String firebaseApiKey = 'your-api-key';
  // Add other API keys here
}
```

## 🚀 Running the App

### Development Mode
```bash
# Android
flutter run

# iOS
flutter run -d ios

# Web
flutter run -d chrome

# Windows
flutter run -d windows
```

### Production Build
```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release

# Web
flutter build web --release
```

## 📁 Project Structure

```
lib/
├── main.dart                 # App entry point
├── constants/                # App constants and themes
├── screens/                  # UI screens
│   ├── language.dart        # Language selection
│   ├── note.dart           # Note-taking interface
│   └── verification.dart   # Phone verification
└── services/               # Business logic and services
    ├── firebase_service.dart
    ├── audio_service.dart
    └── export_service.dart

android/
├── app/
│   ├── build.gradle.kts     # Android build configuration
│   └── google-services.json # Firebase config (gitignored)
└── build.gradle.kts         # Project-level build config

assets/
└── images/                  # App images and icons
```

## 🔒 Security & Privacy

**⚠️ Important:** This repository does NOT contain sensitive credentials. All configuration files with API keys, passwords, and signing certificates are excluded via `.gitignore`.

### Required Setup Files (Not Included):
- ✅ `android/app/google-services.json` - Firebase configuration
- ✅ `android/key.properties` - Android signing credentials
- ✅ `android/app/*.jks` - Keystore files
- ✅ `.env` files - Environment variables

### For New Developers:
1. See `SECURITY.md` for complete setup instructions
2. Use template files (`*.template`) as reference
3. Never commit sensitive files to version control
4. Contact your team lead for credential access

### Security Features:
- 🔐 Phone number authentication via Firebase
- 🔥 Firebase Security Rules for data protection
- 🛡️ Encrypted data storage
- 🚫 No hardcoded secrets in codebase

**📖 Read `SECURITY.md` for detailed security guidelines.**

## 🧪 Testing

```bash
# Run unit tests
flutter test

# Run integration tests
flutter test integration_test/

# Run tests with coverage
flutter test --coverage
```

## 📦 Dependencies

### Core Dependencies
- `flutter`: SDK
- `firebase_core`: Firebase initialization
- `firebase_auth`: User authentication
- `cloud_firestore`: Database
- `firebase_storage`: File storage

### Feature Dependencies
- `audioplayers`: Audio playback
- `record`: Audio recording
- `speech_to_text`: Voice recognition
- `flutter_tts`: Text-to-speech
- `printing`: PDF generation
- `share_plus`: Content sharing

### Platform Dependencies
- `google_sign_in`: Google authentication
- `connectivity_plus`: Network connectivity
- `permission_handler`: Device permissions

## 🌍 Internationalization

The app supports multiple languages with dynamic switching:
- English (default)
- Spanish
- French
- Add more languages in `lib/l10n/`

## 🚀 Deployment

### GitHub Actions CI/CD
The project includes GitHub Actions workflows for:
- Automated testing
- Build verification
- Release deployment

### App Store Deployment
1. **Android**: Upload APK/AAB to Google Play Console
2. **iOS**: Archive and upload to App Store Connect
3. **Web**: Deploy to Firebase Hosting or Netlify

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.



- Flutter team for the amazing framework
- Firebase for backend services
- Open source community for the packages used Macjohnson for the awesome job.

---


