import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in customer's saved products (Firebase: wishlists/{uid}, ≤ 200 ids). Owner: engineer B.
abstract interface class WishlistRepository {
  /// Newest first.
  Future<List<String>> productIds(String uid);

  /// No-op when already saved.
  Future<void> add(String uid, String productId);

  Future<void> remove(String uid, String productId);
}

final wishlistRepositoryProvider = Provider<WishlistRepository>((ref) => throw UnimplementedError('Phase 1: WishlistRepository'));
