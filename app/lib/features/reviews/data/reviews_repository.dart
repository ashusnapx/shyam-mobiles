import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart' show firestoreProvider, functionsProvider, storageProvider;
import '../../admin/data/photos.dart' show PreparedPhoto;
import 'reviews_repository_firebase.dart';
import 'reviews_repository_supabase.dart';

/// A verified-purchase review (firebase/functions/src/model/reviews.ts). [name] is "Ravi S.", never the full name.
class Review {
  const Review({
    required this.id,
    required this.productId,
    required this.uid,
    required this.name,
    required this.rating,
    this.text = '',
    this.photos = const [],
    this.hidden = false,
    required this.updatedAt,
  });

  final String id;
  final String productId;
  final String uid;
  final String name;
  final int rating; // 1..5
  final String text;
  final List<String> photos; // Storage keys under review-photos/
  final bool hidden;
  final DateTime updatedAt;
}

/// productStats/{productId}: counted by triggers, never typed in (docs/GROWTH.md §2a, b).
class ProductStats {
  const ProductStats({
    this.ratingCount = 0,
    this.ratingSum = 0,
    this.stars = const [0, 0, 0, 0, 0],
    this.sold = const {},
    this.boughtWith = const {},
  });

  final int ratingCount;
  final int ratingSum;
  final List<int> stars; // [1★, …, 5★]
  final Map<String, int> sold; // 'YYYY-MM-DD' (IST) → units on orders that became paid or delivered that day
  final Map<String, int> boughtWith; // productId → orders holding both

  double get average => ratingCount == 0 ? 0 : ratingSum / ratingCount;
}

/// The tile's "★ 4.3 (12)": average × 10 and the count, from reviewIndex/public.
typedef TileRating = ({int avg10, int count});

/// Reviews, ratings and the counted numbers on product pages (docs/GROWTH.md §2). Firebase only: the Supabase build
/// returns nothing, so every review surface stays hidden until the cut-over.
abstract interface class ReviewsRepository {
  /// Empty stats when the product has none yet.
  Future<ProductStats> stats(String productId);

  /// Visible reviews of a product, newest first, at most [limit].
  Future<List<Review>> reviews(String productId, {int limit = 20});

  /// Product ids in [uid]'s delivered orders (the latest 50): what they may review.
  Future<Set<String>> reviewable(String uid);

  /// The caller's own review of [productId] (hidden ones too), if any.
  Future<Review?> mine(String uid, String productId);

  /// REVIEW_NOT_ALLOWED unless the caller has a delivered order of [productId]. Saving again replaces the review.
  Future<void> save({required String productId, required int rating, String text = '', List<String> photos = const []});

  /// Uploads `review-photos/<uid>/<millis>.webp` and its thumb; returns the full photo's key.
  Future<String> uploadPhoto(String uid, PreparedPhoto photo);

  /// productId → the tile's rating, live.
  Stream<Map<String, TileRating>> tileRatings();

  // Staff ------------------------------------------------------------------------------------------------------

  /// Every review, hidden ones too, newest first.
  Future<List<Review>> recent({int limit = 50});

  /// Hide (abuse, personal data, spam) or show again. Never for being negative.
  Future<void> setHidden(String id, {required bool hidden});
}

final reviewsRepositoryProvider = Provider<ReviewsRepository>((ref) => backend == Backend.firebase
    ? FirebaseReviewsRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider), ref.watch(storageProvider))
    : const SupabaseReviewsRepository());
