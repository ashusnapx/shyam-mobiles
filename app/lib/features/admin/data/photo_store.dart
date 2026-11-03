import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart' show storageProvider;
import '../../../core/supabase.dart' show supabaseProvider, thumbPathFor;
import 'photos.dart' show PreparedPhoto;

/// Photo files in Storage (product-images/…, same keys as today; docs/FIREBASE.md §1). Staff only. Owner: B.
abstract interface class PhotoStore {
  /// Uploads `<folder>/<millis>.webp` and its `@thumb.webp`; returns the full photo's key.
  Future<String> upload(String folder, PreparedPhoto photo);

  /// Best effort: an orphaned file is harmless.
  Future<void> remove(List<String> paths);
}

final photoStoreProvider = Provider<PhotoStore>((ref) => backend == Backend.firebase
    ? FirebasePhotoStore(ref.watch(storageProvider))
    : SupabasePhotoStore(ref.watch(supabaseProvider).storage.from('product-images')));

// Keys are never reused (<millis>.webp), so phones may cache a photo for a year: one download per customer.
const _yearCache = 'public, max-age=31536000';

/// Uploads the full photo, then its thumb; a failed thumb takes the full photo back out.
Future<String> _uploadPair(String folder, PreparedPhoto photo, Future<void> Function(String key, Uint8List bytes) put,
    Future<void> Function(List<String>) remove) async {
  final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.webp';
  await put(path, photo.full);
  try {
    await put(thumbPathFor(path)!, photo.thumb);
  } catch (_) {
    await remove([path]);
    rethrow;
  }
  return path;
}

class SupabasePhotoStore implements PhotoStore {
  const SupabasePhotoStore(this._bucket);

  final StorageFileApi _bucket;

  @override
  Future<String> upload(String folder, PreparedPhoto photo) => _uploadPair(
      folder,
      photo,
      (key, bytes) => _bucket.uploadBinary(key, bytes,
          fileOptions: const FileOptions(contentType: 'image/webp', cacheControl: '31536000')),
      remove);

  @override
  Future<void> remove(List<String> paths) async {
    try {
      await _bucket.remove(paths);
    } catch (_) {}
  }
}

/// Storage Rules: staff only, image/webp|jpeg|png, at most 1 MB (photos.dart keeps each under 900 KB).
class FirebasePhotoStore implements PhotoStore {
  const FirebasePhotoStore(this._storage);

  final FirebaseStorage _storage;

  Reference _ref(String key) => _storage.ref('product-images/$key');

  @override
  Future<String> upload(String folder, PreparedPhoto photo) => _uploadPair(
      folder,
      photo,
      (key, bytes) => _ref(key).putData(bytes, SettableMetadata(contentType: 'image/webp', cacheControl: _yearCache)),
      remove);

  @override
  Future<void> remove(List<String> paths) async {
    for (final p in paths) {
      try {
        await _ref(p).delete();
      } catch (_) {}
    }
  }
}
