import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // If you need to pass a web-client ID, use the named parameter `clientId:`
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    // clientId: 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com',
  );

  /// Sign up with email and password
  Future<UserCredential> signupWithEmail(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password)
          .then((cred) {
        sendEmailVerification();
        return cred;
      });

  /// Login with email and password
  Future<UserCredential> loginWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  /// Sign in with Google
  Future<UserCredential> signInWithGoogle({bool forcePrompt = false}) async {
    final googleSignIn = GoogleSignIn(
      scopes: ['email'],
    );

    if (forcePrompt) {
      await googleSignIn.signOut(); // Important: forces re-pick of account
    }

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google sign-in was cancelled');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return await _auth.signInWithCredential(credential);
  }

  Future<void> signOutFromGoogle() async {
    await GoogleSignIn().signOut();
  }


  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<bool> checkIfEmailInUse(String email) async {
    try {
      final result = await _db
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      return result.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Firestore email check error: $e');
      return false;
    }
  }




  Future<bool> checkEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser!.emailVerified;
  }

  bool isEmailVerified() => _auth.currentUser?.emailVerified ?? false;

  Future<void> updateProfile({String? displayName, String? photoURL}) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');
    if (displayName != null) await user.updateDisplayName(displayName);
    if (photoURL != null) await user.updatePhotoURL(photoURL);
    await user.reload();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  /// Save the full profile info for a new user
  Future<void> saveUserInfo({
    required String uid,
    required String name,
    required String email,
    required String phone,
    required bool is12Hour,
  }) {
    return _db
        .collection('users')
        .doc(uid)
        .set({
      'name': name,
      'email': email,
      'phone': phone,
      'is12HourFormat': is12Hour,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }



  /// Save just usage into /user_metadata/{uid}
  Future<void> saveEnquiry(String uid, String usage) {
    return _db
        .collection('user_metadata')
        .doc(uid)
        .set({ 'usage': usage }, SetOptions(merge: true));
  }

  /// Save just role into /user_metadata/{uid}
  Future<void> saveRole(String uid, String role) {
    return _db
        .collection('user_metadata')
        .doc(uid)
        .set({ 'role': role }, SetOptions(merge: true));
  }
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}

