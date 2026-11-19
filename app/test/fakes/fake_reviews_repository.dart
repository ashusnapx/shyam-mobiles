import 'package:shyam_mobiles/features/admin/data/photos.dart' show PreparedPhoto;
import 'package:shyam_mobiles/features/reviews/data/reviews_repository.dart';

import 'fake.dart';

class FakeReviewsRepository with Fake implements ReviewsRepository {
  var statsOf = <String, ProductStats>{};
  var list = <Review>[];
  var canReview = <String>{};
  var tiles = <String, TileRating>{};
  Review? myReview;

  @override
  Future<ProductStats> stats(String productId) async => statsOf[productId] ?? const ProductStats();

  @override
  Future<List<Review>> reviews(String productId, {int limit = 20}) async =>
      [for (final r in list) if (r.productId == productId && !r.hidden) r].take(limit).toList();

  @override
  Future<Set<String>> reviewable(String uid) async => canReview;

  @override
  Future<Review?> mine(String uid, String productId) async => myReview;

  @override
  Future<void> save({required String productId, required int rating, String text = '', List<String> photos = const []}) async =>
      record('save $productId $rating "$text" ${photos.length}');

  @override
  Future<String> uploadPhoto(String uid, PreparedPhoto photo) async {
    record('upload');
    return 'review-photos/$uid/1.webp';
  }

  @override
  Stream<Map<String, TileRating>> tileRatings() => Stream.value(tiles);

  @override
  Future<List<Review>> recent({int limit = 50}) async => list;

  @override
  Future<void> setHidden(String id, {required bool hidden}) async => record('hide $id $hidden');
}
