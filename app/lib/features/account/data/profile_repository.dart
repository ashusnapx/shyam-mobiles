import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';

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

  /// ACTIVE_ORDERS while orders or repairs are open or a refund is due. Signs the user out on success.
  Future<void> deleteAccount();
}

/// The DI seam (Phase 1: Supabase or Firebase by `backend`); tests use test/fakes/fake_profile_repository.dart.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) => throw UnimplementedError('Phase 1: ProfileRepository'));
