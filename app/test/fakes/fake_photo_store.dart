import 'package:shyam_mobiles/features/admin/data/photo_store.dart';
import 'package:shyam_mobiles/features/admin/data/photos.dart' show PreparedPhoto;

import 'fake.dart';

class FakePhotoStore with Fake implements PhotoStore {
  final files = <String, int>{}; // key → bytes
  var _clock = 1730000000000;

  @override
  Future<String> upload(String folder, PreparedPhoto photo) async {
    record('upload $folder');
    final path = '$folder/${_clock++}.webp';
    files[path] = photo.full.length;
    files[path.replaceFirst('.webp', '@thumb.webp')] = photo.thumb.length;
    return path;
  }

  @override
  Future<void> remove(List<String> paths) async {
    record('remove ${paths.length}');
    paths.forEach(files.remove);
  }
}
