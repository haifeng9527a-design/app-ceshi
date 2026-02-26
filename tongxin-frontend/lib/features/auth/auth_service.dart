import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../messages/supabase_user_sync.dart';

class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  static bool _googleInitialized = false;
  static const String _googleServerClientId =
      '130160287801-vj4r1e6irc8e1g6mavm88qlf2sev2m4b.apps.googleusercontent.com';
  static const String _googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _syncSupabaseProfile();
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    final safeName = displayName?.trim();
    if (user != null && safeName != null && safeName.isNotEmpty) {
      await user.updateDisplayName(safeName);
      await user.reload();
    }
    await sendEmailVerificationIfNeeded();
    await _syncSupabaseProfile();
  }

  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await _auth.signInWithPopup(GoogleAuthProvider());
      await _syncSupabaseProfile();
      return;
    }
    await _ensureGoogleInitialized();
    final googleUser = await GoogleSignIn.instance.authenticate(
      scopeHint: const ['email', 'profile'],
    );
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    await _auth.signInWithCredential(credential);
    await _syncSupabaseProfile();
  }

  Future<void> signInWithApple() async {
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final oauth = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );
    await _auth.signInWithCredential(oauth);
    await _syncSupabaseProfile();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (_googleInitialized) {
      await GoogleSignIn.instance.signOut();
    }
  }

  Future<void> sendEmailVerificationIfNeeded() async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    await user.reload();
    if (!user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<bool> isEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) {
      return false;
    }
    await user.reload();
    return user.emailVerified;
  }

  Future<void> resendVerificationForEmailPassword({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await sendEmailVerificationIfNeeded();
    await _auth.signOut();
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) {
      return;
    }
    if (kIsWeb) {
      await GoogleSignIn.instance.initialize(
        clientId: _googleWebClientId.isEmpty ? null : _googleWebClientId,
      );
    } else {
      await GoogleSignIn.instance.initialize(
        serverClientId: _googleServerClientId,
      );
    }
    _googleInitialized = true;
  }

  Future<void> _syncSupabaseProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    await SupabaseUserSync().upsertFromFirebase(user);
  }
}
