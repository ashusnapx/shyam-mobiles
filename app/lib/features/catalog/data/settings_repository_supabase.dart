import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import 'settings_repository.dart';

/// Today's single store_settings row. Deleted in Phase 2.
class SupabaseSettingsRepository implements SettingsRepository {
  const SupabaseSettingsRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<StoreSettings> storeSettings() async => StoreSettings.fromJson(await _db.from('store_settings').select().single());

  // store_photos has its own writer below; the form's copy may be stale
  @override
  Future<void> saveStoreSettings(StoreSettings settings) =>
      _db.from('store_settings').update(settings.toJson()..remove('store_photos')).eq('id', true).select('id').single();

  @override
  Future<void> saveStorePhotos(List<String> paths) =>
      _db.from('store_settings').update({'store_photos': paths}).eq('id', true).select('id').single();

  @override
  Future<BusinessProfile?> businessProfile() async => null;

  @override
  Future<void> saveBusinessProfile(BusinessProfile profile) =>
      throw UnsupportedError('The business profile needs the Firebase build');
}
