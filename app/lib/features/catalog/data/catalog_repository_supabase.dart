import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import 'catalog.dart' show HomeData, SearchParams, SearchSort, prefixTsQuery, searchPageSize;
import 'catalog_repository.dart';
import 'rails.dart' show closestByPrice, railSize;

/// Columns of `product_cards` that [ProductCard] reads (skips the `search` tsvector).
const cardColumns =
    'id, slug, name, is_featured, category_slug, brand_name, min_price_paise, mrp_paise, in_stock, cover_path';

/// One page of `product_cards` for [p], starting at row [offset]. Always ends on `id` so paging is stable.
PostgrestTransformBuilder<PostgrestList> searchQuery(
  PostgrestQueryBuilder table,
  SearchParams p, {
  int offset = 0,
  int pageSize = searchPageSize,
}) {
  var q = table.select(cardColumns);
  final tsquery = prefixTsQuery(p.q);
  if (tsquery != null) q = q.textSearch('search', tsquery, config: 'simple');
  if (p.category != null) q = q.eq('category_slug', p.category!);
  if (p.brand != null) q = q.eq('brand_slug', p.brand!);
  if (p.minPricePaise != null) q = q.gte('min_price_paise', p.minPricePaise!);
  if (p.maxPricePaise != null) q = q.lte('min_price_paise', p.maxPricePaise!);
  if (p.inStock) q = q.eq('in_stock', true);
  final stocked = q.order('in_stock'); // what can be bought first, in every sort
  final sorted = switch (p.sort) {
    // shortcut: no ts_rank through PostgREST, so "relevance" is featured first; needs an RPC for real ranking
    SearchSort.relevance => stocked.order('is_featured').order('name', ascending: true),
    SearchSort.newest => stocked.order('created_at'),
    SearchSort.priceAsc => stocked.order('min_price_paise', ascending: true),
    SearchSort.priceDesc => stocked.order('min_price_paise'),
  };
  return sorted.order('id', ascending: true).range(offset, offset + pageSize - 1);
}

/// Today's PostgREST reads (RLS hides inactive products), moved here unchanged. Deleted in Phase 2.
class SupabaseCatalogRepository implements CatalogRepository {
  const SupabaseCatalogRepository(this._db);

  final SupabaseClient _db;

  List<ProductCard> _cards(PostgrestList rows) => [for (final r in rows) ProductCard.fromJson(r)];

  @override
  Future<List<Category>> categories() async =>
      [for (final r in await _db.from('categories').select().order('sort', ascending: true)) Category.fromJson(r)];

  @override
  Future<List<Brand>> brands() async =>
      [for (final r in await _db.from('brands').select().order('name', ascending: true)) Brand.fromJson(r)];

  @override
  Future<HomeData> home() async {
    final (categories, featured, accessories) = await (
      _db.from('categories').select().order('sort', ascending: true),
      // phones first (enum order), so the hero is a phone when one is featured
      _db
          .from('product_cards')
          .select(cardColumns)
          .eq('is_featured', true)
          .order('category_kind', ascending: true)
          .order('created_at')
          .order('id', ascending: true)
          .limit(10),
      _db
          .from('product_cards')
          .select(cardColumns)
          .eq('category_kind', 'accessory')
          .eq('in_stock', true) // a deal you can't buy isn't one
          .lte('min_price_paise', 150000)
          .order('min_price_paise', ascending: true)
          .order('id', ascending: true)
          .limit(10), // Home's "Deals under ₹1,500" rail
    ).wait;
    return (
      categories: [for (final r in categories) Category.fromJson(r)],
      featured: _cards(featured),
      accessories: _cards(accessories),
    );
  }

  @override
  Future<Product?> product(String slug) async {
    final row = await _db
        .from('products')
        .select('*, brand:brands(*), category:categories(*), images:product_images(*), variants(*)')
        .eq('slug', slug)
        .maybeSingle();
    return row == null ? null : Product.fromJson(row);
  }

  @override
  Future<({List<ProductCard> items, int total})> search(SearchParams params, {required int offset, required int limit}) async {
    final res = await searchQuery(_db.from('product_cards'), params, offset: offset, pageSize: limit).count(CountOption.exact);
    return (items: _cards(res.data), total: res.count);
  }

  @override
  Future<List<ProductCard>> cards(List<String> ids) async =>
      _cards(await _db.from('product_cards').select(cardColumns).inFilter('id', ids));

  @override
  Future<List<ProductCard>> fits(Set<String> names) async {
    final hits = await Future.wait([
      for (final n in names)
        _db.from('products').select('id').filter('specs', 'cs', jsonEncode([{'label': 'Fits', 'value': n}])).limit(40),
    ]);
    final ids = {for (final rows in hits) for (final r in rows) r['id'] as String};
    if (ids.isEmpty) return const [];
    return _cards(await _db
        .from('product_cards')
        .select(cardColumns)
        .inFilter('id', ids.toList())
        .order('in_stock')
        .order('min_price_paise', ascending: true)
        .order('id', ascending: true)
        .limit(railSize));
  }

  @override
  Future<List<ProductCard>> similar(String categorySlug, int pricePaise, String excludeId) async {
    PostgrestFilterBuilder<PostgrestList> base() =>
        _db.from('product_cards').select(cardColumns).eq('category_slug', categorySlug).neq('id', excludeId);
    final (above, below) = await (
      base().gte('min_price_paise', pricePaise).order('min_price_paise', ascending: true).limit(railSize),
      base().lt('min_price_paise', pricePaise).order('min_price_paise').limit(railSize),
    ).wait;
    return closestByPrice(_cards([...above, ...below]), pricePaise);
  }

  @override
  Future<List<ProductCard>> latest() async =>
      _cards(await _db.from('product_cards').select(cardColumns).order('created_at').order('id').limit(10));

  @override
  Future<List<Variant>> variants(List<String> ids) async =>
      [for (final r in await _db.from('variants').select().inFilter('id', ids).eq('is_active', true)) Variant.fromJson(r)];
}
