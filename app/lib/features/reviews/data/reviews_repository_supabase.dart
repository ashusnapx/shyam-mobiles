import '../../admin/data/photos.dart' show PreparedPhoto;
import 'reviews_repository.dart';

/// Reviews exist only on Firebase: before the cut-over every read is empty, so the review surfaces stay hidden.
/// Deleted in Phase 2.
class SupabaseReviewsRepository implements ReviewsRepository {
  const SupabaseReviewsRepository();

  @override
  Future<ProductStats> stats(String productId) async => const ProductStats();

  @override
  Future<List<Review>> reviews(String productId, {int limit = 20}) async => const [];

  @override
  Future<Set<String>> reviewable(String uid) async => const {};

  @override
  Future<Review?> mine(String uid, String productId) async => null;

  @override
  Future<void> save({required String productId, required int rating, String text = '', List<String> photos = const []}) =>
      throw UnsupportedError('Reviews need the Firebase backend');

  @override
  Future<String> uploadPhoto(String uid, PreparedPhoto photo) => throw UnsupportedError('Reviews need the Firebase backend');

  @override
  Stream<Map<String, TileRating>> tileRatings() => Stream.value(const {});

  @override
  Future<List<Review>> recent({int limit = 50}) async => const [];

  @override
  Future<void> setHidden(String id, {required bool hidden}) => throw UnsupportedError('Reviews need the Firebase backend');
}
