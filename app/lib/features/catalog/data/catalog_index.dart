import '../../../core/models/models.dart';
import 'catalog.dart' show SearchParams, SearchSort;

// The catalog index docs (catalogIndex/public and /staff, docs/FIREBASE.md D3) searched on the phone: one read powers
// home, search, rails and the wishlist. Keys are short to keep the doc small (functions/src/model/catalog.ts
// CatalogCard): n name, s slug, b brand, bn brand name, c category, k kind, v variant names, p price, m MRP,
// i in stock, f featured, cv cover, col collections, t created millis, ft "Fits" values.

typedef IndexCards = Map<String, Map<String, dynamic>>;

/// The doc's `cards` map, typed (missing doc or field: empty).
IndexCards indexCards(Map<String, dynamic>? doc) => {
      for (final MapEntry(:key, :value) in ((doc?['cards'] as Map?) ?? const {}).entries)
        key as String: Map<String, dynamic>.from(value as Map),
    };

ProductCard cardOf(String id, Map<String, dynamic> c) => ProductCard(
      id: id,
      slug: c['s'] as String,
      name: c['n'] as String,
      brandName: c['bn'] as String,
      categorySlug: c['c'] as String,
      minPricePaise: (c['p'] as num).toInt(),
      mrpPaise: (c['m'] as num).toInt(),
      inStock: c['i'] == true,
      coverPath: c['cv'] as String?,
      isFeatured: c['f'] == true,
    );

final _wordSplit = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);

/// Lowercased words, split like prefixTsQuery (letters with their marks, so Hindi words stay whole).
List<String> words(String s) => s.toLowerCase().split(_wordSplit).where((w) => w.isNotEmpty).toList();

/// Every word typed is the start of a word in the name, brand, variant names or category ("sams gal" finds
/// "Samsung Galaxy"). Description text is not searched (docs/FIREBASE.md §1).
bool matchesQuery(Map<String, dynamic> c, List<String> query) {
  if (query.isEmpty) return true;
  final hay = words('${c['n']} ${c['bn']} ${c['v'] ?? ''} ${c['c']}');
  return query.every((q) => hay.any((w) => w.startsWith(q)));
}

int _byId(MapEntry<String, dynamic> a, MapEntry<String, dynamic> b) => a.key.compareTo(b.key);

/// [p]'s matches in the order today's search returns them: in stock first, then the sort, then id.
List<ProductCard> searchCards(IndexCards cards, SearchParams p) {
  final q = words(p.q).take(10).toList();
  final hits = cards.entries.where((e) {
    final c = e.value;
    return matchesQuery(c, q) &&
        (p.category == null || c['c'] == p.category) &&
        (p.brand == null || c['b'] == p.brand) &&
        (p.minPricePaise == null || (c['p'] as num) >= p.minPricePaise!) &&
        (p.maxPricePaise == null || (c['p'] as num) <= p.maxPricePaise!) &&
        (!p.inStock || c['i'] == true);
  }).toList();
  int flag(Object? v) => v == true ? 0 : 1;
  int numOf(MapEntry<String, Map<String, dynamic>> e, String k) => (e.value[k] as num).toInt();
  hits.sort((a, b) {
    final stocked = flag(a.value['i']) - flag(b.value['i']);
    if (stocked != 0) return stocked;
    final by = switch (p.sort) {
      // same shortcut as before: "relevance" is featured first, then name
      SearchSort.relevance => flag(a.value['f']) - flag(b.value['f']) != 0
          ? flag(a.value['f']) - flag(b.value['f'])
          : (a.value['n'] as String).compareTo(b.value['n'] as String),
      SearchSort.newest => numOf(b, 't') - numOf(a, 't'),
      SearchSort.priceAsc => numOf(a, 'p') - numOf(b, 'p'),
      SearchSort.priceDesc => numOf(b, 'p') - numOf(a, 'p'),
    };
    return by != 0 ? by : _byId(a, b);
  });
  return [for (final e in hits) cardOf(e.key, e.value)];
}

/// Home: featured (phones first, newest first) and "Deals under ₹1,500" (in-stock accessories, cheapest first).
({List<ProductCard> featured, List<ProductCard> accessories}) homeCards(IndexCards cards) {
  final all = cards.entries.toList();
  int t(MapEntry<String, Map<String, dynamic>> e) => (e.value['t'] as num).toInt();
  final featured = all.where((e) => e.value['f'] == true).toList()
    ..sort((a, b) {
      final kind = (a.value['k'] == 'phone' ? 0 : 1) - (b.value['k'] == 'phone' ? 0 : 1);
      return kind != 0 ? kind : (t(b) - t(a) != 0 ? t(b) - t(a) : _byId(a, b));
    });
  final deals = all.where((e) => e.value['k'] == 'accessory' && e.value['i'] == true && (e.value['p'] as num) <= 150000).toList()
    ..sort((a, b) => (a.value['p'] as num).compareTo(b.value['p'] as num) != 0
        ? (a.value['p'] as num).compareTo(b.value['p'] as num)
        : _byId(a, b));
  return (
    featured: [for (final e in featured.take(10)) cardOf(e.key, e.value)],
    accessories: [for (final e in deals.take(10)) cardOf(e.key, e.value)],
  );
}

/// The newest [n] products.
List<ProductCard> latestCards(IndexCards cards, [int n = 10]) {
  final all = cards.entries.toList()
    ..sort((a, b) {
      final t = (b.value['t'] as num).compareTo(a.value['t'] as num);
      return t != 0 ? t : b.key.compareTo(a.key);
    });
  return [for (final e in all.take(n)) cardOf(e.key, e.value)];
}

/// Accessories whose "Fits" spec names one of [names], in stock first, then cheapest.
List<ProductCard> fitsCards(IndexCards cards, Set<String> names, int n) {
  final hits = cards.entries.where((e) => ((e.value['ft'] as List?) ?? const []).any(names.contains)).toList()
    ..sort((a, b) {
      final s = (a.value['i'] == true ? 0 : 1) - (b.value['i'] == true ? 0 : 1);
      if (s != 0) return s;
      final p = (a.value['p'] as num).compareTo(b.value['p'] as num);
      return p != 0 ? p : _byId(a, b);
    });
  return [for (final e in hits.take(n)) cardOf(e.key, e.value)];
}
