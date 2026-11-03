import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'photos.dart' show PreparedPhoto;

/// Photo files in Storage (product-images/…, same keys as today; docs/FIREBASE.md §1). Staff only. Owner: B.
abstract interface class PhotoStore {
  /// Uploads `<folder>/<millis>.webp` and its `@thumb.webp`; returns the full photo's key.
  Future<String> upload(String folder, PreparedPhoto photo);

  /// Best effort: an orphaned file is harmless.
  Future<void> remove(List<String> paths);
}

final photoStoreProvider = Provider<PhotoStore>((ref) => throw UnimplementedError('Phase 1: PhotoStore'));
