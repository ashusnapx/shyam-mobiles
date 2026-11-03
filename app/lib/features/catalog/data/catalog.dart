import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/network.dart';
import '../../../core/supabase.dart' show cacheFor;
import 'catalog_repository.dart';

// shortcut: re-exported for offers.dart and search_query_test until Phase 2 deletes the Supabase side.
export 'catalog_repository_supabase.dart' show cardColumns, searchQuery;

const searchPageSize = 20;
const saverPageSize = 12; // data-saver mode

final categoriesProvider = FutureProvider<List<Category>>((ref) => ref.watch(catalogRepositoryProvider).categories());

final brandsProvider = FutureProvider<List<Brand>>((ref) => ref.watch(catalogRepositoryProvider).brands());

typedef HomeData = ({List<Category> categories, List<ProductCard> featured, List<ProductCard> accessories});

/// Saved on the phone: a cold start (or no signal) shows the last home at once and refreshes in the background.
final homeProvider = FutureProvider<HomeData>((ref) {
  final repo = ref.watch(catalogRepositoryProvider);
  return savedOrFetch(ref, 'home', () async => homeToJson(await repo.home()), homeFromJson);
});

/// [HomeData] as the saved copy stores it (the PostgREST row shapes, so copies saved by older builds still parse).
Map<String, Object?> homeToJson(HomeData h) => {
      'categories': [for (final c in h.categories) c.toJson()],
      'featured': [for (final c in h.featured) c.toJson()],
      'accessories': [for (final c in h.accessories) c.toJson()],
    };

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

/// Null when the slug doesn't exist or the product is hidden.
final productProvider = FutureProvider.autoDispose.family<Product?, String>((ref, slug) {
  cacheFor(ref, const Duration(minutes: 5));
  return ref.watch(catalogRepositoryProvider).product(slug);
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

/// [inStock]: only what can be bought now. Whatever the filters, in-stock rows come first.
typedef SearchParams = ({
  String q,
  String? category,
  String? brand,
  int? minPricePaise,
  int? maxPricePaise,
  bool inStock,
  SearchSort sort,
});

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
    final res = await ref.read(catalogRepositoryProvider).search(params, offset: offset, limit: size);
    return (res.items, res.total);
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
