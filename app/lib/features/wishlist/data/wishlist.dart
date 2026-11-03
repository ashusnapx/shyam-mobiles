import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/paging.dart';
import '../../../core/supabase.dart';
import '../../catalog/data/catalog_repository.dart';
import 'wishlist_repository.dart';

/// Ids of the signed-in user's saved products (drives the hearts). Empty when signed out.
final wishlistProvider = AsyncNotifierProvider<WishlistNotifier, Set<String>>(WishlistNotifier.new);

class WishlistNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const {};
    return {...await ref.watch(wishlistRepositoryProvider).productIds(uid)};
  }

  /// Optimistic; on failure only this product flips back (other toggles in flight are kept) and the error rethrows.
  /// [waitFor]: saving a sold-out item also asks to hear when it's back (see [WishlistRepository.add]).
  Future<void> toggle(String productId, {String? waitFor}) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) throw const AuthException('Sign in to save to your wishlist');
    final saved = state.value?.contains(productId) ?? false;
    _set(productId, !saved);
    try {
      final api = ref.read(wishlistRepositoryProvider);
      saved ? await api.remove(uid, productId) : await api.add(uid, productId, waitFor: waitFor);
    } catch (_) {
      _set(productId, saved);
      rethrow;
    }
  }

  /// Notify me (docs/FIREBASE.md §6): saves the product, or marks the saved entry, to hear when [waitFor] is back.
  Future<void> notifyWhenBack(String productId, String waitFor) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) throw const AuthException('Sign in to hear when it’s back in stock');
    await ref.read(wishlistRepositoryProvider).add(uid, productId, waitFor: waitFor);
    _set(productId, true);
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
      final byId = {for (final c in await ref.read(catalogRepositoryProvider).cards(ids)) c.id: c};
      _cursor += ids.length;
      _dropped += ids.length - byId.length;
      if (byId.isNotEmpty) return [for (final id in ids) ?byId[id]];
    }
    return const [];
  }
}
