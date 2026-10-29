import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../catalog/data/catalog.dart';

/// Wishlist table access; a provider so tests can swap it.
class WishlistApi {
  const WishlistApi(this._db);

  final SupabaseClient _db;

  /// Newest first.
  Future<Set<String>> productIds() async {
    final rows = await _db.from('wishlist').select('product_id').order('created_at');
    return {for (final r in rows) r['product_id'] as String};
  }

  Future<void> add(String userId, String productId) async {
    await _db.from('wishlist').upsert({'user_id': userId, 'product_id': productId}, ignoreDuplicates: true);
  }

  Future<void> remove(String userId, String productId) async {
    await _db.from('wishlist').delete().eq('user_id', userId).eq('product_id', productId);
  }
}

final wishlistApiProvider = Provider<WishlistApi>((ref) => WishlistApi(ref.watch(supabaseProvider)));

/// Ids of the signed-in user's saved products (drives the hearts). Empty when signed out.
final wishlistProvider = AsyncNotifierProvider<WishlistNotifier, Set<String>>(WishlistNotifier.new);

class WishlistNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const {};
    return ref.watch(wishlistApiProvider).productIds();
  }

  /// Optimistic; on failure only this product flips back (other toggles in flight are kept) and the error rethrows.
  Future<void> toggle(String productId) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) throw const AuthException('Sign in to save to your wishlist');
    final saved = state.value?.contains(productId) ?? false;
    _set(productId, !saved);
    try {
      final api = ref.read(wishlistApiProvider);
      saved ? await api.remove(uid, productId) : await api.add(uid, productId);
    } catch (_) {
      _set(productId, saved);
      rethrow;
    }
  }

  void _set(String productId, bool saved) {
    final ids = {...?state.value};
    saved ? ids.add(productId) : ids.remove(productId);
    state = AsyncData(ids);
  }
}

/// Cards for the wishlist screen, in wishlist order. Inactive products drop out (not in `product_cards`).
final wishlistCardsProvider = FutureProvider.autoDispose<List<ProductCard>>((ref) async {
  final ids = await ref.watch(wishlistProvider.future);
  if (ids.isEmpty) return const [];
  final rows = await ref.watch(supabaseProvider).from('product_cards').select(cardColumns).inFilter('id', [...ids]);
  final byId = {for (final r in rows) r['id'] as String: ProductCard.fromJson(r)};
  return [for (final id in ids) ?byId[id]];
});
