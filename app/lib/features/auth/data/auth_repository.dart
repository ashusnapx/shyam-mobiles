import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart';
import '../../../core/supabase.dart';
import 'auth_repository_firebase.dart';
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
    ? FirebaseAuthRepository(ref.watch(firebaseAuthProvider))
    : SupabaseAuthRepository(ref.watch(supabaseProvider)));

final _authChangesProvider = StreamProvider<AppUser?>((ref) => ref.watch(authRepositoryProvider).userChanges());

/// The signed-in person, or null. Changes on sign-in and sign-out (core/supabase.dart re-exports it until Phase 2).
final currentUserProvider = Provider<AppUser?>((ref) {
  ref.watch(_authChangesProvider);
  return ref.watch(authRepositoryProvider).currentUser;
});

/// For data that belongs to the user: only changes on sign-in and sign-out, so data isn't refetched needlessly.
final currentUserIdProvider = Provider<String?>((ref) => ref.watch(currentUserProvider)?.id);

/// Staff screens are shown only to staff; the server checks again on every call.
final isAdminProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return false;
  return await ref.watch(authRepositoryProvider).staffRole() != null;
});
