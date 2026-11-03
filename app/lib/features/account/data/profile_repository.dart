import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import 'profile_repository_firebase.dart';
import 'profile_repository_supabase.dart';

/// The customer's own profile, saved addresses and account deletion (docs/FIREBASE.md §3 users/*, §4). Owner: A.
abstract interface class ProfileRepository {
  /// Null until the profile exists (Firebase: the Name screen creates users/{uid}).
  Future<Profile?> profile(String uid);

  /// A null or blank [fullName] clears it. The caller has tidied and checked it (validatePersonName).
  Future<void> saveFullName(String uid, String? fullName);

  /// Default first, then newest.
  Future<List<Address>> addresses(String uid);

  /// Creates when `address.id` is null (ADDRESS_LIMIT past 10), else updates. Returns the saved address.
  Future<Address> saveAddress(String uid, Address address);

  Future<void> setDefaultAddress(String uid, String addressId);

  Future<void> deleteAddress(String uid, String addressId);

  /// ACTIVE_ORDERS while orders or repairs are open or a refund is due; REAUTH_REQUIRED on Firebase past 5 minutes
  /// after sign-in. The caller signs out afterwards.
  Future<void> deleteAccount();

  /// "Download my data" (docs/SECURITY.md §4.7): what the shop holds about the signed-in user, as JSON. Firebase
  /// allows it once a day (RATE_LIMITED).
  Future<Map<String, Object?>> exportMyData(String uid);
}

/// The DI seam (Phase 1: Supabase or Firebase by `backend`); tests use test/fakes/fake_profile_repository.dart.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) => backend == Backend.firebase
    ? FirebaseProfileRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider), ref.watch(firebaseAuthProvider))
    : SupabaseProfileRepository(ref.watch(supabaseProvider)));
