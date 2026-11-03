import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';
import 'google.dart' as google;

/// Today's Supabase sign-in behind [AuthRepository] (docs/FIREBASE.md §2); deleted in Phase 2 with Supabase.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._db);

  final SupabaseClient _db;

  GoTrueClient get _auth => _db.auth;

  static AppUser? _user(User? u) => u == null
      ? null
      : AppUser(
          id: u.id,
          // Supabase stores phones without '+', and '' for accounts without one
          phone: (u.phone?.isEmpty ?? true) ? null : '+${u.phone!.replaceFirst('+', '')}',
          email: (u.email?.isEmpty ?? true) ? null : u.email,
          displayName: u.userMetadata?['full_name'] as String? ?? u.userMetadata?['name'] as String?,
          photoUrl: u.userMetadata?['avatar_url'] as String?,
        );

  @override
  Stream<AppUser?> userChanges() => _auth.onAuthStateChange
      .where((s) => const {AuthChangeEvent.initialSession, AuthChangeEvent.signedIn, AuthChangeEvent.signedOut}
          .contains(s.event))
      .map((s) => _user(s.session?.user));

  @override
  AppUser? get currentUser => _user(_auth.currentUser);

  /// Supabase has one kind of staff (the `admins` table), with every right.
  @override
  Future<StaffRole?> staffRole() async =>
      _auth.currentUser != null && await _db.rpc<bool>('is_admin') ? StaffRole.owner : null;

  @override
  Future<bool> signInWithGoogle() => google.signInWithGoogle(_auth);

  @override
  Future<PhoneCodeRequest> requestPhoneCode(String phone, {PhoneCodeRequest? resend}) async {
    await _auth.signInWithOtp(phone: phone);
    return PhoneCodeRequest(phone: phone);
  }

  @override
  Future<void> verifyPhoneCode(PhoneCodeRequest request, String code) =>
      _auth.verifyOTP(phone: request.phone, token: code, type: OtpType.sms);

  @override
  Future<void> requestEmailCode(String email) => _auth.signInWithOtp(email: email, shouldCreateUser: true);

  @override
  Future<void> verifyEmailCode(String email, String code) =>
      _auth.verifyOTP(email: email, token: code, type: OtpType.email);

  @override
  Future<void> signInForDev(String email, String password) =>
      _auth.signInWithPassword(email: email, password: password);

  @override
  Future<void> signOut() async {
    await google.signOutOfGoogle();
    await _auth.signOut(scope: SignOutScope.local);
  }
}
