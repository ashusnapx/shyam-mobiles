import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';

/// settings/store: fees, COD, hours, store photos (docs/FIREBASE.md §3). Everyone reads; staff write. Owner: B.
abstract interface class SettingsRepository {
  Future<StoreSettings> storeSettings();

  /// Staff. Everything but the store photos, which [saveStorePhotos] owns.
  Future<void> saveStoreSettings(StoreSettings settings);

  /// Staff: the ordered list of store photo keys (uploads go through PhotoStore first).
  Future<void> saveStorePhotos(List<String> paths);
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => throw UnimplementedError('Phase 1: SettingsRepository'));
