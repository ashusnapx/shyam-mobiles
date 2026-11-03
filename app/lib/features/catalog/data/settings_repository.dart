import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart' show firestoreProvider;
import '../../../core/models/models.dart';
import '../../../core/network.dart' show savedOrFetch;
import '../../../core/supabase.dart' show supabaseProvider;
import 'settings_repository_firebase.dart';
import 'settings_repository_supabase.dart';

/// settings/business: the shop's legal identity, printed on invoices and the policy pages (docs/FIREBASE.md §3). The
/// GSTIN is the only tax id kept: there is never a PAN field. [stateCode] is always the GSTIN's first two digits.
class BusinessProfile {
  const BusinessProfile({
    required this.tradeName,
    required this.legalName,
    required this.gstin,
    required this.phone,
    this.email,
    required this.line1,
    required this.city,
    required this.district,
    required this.state,
    required this.pincode,
  });

  final String tradeName; // "Shyam Online Shop"
  final String legalName; // the proprietor
  final String gstin;
  final String phone; // +91…
  final String? email;
  final String line1;
  final String city;
  final String district;
  final String state;
  final String pincode;

  String get stateCode => gstin.substring(0, 2);

  /// One line, as customers see it: "Rajeev Complex, Waidhan, District Singrauli, Madhya Pradesh 486886".
  String get address => '$line1, $city, District $district, $state $pincode';
}

/// settings/store (fees, COD, hours, store photos) and settings/business. Everyone reads; staff write. Owner: B.
abstract interface class SettingsRepository {
  Future<StoreSettings> storeSettings();

  /// Staff. Everything but the store photos, which [saveStorePhotos] owns.
  Future<void> saveStoreSettings(StoreSettings settings);

  /// Staff: the ordered list of store photo keys (uploads go through PhotoStore first).
  Future<void> saveStorePhotos(List<String> paths);

  /// Null on the Supabase build: its store phone and address live in store_settings instead.
  Future<BusinessProfile?> businessProfile();

  /// Staff signed in within the last 5 minutes (Rules); [profile] already passed the form's checks.
  Future<void> saveBusinessProfile(BusinessProfile profile);
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => backend == Backend.firebase
    ? FirebaseSettingsRepository(ref.watch(firestoreProvider))
    : SupabaseSettingsRepository(ref.watch(supabaseProvider)));

/// Saved on the phone: a cold start (or no signal) shows the last copy at once and refreshes in the background.
final storeSettingsProvider = FutureProvider<StoreSettings>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return savedOrFetch(ref, 'store_settings', () async => (await repo.storeSettings()).toJson(),
      (json) => StoreSettings.fromJson(json! as Map<String, dynamic>));
});

/// Admin → Settings' business section; null on the Supabase build.
final businessProfileProvider = FutureProvider.autoDispose<BusinessProfile?>((ref) => ref.watch(settingsRepositoryProvider).businessProfile());
