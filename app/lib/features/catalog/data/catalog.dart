import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/network.dart';
import '../../../core/supabase.dart';

/// Columns of `product_cards` that [ProductCard] reads (skips the `search` tsvector).
const cardColumns =
    'id, slug, name, is_featured, category_slug, brand_name, min_price_paise, mrp_paise, in_stock, cover_path';

const searchPageSize = 20;
const saverPageSize = 12; // data-saver mode

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final rows = await ref.watch(supabaseProvider).from('categories').select().order('sort', ascending: true);
  return [for (final r in rows) Category.fromJson(r)];
});

final brandsProvider = FutureProvider<List<Brand>>((ref) async {
  final rows = await ref.watch(supabaseProvider).from('brands').select().order('name', ascending: true);
  return [for (final r in rows) Brand.fromJson(r)];
});

typedef HomeData = ({List<Category> categories, List<ProductCard> featured, List<ProductCard> accessories});

/// Saved on the phone: a cold start (or no signal) shows the last home at once and refreshes in the background.
final homeProvider = FutureProvider<HomeData>((ref) {
  final db = ref.watch(supabaseProvider);
  return savedOrFetch(ref, 'home', () async {
    final (categories, featured, accessories) = await (
      db.from('categories').select().order('sort', ascending: true),
      // phones first (enum order), so the hero is a phone when one is featured
      db
          .from('product_cards')
          .select(cardColumns)
          .eq('is_featured', true)
          .order('category_kind', ascending: true)
          .order('created_at')
          .order('id', ascending: true)
          .limit(10),
      db
          .from('product_cards')
          .select(cardColumns)
          .eq('category_kind', 'accessory')
          .lte('min_price_paise', 150000)
          .order('min_price_paise', ascending: true)
          .order('id', ascending: true)
          .limit(4),
    ).wait;
    return {'categories': categories, 'featured': featured, 'accessories': accessories};
  }, homeFromJson);
});

/// The saved/fetched home payload (PostgREST rows by section) as [HomeData].
HomeData homeFromJson(Object? json) {
  final j = json! as Map<String, dynamic>;
  List<Map<String, dynamic>> rows(String k) => [for (final r in j[k] as List) r as Map<String, dynamic>];
  return (
    categories: [for (final r in rows('categories')) Category.fromJson(r)],
    featured: [for (final r in rows('featured')) ProductCard.fromJson(r)],
    accessories: [for (final r in rows('accessories')) ProductCard.fromJson(r)],
  );
}

/// Null when the slug doesn't exist or the product is inactive (RLS hides it).
final productProvider = FutureProvider.autoDispose.family<Product?, String>((ref, slug) async {
  cacheFor(ref, const Duration(minutes: 5));
  final row = await ref
      .watch(supabaseProvider)
      .from('products')
      .select('*, brand:brands(*), category:categories(*), images:product_images(*), variants(*)')
      .eq('slug', slug)
      .maybeSingle();
  return row == null ? null : Product.fromJson(row);
});

// Search ----------------------------------------------------------------------

enum SearchSort {
  relevance('relevance', 'Relevance'),
  newest('newest', 'Newest'),
  priceAsc('price_asc', 'Price: low to high'),
  priceDesc('price_desc', 'Price: high to low');

  const SearchSort(this.param, this.label);

  final String param; // value of the `sort` route parameter
  final String label;

  static SearchSort parse(String? param) => values.firstWhere((s) => s.param == param, orElse: () => relevance);
}

typedef SearchParams = ({String q, String? category, String? brand, int? maxPricePaise, SearchSort sort});

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
  if (p.maxPricePaise != null) q = q.lte('min_price_paise', p.maxPricePaise!);
  final sorted = switch (p.sort) {
    // shortcut: no ts_rank through PostgREST, so "relevance" is featured first; needs an RPC for real ranking
    SearchSort.relevance => q.order('is_featured').order('name', ascending: true),
    SearchSort.newest => q.order('created_at'),
    SearchSort.priceAsc => q.order('min_price_paise', ascending: true),
    SearchSort.priceDesc => q.order('min_price_paise'),
  };
  return sorted.order('id', ascending: true).range(offset, offset + pageSize - 1);
}

/// [moreFailed]: the last next-page load failed; paging pauses until a retry.
typedef SearchResults = ({List<ProductCard> items, int total, bool moreFailed});

final searchProvider = AsyncNotifierProvider.autoDispose.family<SearchNotifier, SearchResults, SearchParams>(
  SearchNotifier.new,
);

class SearchNotifier extends AsyncNotifier<SearchResults> {
  SearchNotifier(this.params);

  final SearchParams params;
  bool _loadingMore = false;

  @override
  Future<SearchResults> build() async {
    cacheFor(ref, const Duration(minutes: 5));
    final (items, total) = await _page(0);
    return (items: items, total: total, moreFailed: false);
  }

  Future<(List<ProductCard>, int)> _page(int offset) async {
    final size = ref.read(dataSaverProvider) == DataMode.saver ? saverPageSize : searchPageSize;
    final res = await searchQuery(ref.read(supabaseProvider).from('product_cards'), params, offset: offset, pageSize: size)
        .count(CountOption.exact);
    return ([for (final r in res.data) ProductCard.fromJson(r)], res.count);
  }

  /// Appends the next page. No-op while one is loading, when all rows are loaded, or after a failure unless [retry].
  Future<void> loadMore({bool retry = false}) async {
    final cur = state.value;
    if (cur == null || _loadingMore || cur.items.length >= cur.total || (cur.moreFailed && !retry)) return;
    _loadingMore = true;
    if (retry) state = AsyncData((items: cur.items, total: cur.total, moreFailed: false));
    try {
      final (items, total) = await _page(cur.items.length);
      if (ref.mounted) state = AsyncData((items: [...cur.items, ...items], total: total, moreFailed: false));
    } catch (_) {
      if (ref.mounted) state = AsyncData((items: cur.items, total: cur.total, moreFailed: true));
    } finally {
      _loadingMore = false;
    }
  }
}

/// "sams gal" → "sams:* & gal:*" so results appear while the customer is still typing.
/// Strips everything but letters, their marks (Hindi vowel signs: "सैमसंग" stays one word) and digits, so tsquery
/// syntax (& | ! ( ) : * ' \) and PostgREST's , . ( ) in input can't break or widen the query. At most 10 words.
String? prefixTsQuery(String input) {
  final words =
      input.toLowerCase().split(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true)).where((w) => w.isNotEmpty).take(10);
  return words.isEmpty ? null : words.map((w) => '$w:*').join(' & ');
}
