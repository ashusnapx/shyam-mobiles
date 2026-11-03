import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/supabase.dart';
import 'auth_repository_supabase.dart';

/// The signed-in person as the app needs them: no Supabase or Firebase types past this file.
class AppUser {
  const AppUser({required this.id, this.phone, this.email, this.displayName, this.photoUrl});

  final String id;
  final String? phone; // E.164 (+91…), when signed in by phone
  final String? email; // Google accounts
  final String? displayName;
  final String? photoUrl;
}

enum StaffRole { owner, staff }

/// One phone sign-in in progress: what [AuthRepository.verifyPhoneCode] needs back. [autoVerified]: Android read the
/// SMS itself and the user is already signed in.
class PhoneCodeRequest {
  const PhoneCodeRequest({required this.phone, this.verificationId, this.resendToken, this.autoVerified = false});

  final String phone;
  final String? verificationId;
  final int? resendToken;
  final bool autoVerified;
}

/// Sign-in and the session (docs/FIREBASE.md §4). Owner: engineer A.
abstract interface class AuthRepository {
  /// Emits on sign-in and sign-out only (not on token refreshes). Null: signed out.
  Stream<AppUser?> userChanges();

  AppUser? get currentUser;

  /// Staff rights in this session, or null. Firebase: the `role` claim plus a TOTP sign-in (docs/SECURITY.md §2.2).
  Future<StaffRole?> staffRole();

  /// The Google sheet, then a session. False when the user backed out.
  Future<bool> signInWithGoogle();

  /// Sends the SMS code to [phone] (E.164). Pass the last request as [resend] to send again.
  Future<PhoneCodeRequest> requestPhoneCode(String phone, {PhoneCodeRequest? resend});

  Future<void> verifyPhoneCode(PhoneCodeRequest request, String code);

  /// Supabase only: email codes go at the cut-over (decision D5); the Firebase implementation throws UnsupportedError.
  Future<void> requestEmailCode(String email);

  /// Supabase only, as [requestEmailCode].
  Future<void> verifyEmailCode(String email, String code);

  /// Debug and demo builds' one-tap test accounts (Env.devLogin): email + password, the Auth emulator only on Firebase.
  Future<void> signInForDev(String email, String password);

  /// Signs out on this phone only.
  Future<void> signOut();
}

/// The DI seam. Phase 1 (engineer A) returns SupabaseAuthRepository or FirebaseAuthRepository by `backend`; tests
/// override it with test/fakes/fake_auth_repository.dart.
final authRepositoryProvider = Provider<AuthRepository>((ref) => backend == Backend.firebase
    ? throw UnimplementedError('Phase 1: FirebaseAuthRepository')
    : SupabaseAuthRepository(ref.watch(supabaseProvider)));
