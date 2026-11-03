import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/catalog/data/settings_repository.dart';

import 'fake.dart';

class FakeSettingsRepository with Fake implements SettingsRepository {
  FakeSettingsRepository(this.settings);

  StoreSettings settings;
  var storePhotos = <String>[];

  @override
  Future<StoreSettings> storeSettings() async {
    record('storeSettings');
    return settings;
  }

  @override
  Future<void> saveStoreSettings(StoreSettings settings) async {
    record('saveStoreSettings');
    this.settings = settings;
  }

  @override
  Future<void> saveStorePhotos(List<String> paths) async {
    record('saveStorePhotos ${paths.length}');
    storePhotos = [...paths];
  }
}
