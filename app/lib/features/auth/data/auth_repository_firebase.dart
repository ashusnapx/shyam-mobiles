import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/backend.dart';
import 'auth_repository.dart';
import 'google.dart' as google;

/// Firebase Auth sign-in (docs/FIREBASE.md §4): Google and phone OTP; email/password only for the emulator's dev logins.
/// FirebaseAuthException codes reach the screens as they are; auth_errors.dart turns them into copy.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final FirebaseAuth _auth;

  static AppUser? _user(User? u) => u == null
      ? null
      : AppUser(id: u.uid, phone: u.phoneNumber, email: u.email, displayName: u.displayName, photoUrl: u.photoURL);

  @override
  Stream<AppUser?> userChanges() => _auth.authStateChanges().map(_user);

  @override
  AppUser? get currentUser => _user(_auth.currentUser);

  /// The `role` claim counts only in a TOTP session (docs/SECURITY.md §2.2), or a dev login on the emulators
  /// (firebase/README.md "Staff on the emulator"). The server checks the same, plus the role doc.
  @override
  Future<StaffRole?> staffRole() async {
    final token = await _auth.currentUser?.getIdTokenResult();
    if (token == null) return null;
    final staffSession =
        token.signInSecondFactor == 'totp' || (useEmulators && token.signInProvider == 'password');
    return staffSession ? StaffRole.values.asNameMap()[token.claims?['role']] : null;
  }

  @override
  Future<bool> signInWithGoogle() async {
    final idToken = await google.googleIdToken();
    if (idToken == null) return false;
    await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
    return true;
  }

  /// Completes when the SMS is sent, or when Android verified the number itself (SMS Retriever or instant
  /// verification: already signed in, [PhoneCodeRequest.autoVerified]). A code read after this completes still signs
  /// the user in, and the router moves on.
  @override
  Future<PhoneCodeRequest> requestPhoneCode(String phone, {PhoneCodeRequest? resend}) async {
    final sent = Completer<PhoneCodeRequest>();
    void settle(PhoneCodeRequest r) => sent.isCompleted ? null : sent.complete(r);
    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      forceResendingToken: resend?.resendToken,
      timeout: const Duration(seconds: 60), // auto-retrieval window, as the resend timer
      verificationCompleted: (credential) async {
        try {
          await _auth.signInWithCredential(credential);
          settle(PhoneCodeRequest(phone: phone, autoVerified: true));
        } catch (e) {
          if (!sent.isCompleted) sent.completeError(e);
        }
      },
      verificationFailed: (e) => sent.isCompleted ? null : sent.completeError(e),
      codeSent: (id, token) => settle(PhoneCodeRequest(phone: phone, verificationId: id, resendToken: token)),
      codeAutoRetrievalTimeout: (_) {},
    );
    return sent.future;
  }

  @override
  Future<void> verifyPhoneCode(PhoneCodeRequest request, String code) async {
    if (request.autoVerified || _auth.currentUser?.phoneNumber == request.phone) return; // Android got there first
    await _auth.signInWithCredential(PhoneAuthProvider.credential(verificationId: request.verificationId!, smsCode: code));
  }

  @override
  Future<void> requestEmailCode(String email) => throw UnsupportedError('Email codes are not offered on Firebase (D5)');

  @override
  Future<void> verifyEmailCode(String email, String code) => throw UnsupportedError('Email codes are not offered on Firebase (D5)');

  @override
  Future<void> signInForDev(String email, String password) {
    if (!useEmulators) throw UnsupportedError('Dev logins exist only on the Auth emulator');
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() async {
    await google.signOutOfGoogle();
    await _auth.signOut();
  }
}
