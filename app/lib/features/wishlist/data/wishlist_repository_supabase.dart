import 'package:supabase_flutter/supabase_flutter.dart';

import 'wishlist_repository.dart';

/// Today's wishlist table (RLS: own rows only). Deleted in Phase 2.
class SupabaseWishlistRepository implements WishlistRepository {
  const SupabaseWishlistRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<List<String>> productIds(String uid) async =>
      [for (final r in await _db.from('wishlist').select('product_id').order('created_at')) r['product_id'] as String];

  @override
  Future<void> add(String uid, String productId) =>
      _db.from('wishlist').upsert({'user_id': uid, 'product_id': productId}, ignoreDuplicates: true);

  @override
  Future<void> remove(String uid, String productId) =>
      _db.from('wishlist').delete().eq('user_id', uid).eq('product_id', productId);
}
