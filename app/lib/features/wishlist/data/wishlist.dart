import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/paging.dart';
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

/// Cards for the wishlist screen, in wishlist order, a page of saved ids at a time. Hidden products drop out (not in
/// `product_cards`), so a page can come back short or empty: an empty one moves straight on to the next ids, and
/// whether there's more goes by the ids, not the rows.
final wishlistCardsProvider =
    AsyncNotifierProvider.autoDispose<WishlistCardsNotifier, Paged<ProductCard>>(WishlistCardsNotifier.new);

class WishlistCardsNotifier extends PagedNotifier<ProductCard> {
  List<String> _ids = const [];
  int _cursor = 0; // ids asked for so far: a page may read past its size while it skips hidden ones
  int _dropped = 0;

  /// Saved products that aren't sold any more, among those loaded so far.
  int get dropped => _dropped;

  @override
  Object idOf(ProductCard c) => c.id;

  @override
  bool hasMoreAfter(int from, List<ProductCard> rows) => _cursor < _ids.length;

  @override
  Future<Paged<ProductCard>> build() async {
    _ids = [...await ref.watch(wishlistProvider.future)];
    return super.build();
  }

  /// The next [size] saved ids that still have a card, or the rest of them. [from] only says when to start over.
  @override
  Future<List<ProductCard>> fetch(int from, int size) async {
    if (from == 0) _cursor = _dropped = 0;
    while (_cursor < _ids.length) {
      final ids = _ids.skip(_cursor).take(size).toList();
      final rows = await ref.read(supabaseProvider).from('product_cards').select(cardColumns).inFilter('id', ids);
      final byId = {for (final r in rows) r['id'] as String: ProductCard.fromJson(r)};
      _cursor += ids.length;
      _dropped += ids.length - byId.length;
      if (byId.isNotEmpty) return [for (final id in ids) ?byId[id]];
    }
    return const [];
  }
}
