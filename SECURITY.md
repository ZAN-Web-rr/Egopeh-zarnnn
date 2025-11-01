# 🔐 Security Guidelines

## Overview
This project requires sensitive configuration files that are **NOT** included in the repository for security reasons. All developers must set up these files locally.

## 🚨 Required Configuration Files

### 1. Firebase Configuration
**File:** `android/app/google-services.json`

**Setup:**
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project or create a new one
3. Navigate to Project Settings → Your Apps
4. Download `google-services.json`
5. Place it in `android/app/` directory

**Template:** See `android/app/google-services.json.template`

---

### 2. Android Signing Configuration
**File:** `android/key.properties`

**Setup:**
```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=YOUR_KEY_ALIAS
storeFile=YOUR_KEYSTORE_FILE.jks
```

**Template:** See `android/key.properties.template`

---

### 3. Android Keystore File
**File:** `android/app/[YOUR-KEYSTORE].jks`

**Generate a new keystore:**
```bash
keytool -genkey -v -keystore android/app/zarn-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias zarn-key
```

**⚠️ IMPORTANT:**
- Store your keystore password in a secure password manager
- Back up your keystore file securely (without it, you cannot update your app)
- Never commit `.jks` files to version control

---

## 🔒 Sensitive Information Checklist

The following are **NEVER** committed to the repository:

- ❌ Firebase configuration files (`google-services.json`)
- ❌ Keystore files (`.jks`, `.keystore`)
- ❌ Signing credentials (`key.properties`)
- ❌ API keys and secrets (`.env` files)
- ❌ Private certificates (`.p12` files)
- ❌ OAuth client secrets
- ❌ Database credentials

All sensitive patterns are listed in `.gitignore`.

---

## 🛡️ Security Best Practices

### For Developers:
1. **Never share** your `key.properties` or `.jks` files
2. **Use different keystores** for debug and release builds
3. **Enable 2FA** on your Firebase account
4. **Review Firebase Security Rules** regularly
5. **Rotate API keys** if compromised

### For CI/CD:
Use encrypted secrets instead of files:

**GitHub Actions Example:**
```yaml
env:
  KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
  KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
  KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
```

**Store keystore as base64:**
```bash
# Encode
base64 -i android/app/zarn-release-key.jks > keystore.base64

# Decode in CI
echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > android/app/release.jks
```

---

## 🔍 Firebase Security Rules

Ensure your Firebase security rules are properly configured:

**Firestore Example:**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

**Storage Example:**
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /users/{userId}/{allPaths=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

---

## 📋 Setup Checklist for New Developers

- [ ] Clone the repository
- [ ] Copy `android/key.properties.template` to `android/key.properties`
- [ ] Fill in your keystore details in `key.properties`
- [ ] Download `google-services.json` from Firebase Console
- [ ] Place `google-services.json` in `android/app/`
- [ ] Generate or obtain the signing keystore (`.jks`)
- [ ] Verify `.gitignore` excludes all sensitive files
- [ ] Run `git status` to ensure no sensitive files are tracked
- [ ] Test build: `flutter build apk` or `flutter build appbundle`

---

## 🚨 What To Do If Credentials Are Exposed

1. **Immediately rotate compromised credentials:**
   - Generate new Firebase API keys
   - Create new keystore for app signing
   - Update OAuth client IDs

2. **Remove from git history** (if committed):
   ```bash
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch PATH_TO_FILE" \
     --prune-empty --tag-name-filter cat -- --all
   
   git push origin --force --all
   ```

3. **Notify your team** and update documentation

4. **Review Firebase Security Rules** and access logs

---

## 📞 Support

If you have security concerns or questions:
- Review this document first
- Check `.gitignore` for exclusion patterns
- Consult your team lead for credential access
- Never share credentials via email or chat

---

## 📝 Additional Resources

- [Firebase Security Checklist](https://firebase.google.com/docs/projects/security-checklist)
- [Android App Signing](https://developer.android.com/studio/publish/app-signing)
- [Flutter Security Best Practices](https://docs.flutter.dev/security)
- [GitHub Secret Scanning](https://docs.github.com/en/code-security/secret-scanning)

---

**Last Updated:** 2024
**Maintained By:** Development Team
