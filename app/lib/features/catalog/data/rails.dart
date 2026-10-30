import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../widgets/product_tile.dart' show shortName;
import 'catalog.dart';

const railSize = 8;

/// The product-page and home rails' reads; a provider so tests can swap it.
class RailsApi {
  const RailsApi(this._db);

  final SupabaseClient _db;

  /// Accessories whose specs say `{"label": "Fits", "value": <one of names>}`, in stock first.
  Future<List<ProductCard>> fits(Set<String> names) async {
    final hits = await Future.wait([
      for (final n in names)
        _db.from('products').select('id').filter('specs', 'cs', jsonEncode([{'label': 'Fits', 'value': n}])).limit(40),
    ]);
    final ids = {for (final rows in hits) for (final r in rows) r['id'] as String};
    if (ids.isEmpty) return const [];
    final rows = await _db
        .from('product_cards')
        .select(cardColumns)
        .inFilter('id', ids.toList())
        .order('in_stock')
        .order('min_price_paise', ascending: true)
        .order('id', ascending: true)
        .limit(railSize);
    return [for (final r in rows) ProductCard.fromJson(r)];
  }

  /// The products in [categorySlug] priced nearest [pricePaise], [excludeId] left out.
  Future<List<ProductCard>> similar(String categorySlug, int pricePaise, String excludeId) async {
    PostgrestFilterBuilder<PostgrestList> base() =>
        _db.from('product_cards').select(cardColumns).eq('category_slug', categorySlug).neq('id', excludeId);
    final (above, below) = await (
      base().gte('min_price_paise', pricePaise).order('min_price_paise', ascending: true).limit(railSize),
      base().lt('min_price_paise', pricePaise).order('min_price_paise').limit(railSize),
    ).wait;
    return closestByPrice([for (final r in [...above, ...below]) ProductCard.fromJson(r)], pricePaise);
  }

  Future<List<ProductCard>> cards(List<String> ids) async {
    final rows = await _db.from('product_cards').select(cardColumns).inFilter('id', ids);
    return [for (final r in rows) ProductCard.fromJson(r)];
  }
}

final railsApiProvider = Provider<RailsApi>((ref) => RailsApi(ref.watch(supabaseProvider)));

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
  return ref.watch(railsApiProvider).fits({shortName(p.name, p.brand.name), p.name});
});

/// "Similar": same category, nearest price to this product's cheapest option.
final similarProvider = FutureProvider.autoDispose.family<List<ProductCard>, String>((ref, slug) async {
  cacheFor(ref, const Duration(minutes: 5));
  final p = await ref.watch(productProvider(slug).future);
  final prices = [for (final v in p?.activeVariants ?? const <Variant>[]) v.pricePaise];
  if (p == null || prices.isEmpty) return const [];
  return ref.watch(railsApiProvider).similar(p.category.slug, prices.reduce(math.min), p.id);
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
  final byId = {for (final c in await ref.watch(railsApiProvider).cards(ids)) c.id: c};
  return [for (final id in ids) ?byId[id]];
});
