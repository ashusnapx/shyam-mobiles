import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase.dart';
import 'admin.dart';

// Admin → Catalogue: every variant on one screen, with quick and bulk edits. Staff write variants/products
// directly (RLS "admin write"); hiding is the only removal, nothing is deleted.

const lowStockMax = 3; // same rule as admin_dashboard's low_stock
const maxStock = 99999;
const maxPricePaise = 100000000; // ₹10,00,000
const minPercent = -90, maxPercent = 300;

/// One variant with its product, as the Catalogue lists it.
class CatalogueRow {
  const CatalogueRow({
    required this.variantId,
    required this.productId,
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.pricePaise,
    required this.mrpPaise,
    required this.stock,
    required this.variantActive,
    required this.productActive,
    required this.featured,
    required this.categoryId,
    required this.brandId,
    required this.updatedAt,
    this.coverPath,
  });

  final String variantId;
  final String productId;
  final String productName;
  final String variantName;
  final String sku;
  final int pricePaise;
  final int mrpPaise;
  final int stock;
  final bool variantActive;
  final bool productActive;
  final bool featured; // product level
  final String categoryId;
  final String brandId;
  final DateTime updatedAt; // the later of the variant's and the product's
  final String? coverPath;

  /// Customers can see it: both the variant and its product are shown.
  bool get visible => variantActive && productActive;

  CatalogueRow copyWith({int? pricePaise, int? mrpPaise, int? stock, bool? variantActive, bool? featured}) => CatalogueRow(
        variantId: variantId,
        productId: productId,
        productName: productName,
        variantName: variantName,
        sku: sku,
        pricePaise: pricePaise ?? this.pricePaise,
        mrpPaise: mrpPaise ?? this.mrpPaise,
        stock: stock ?? this.stock,
        variantActive: variantActive ?? this.variantActive,
        productActive: productActive,
        featured: featured ?? this.featured,
        categoryId: categoryId,
        brandId: brandId,
        updatedAt: DateTime.now(),
        coverPath: coverPath,
      );
}

const catalogueColumns = 'id, name, is_active, is_featured, category_id, brand_id, updated_at, '
    'images:product_images(path, sort), '
    'variants(id, sku, name, price_paise, mrp_paise, stock, is_active, updated_at)';

/// Flattens `products.select(catalogueColumns)` into one row per variant.
List<CatalogueRow> catalogueRowsFrom(List<Map<String, dynamic>> products) => [
      for (final p in products)
        for (final v in [for (final v in p['variants'] as List) v as Map<String, dynamic>])
          CatalogueRow(
            variantId: v['id'],
            productId: p['id'],
            productName: p['name'],
            variantName: v['name'],
            sku: v['sku'],
            pricePaise: v['price_paise'],
            mrpPaise: v['mrp_paise'],
            stock: v['stock'],
            variantActive: v['is_active'],
            productActive: p['is_active'],
            featured: p['is_featured'],
            categoryId: p['category_id'],
            brandId: p['brand_id'],
            updatedAt: [DateTime.parse(v['updated_at']), DateTime.parse(p['updated_at'])].reduce((a, b) => a.isAfter(b) ? a : b),
            coverPath: coverOf(p['images'] as List),
          ),
    ];

/// The first photo by sort, as the product_cards view picks it.
String? coverOf(List<dynamic> images) {
  final sorted = [for (final i in images) i as Map<String, dynamic>]
    ..sort((a, b) => (a['sort'] as int).compareTo(b['sort'] as int));
  return sorted.isEmpty ? null : sorted.first['path'] as String;
}

// Summary -----------------------------------------------------------------------

typedef CatalogueSummary = ({int skus, int units, int valueAtPricePaise, int valueAtMrpPaise, int low, int out});

/// Totals for the rows on screen. Low is 1–3 left; out is 0 (each row counts in at most one).
CatalogueSummary summarize(Iterable<CatalogueRow> rows) {
  var skus = 0, units = 0, atPrice = 0, atMrp = 0, low = 0, out = 0;
  for (final r in rows) {
    skus++;
    units += r.stock;
    atPrice += r.pricePaise * r.stock;
    atMrp += r.mrpPaise * r.stock;
    if (r.stock == 0) {
      out++;
    } else if (r.stock <= lowStockMax) {
      low++;
    }
  }
  return (skus: skus, units: units, valueAtPricePaise: atPrice, valueAtMrpPaise: atMrp, low: low, out: out);
}

// Filter and sort ---------------------------------------------------------------

enum StockFilter {
  all('Any stock'),
  low('Low (1–3 left)'),
  out('Out of stock');

  const StockFilter(this.label);
  final String label;
}

enum VisibilityFilter {
  all('Shown and hidden'),
  shown('Shown in the shop'),
  hidden('Hidden');

  const VisibilityFilter(this.label);
  final String label;
}

enum CatalogueSort {
  name('Name'),
  stock('Stock, lowest first'),
  price('Price, lowest first'),
  updated('Recently updated');

  const CatalogueSort(this.label);
  final String label;
}

typedef CatalogueView = ({
  String query,
  String? categoryId,
  String? brandId,
  StockFilter stock,
  VisibilityFilter visibility,
  CatalogueSort sort,
});

const allRows = (
  query: '',
  categoryId: null,
  brandId: null,
  stock: StockFilter.all,
  visibility: VisibilityFilter.all,
  sort: CatalogueSort.name,
);

/// Search matches the product name, variant name or SKU, ignoring case. Ties sort by name.
List<CatalogueRow> applyView(List<CatalogueRow> rows, CatalogueView v) {
  final q = v.query.trim().toLowerCase();
  final shown = rows
      .where((r) =>
          (q.isEmpty || '${r.productName} ${r.variantName} ${r.sku}'.toLowerCase().contains(q)) &&
          (v.categoryId == null || r.categoryId == v.categoryId) &&
          (v.brandId == null || r.brandId == v.brandId) &&
          switch (v.stock) {
            StockFilter.all => true,
            StockFilter.low => r.stock > 0 && r.stock <= lowStockMax,
            StockFilter.out => r.stock == 0,
          } &&
          switch (v.visibility) {
            VisibilityFilter.all => true,
            VisibilityFilter.shown => r.visible,
            VisibilityFilter.hidden => !r.visible,
          })
      .toList();
  int byName(CatalogueRow a, CatalogueRow b) {
    final p = a.productName.toLowerCase().compareTo(b.productName.toLowerCase());
    return p != 0 ? p : a.variantName.toLowerCase().compareTo(b.variantName.toLowerCase());
  }

  int then(int c, CatalogueRow a, CatalogueRow b) => c != 0 ? c : byName(a, b);
  shown.sort(switch (v.sort) {
    CatalogueSort.name => byName,
    CatalogueSort.stock => (a, b) => then(a.stock.compareTo(b.stock), a, b),
    CatalogueSort.price => (a, b) => then(a.pricePaise.compareTo(b.pricePaise), a, b),
    CatalogueSort.updated => (a, b) => then(b.updatedAt.compareTo(a.updatedAt), a, b),
  });
  return shown;
}

// Bulk maths --------------------------------------------------------------------

/// Bulk price change by [amount] percent or whole rupees (negative lowers). Integer maths only, rounded half up
/// to whole rupees, then kept between ₹1 and the MRP.
int bulkPrice(int pricePaise, int mrpPaise, {required bool percent, required int amount}) {
  final rupees = percent
      ? (max(0, pricePaise * (100 + amount)) + 5000) ~/ 10000 // paise × 100 → rupees
      : (max(0, pricePaise + amount * 100) + 50) ~/ 100;
  return min(mrpPaise, max(100, rupees * 100));
}

enum StockOp { set, add, remove }

/// Never below 0 or above [maxStock].
int bulkStock(int stock, StockOp op, int n) => switch (op) {
      StockOp.set => n,
      StockOp.add => stock + n,
      StockOp.remove => stock - n,
    }.clamp(0, maxStock);

/// A planned change: the row as loaded and as it will be.
typedef RowChange = ({CatalogueRow before, CatalogueRow after});

// Data --------------------------------------------------------------------------

/// PostgREST's `max_rows` in supabase/config.toml; the hosted project has the same default.
const catalogueRowCap = 1000;

/// Every row, one page at a time: a single request stops silently at [catalogueRowCap], which would drop products
/// from the list and from the stock totals. A product added mid-load can repeat across pages, so ids are deduped.
Future<List<Map<String, dynamic>>> fetchAllPages(
  Future<List<Map<String, dynamic>>> Function(int from, int to) page, {
  int size = catalogueRowCap,
}) async {
  final byId = <Object?, Map<String, dynamic>>{};
  for (var from = 0;; from += size) {
    final rows = await page(from, from + size - 1);
    for (final r in rows) {
      byId[r['id']] = r;
    }
    if (rows.length < size) return [...byId.values];
  }
}

/// The row changed since this screen loaded it (an order sold one, another phone edited it), so nothing was written.
class StaleRowException implements Exception {
  const StaleRowException();
}

final catalogueProvider = AsyncNotifierProvider.autoDispose<CatalogueNotifier, List<CatalogueRow>>(CatalogueNotifier.new);

class CatalogueNotifier extends AsyncNotifier<List<CatalogueRow>> {
  @override
  Future<List<CatalogueRow>> build() async {
    cacheFor(ref, const Duration(minutes: 2)); // writes still in flight finish after the screen closes
    final db = ref.watch(supabaseProvider);
    // name alone isn't unique: id keeps the order stable from page to page
    final products = await fetchAllPages(
        (from, to) => db.from('products').select(catalogueColumns).order('name').order('id').range(from, to));
    return catalogueRowsFrom(products);
  }

  CatalogueRow? row(String variantId) => state.value?.where((r) => r.variantId == variantId).firstOrNull;

  /// Swaps rows in by variant id, so an edit or its rollback touches only its own rows.
  void _put(Iterable<CatalogueRow> rows) {
    final cur = state.value;
    if (!ref.mounted || cur == null) return;
    final byId = {for (final r in rows) r.variantId: r};
    state = AsyncData([for (final r in cur) byId[r.variantId] ?? r]);
  }

  /// Shows [after] at once and writes; on failure puts the rows back. A stale row also reloads the list (not on
  /// network errors: offline, a failed reload would swap the whole list for an error screen).
  Future<void> _optimistic(List<CatalogueRow> before, List<CatalogueRow> after, Future<void> Function() write) async {
    _put(after);
    try {
      await write();
    } catch (e) {
      _put(before);
      if (e is StaleRowException && ref.mounted) ref.invalidateSelf();
      rethrow;
    } finally {
      _changed();
    }
  }

  void _changed() {
    if (!ref.mounted) return;
    ref.invalidate(adminProductsProvider);
    ref.invalidate(adminProductProvider);
    ref.invalidate(adminDashboardProvider); // low stock
  }

  /// Writes the stock/price change of [c], only if the row still holds the value this screen showed.
  Future<void> _writeGuarded(SupabaseClient db, RowChange c) async {
    final (:before, :after) = c;
    final stock = after.stock != before.stock;
    var q = db.from('variants').update({
      if (stock) 'stock': after.stock,
      if (after.pricePaise != before.pricePaise) 'price_paise': after.pricePaise,
    }).eq('id', before.variantId);
    q = stock ? q.eq('stock', before.stock) : q.eq('price_paise', before.pricePaise);
    if ((await q.select('id')).isEmpty) throw const StaleRowException();
  }

  /// Inline −/+ or a typed number.
  Future<void> setStock(CatalogueRow row, int stock) {
    final db = ref.read(supabaseProvider);
    final change = (before: row, after: row.copyWith(stock: stock));
    return _optimistic([row], [change.after], () => _writeGuarded(db, change));
  }

  /// From the price sheet; the form already checked MRP ≥ price > 0 (the DB checks again).
  Future<void> setPrice(CatalogueRow row, int pricePaise, int mrpPaise) {
    final db = ref.read(supabaseProvider);
    return _optimistic([row], [row.copyWith(pricePaise: pricePaise, mrpPaise: mrpPaise)], () async {
      await db
          .from('variants')
          .update({'price_paise': pricePaise, 'mrp_paise': mrpPaise})
          .eq('id', row.variantId)
          .select('id')
          .single();
    });
  }

  /// Show/hide variants: one request.
  Future<void> setVisible(List<CatalogueRow> rows, bool active) {
    final db = ref.read(supabaseProvider);
    return _optimistic(rows, [for (final r in rows) r.copyWith(variantActive: active)],
        () => _updateIn(db, 'variants', {'is_active': active}, [for (final r in rows) r.variantId]));
  }

  /// Feature/unfeature the products of [rows] (every variant row of those products changes).
  Future<void> setFeatured(List<CatalogueRow> rows, bool featured) {
    final db = ref.read(supabaseProvider);
    final ids = {for (final r in rows) r.productId};
    final affected = [...?state.value?.where((r) => ids.contains(r.productId))];
    return _optimistic(affected, [for (final r in affected) r.copyWith(featured: featured)],
        () => _updateIn(db, 'products', {'is_featured': featured}, [...ids]));
  }

  /// The same stock count for every row (a stock take): one request.
  Future<void> setStockAll(List<CatalogueRow> rows, int stock) {
    final db = ref.read(supabaseProvider);
    return _optimistic(rows, [for (final r in rows) r.copyWith(stock: stock)],
        () => _updateIn(db, 'variants', {'stock': stock}, [for (final r in rows) r.variantId]));
  }

  /// Same change on many rows: one PATCH per 100 ids (keeps the URL near 4 KB).
  Future<void> _updateIn(SupabaseClient db, String table, Map<String, Object> fields, List<String> ids) async {
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, min(i + 100, ids.length));
      final done = await db.from(table).update(fields).inFilter('id', chunk).select('id');
      if (done.length != chunk.length) throw const StaleRowException(); // a row vanished, or RLS refused it
    }
  }

  /// A different value per row (add/remove stock, price changes): one guarded request each, in order. A row that
  /// changed meanwhile is skipped; a network or server error stops the run. Rows not saved go back to how they were.
  /// Returns each row that wasn't saved with the reason (null: not tried after the run stopped).
  Future<List<(RowChange, Object?)>> applyEach(List<RowChange> changes, void Function(int done) onProgress) async {
    final db = ref.read(supabaseProvider);
    _put([for (final c in changes) c.after]);
    final failed = <(RowChange, Object?)>[];
    var stale = false;
    for (final (i, c) in changes.indexed) {
      try {
        await _writeGuarded(db, c);
      } on StaleRowException catch (e) {
        stale = true;
        failed.add((c, e));
      } catch (e) {
        failed
          ..add((c, e))
          ..addAll([for (final rest in changes.skip(i + 1)) (rest, null)]);
        break;
      } finally {
        onProgress(i + 1);
      }
    }
    _put([for (final (c, _) in failed) c.before]);
    if (stale && ref.mounted) ref.invalidateSelf();
    _changed();
    return failed;
  }
}
