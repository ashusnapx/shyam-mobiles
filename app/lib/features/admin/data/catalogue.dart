import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/paging.dart';
import '../../../core/supabase.dart';
import 'admin.dart';

// Admin → Catalogue: every variant, 50 at a time from `admin_catalogue` (search, filters, sort and totals run on
// the server), with quick and bulk edits on the loaded rows. Staff write variants/products directly (RLS "admin
// write"); hiding is the only removal, nothing is deleted.

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

  /// One `admin_catalogue` row.
  factory CatalogueRow.fromJson(Map<String, dynamic> j) => CatalogueRow(
        variantId: j['variant_id'],
        productId: j['product_id'],
        productName: j['product_name'],
        variantName: j['variant_name'],
        sku: j['sku'],
        pricePaise: j['price_paise'],
        mrpPaise: j['mrp_paise'],
        stock: j['stock'],
        variantActive: j['variant_active'],
        productActive: j['product_active'],
        featured: j['featured'],
        categoryId: j['category_id'],
        brandId: j['brand_id'],
        updatedAt: DateTime.parse(j['updated_at']),
        coverPath: j['cover_path'],
      );
}


// Summary -----------------------------------------------------------------------

/// Totals over every row the search and filters match (not just the loaded ones), and [total] SKUs in the shop.
/// Low is 1–3 left; out is 0.
typedef CatalogueSummary = ({int skus, int units, int valueAtPricePaise, int valueAtMrpPaise, int low, int out, int total});

CatalogueSummary catalogueSummaryFromJson(Map<String, dynamic> j) {
  int n(String k) => (j[k] as num).toInt(); // the stock values are bigint sums
  return (
    skus: n('skus'),
    units: n('units'),
    valueAtPricePaise: n('value_at_price_paise'),
    valueAtMrpPaise: n('value_at_mrp_paise'),
    low: n('low'),
    out: n('out'),
    total: n('total_skus'),
  );
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

/// `admin_catalogue`: a page of rows for a view, with the totals on the first page. A provider so tests can swap it.
class CatalogueApi {
  const CatalogueApi(this._db);

  final SupabaseClient _db;

  Future<Map<String, dynamic>> page(CatalogueView v, int offset, int limit) async =>
      await _db.rpc<Map<String, dynamic>>('admin_catalogue', params: {
        'p_query': v.query,
        'p_category_id': v.categoryId,
        'p_brand_id': v.brandId,
        'p_stock': v.stock.name,
        'p_visibility': v.visibility.name,
        'p_sort': v.sort.name,
        'p_offset': offset,
        'p_limit': limit,
      });
}

final catalogueApiProvider = Provider<CatalogueApi>((ref) => CatalogueApi(ref.watch(supabaseProvider)));

/// The totals card for a view. Its own one-row request, so an edit can refresh the totals without reloading pages.
final catalogueSummaryProvider = FutureProvider.autoDispose.family<CatalogueSummary, CatalogueView>((ref, v) async {
  cacheFor(ref, const Duration(minutes: 2));
  final j = await ref.watch(catalogueApiProvider).page(v, 0, 1);
  return catalogueSummaryFromJson(j['summary'] as Map<String, dynamic>);
});

/// The row changed since this screen loaded it (an order sold one, another phone edited it), so nothing was written.
class StaleRowException implements Exception {
  const StaleRowException();
}

/// The loaded pages of one view (search, filters, sort): a new view starts again at page 1.
final catalogueProvider =
    AsyncNotifierProvider.autoDispose.family<CatalogueNotifier, Paged<CatalogueRow>, CatalogueView>(CatalogueNotifier.new);

class CatalogueNotifier extends PagedNotifier<CatalogueRow> {
  CatalogueNotifier(this.view);

  final CatalogueView view;

  @override
  int get pageSize => 50;

  @override
  Object idOf(CatalogueRow r) => r.variantId;

  @override
  Future<Paged<CatalogueRow>> build() {
    cacheFor(ref, const Duration(minutes: 2)); // writes still in flight finish after the screen closes
    return super.build();
  }

  @override
  Future<List<CatalogueRow>> fetch(int from, int size) async {
    final j = await ref.read(catalogueApiProvider).page(view, from, size);
    return [for (final r in j['rows'] as List) CatalogueRow.fromJson(r as Map<String, dynamic>)];
  }

  CatalogueRow? row(String variantId) => state.value?.items.where((r) => r.variantId == variantId).firstOrNull;

  /// Swaps rows in by variant id, so an edit or its rollback touches only its own rows.
  void _put(Iterable<CatalogueRow> rows) {
    final byId = {for (final r in rows) r.variantId: r};
    replaceItems((items) => [for (final r in items) byId[r.variantId] ?? r]);
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
    ref.invalidate(catalogueSummaryProvider); // stock and values moved
    ref.invalidate(adminProductsProvider);
    ref.invalidate(adminProductPagesProvider);
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
    final affected = [...?state.value?.items.where((r) => ids.contains(r.productId))];
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
