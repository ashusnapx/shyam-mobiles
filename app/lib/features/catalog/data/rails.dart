import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart' show cacheFor;
import '../widgets/product_tile.dart' show shortName;
import 'catalog.dart';
import 'catalog_repository.dart';

const railSize = 8;

/// The [railSize] cards nearest [pricePaise], nearest first (a tie: the cheaper).
List<ProductCard> closestByPrice(List<ProductCard> cards, int pricePaise) {
  int gap(ProductCard c) => (c.minPricePaise - pricePaise).abs();
  return ([...cards]..sort((a, b) => gap(a) != gap(b) ? gap(a) - gap(b) : a.minPricePaise - b.minPricePaise))
      .take(railSize)
      .toList();
}

/// "Fits this phone": accessories made for it. Their "Fits" spec is the phone's short name ("Galaxy S25"), or the
/// full one when that's just a number ("OnePlus 13"), so both are tried. Empty for anything but a phone.
final fitsProvider = FutureProvider.autoDispose.family<List<ProductCard>, String>((ref, slug) async {
  cacheFor(ref, const Duration(minutes: 5));
  final p = await ref.watch(productProvider(slug).future);
  if (p == null || p.category.kind != CategoryKind.phone) return const [];
  return ref.watch(catalogRepositoryProvider).fits({shortName(p.name, p.brand.name), p.name});
});

/// "Similar": same category, nearest price to this product's cheapest option.
final similarProvider = FutureProvider.autoDispose.family<List<ProductCard>, String>((ref, slug) async {
  cacheFor(ref, const Duration(minutes: 5));
  final p = await ref.watch(productProvider(slug).future);
  final prices = [for (final v in p?.activeVariants ?? const <Variant>[]) v.pricePaise];
  if (p == null || prices.isEmpty) return const [];
  return ref.watch(catalogRepositoryProvider).similar(p.category.slug, prices.reduce(math.min), p.id);
});

final latestProvider = FutureProvider.autoDispose<List<ProductCard>>((ref) {
  cacheFor(ref, const Duration(minutes: 5));
  return ref.watch(catalogRepositoryProvider).latest();
});

const _recentKey = 'recently_viewed';

/// Ids of the last 10 products opened on this phone, newest first. Kept in shared_preferences only.
final recentlyViewedProvider = AsyncNotifierProvider<RecentlyViewed, List<String>>(RecentlyViewed.new);

class RecentlyViewed extends AsyncNotifier<List<String>> {
  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null; // no plugin (tests): nothing is remembered
    }
  }

  @override
  Future<List<String>> build() async => (await _prefs())?.getStringList(_recentKey) ?? const [];

  Future<void> add(String productId) async {
    final before = await future;
    if (before.firstOrNull == productId) return;
    final ids = [productId, ...before.where((id) => id != productId)].take(10).toList();
    state = AsyncData(ids);
    await (await _prefs())?.setStringList(_recentKey, ids);
  }
}

/// Home's "Recently viewed" cards, in viewing order; products gone from the shop drop out.
final recentCardsProvider = FutureProvider.autoDispose<List<ProductCard>>((ref) async {
  final ids = await ref.watch(recentlyViewedProvider.future);
  if (ids.isEmpty) return const [];
  final byId = {for (final c in await ref.watch(catalogRepositoryProvider).cards(ids)) c.id: c};
  return [for (final id in ids) ?byId[id]];
});
