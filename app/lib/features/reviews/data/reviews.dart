import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart' show cacheFor, currentUserIdProvider;
import '../../catalog/data/catalog_repository.dart';
import 'reviews_repository.dart';

/// Tiles show a rating only from this many reviews up: one or two say little (docs/GROWTH.md §2a).
const minTileReviews = 3;

/// The product page's few: with photos first, then with words, then newest. Never sorted by rating, so a low one
/// gets the same place a high one would.
List<Review> topReviews(List<Review> all, [int n = 3]) {
  int weight(Review r) => (r.photos.isNotEmpty ? 2 : 0) + (r.text.isNotEmpty ? 1 : 0);
  return ([...all]..sort((a, b) => weight(a) != weight(b) ? weight(b) - weight(a) : b.updatedAt.compareTo(a.updatedAt)))
      .take(n)
      .toList();
}

/// "N bought this week" shows only from this many: fewer proves nothing (docs/GROWTH.md §2b).
const minBoughtShown = 3;

/// A pair seen in at least this many orders is "frequently" bought together.
const minTogether = 2;

/// Units on orders paid or delivered in the 7 IST days ending [now]'s day (the server keeps only those days, but a
/// product nobody bought since still holds older ones).
int boughtThisWeek(Map<String, int> sold, DateTime now) {
  final today = now.toUtc().add(const Duration(hours: 5, minutes: 30));
  final days = {
    for (var i = 0; i < 7; i++) today.subtract(Duration(days: i)).toIso8601String().substring(0, 10),
  };
  return sold.entries.where((e) => days.contains(e.key)).fold(0, (n, e) => n + e.value);
}

/// Products bought with this one in at least [minTogether] orders, most often first (then by id), at most [n].
List<String> togetherIds(Map<String, int> withCounts, [int n = 8]) {
  final hits = withCounts.entries.where((e) => e.value >= minTogether).toList()
    ..sort((a, b) => a.value != b.value ? b.value - a.value : a.key.compareTo(b.key));
  return [for (final e in hits.take(n)) e.key];
}

/// "4.3": one decimal, from the tile index's average × 10.
String ratingLabel(int avg10) => '${avg10 ~/ 10}.${avg10 % 10}';

final productStatsProvider = FutureProvider.autoDispose.family<ProductStats, String>((ref, productId) {
  cacheFor(ref, const Duration(minutes: 5));
  return ref.watch(reviewsRepositoryProvider).stats(productId);
});

final productReviewsProvider = FutureProvider.autoDispose.family<List<Review>, String>((ref, productId) {
  cacheFor(ref, const Duration(minutes: 5));
  return ref.watch(reviewsRepositoryProvider).reviews(productId, limit: 50);
});

/// "Frequently bought together": real co-purchases only, in that order; hidden products drop out.
final togetherProvider = FutureProvider.autoDispose.family<List<ProductCard>, String>((ref, productId) async {
  final ids = togetherIds((await ref.watch(productStatsProvider(productId).future)).boughtWith);
  if (ids.isEmpty) return const [];
  final byId = {for (final c in await ref.watch(catalogRepositoryProvider).cards(ids)) c.id: c};
  return [for (final id in ids) ?byId[id]];
});

/// The signed-in customer's own review of a product (hidden ones too).
final myReviewProvider = FutureProvider.autoDispose.family<Review?, String>((ref, productId) async {
  final uid = ref.watch(currentUserIdProvider);
  return uid == null ? null : ref.watch(reviewsRepositoryProvider).mine(uid, productId);
});

/// Products the signed-in customer may review (in a delivered order). The server checks again (REVIEW_NOT_ALLOWED).
final reviewableProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const {};
  cacheFor(ref, const Duration(minutes: 5));
  return ref.watch(reviewsRepositoryProvider).reviewable(uid);
});

/// productId → the tile's rating, one live doc for every tile.
final tileRatingsProvider = StreamProvider<Map<String, TileRating>>((ref) => ref.watch(reviewsRepositoryProvider).tileRatings());

/// After a save: the product page and the tile show the new numbers once the trigger has run.
void refreshReviews(WidgetRef ref, String productId) {
  ref
    ..invalidate(myReviewProvider(productId))
    ..invalidate(productReviewsProvider(productId))
    ..invalidate(productStatsProvider(productId));
}
