// The Catalogue screen at 360x800 dp with large text: rows, summary, selection and the bulk bar must not overflow;
// pages of 50 load on scroll from admin_catalogue (a fake here), and a new search or filter starts at page 1.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/admin.dart';
import 'package:shyam_mobiles/features/admin/data/catalogue.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_catalogue_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../repairs/layout_harness.dart';

/// admin_catalogue over [rows]: search, the stock filter, paging and the totals, like the SQL.
class _Api implements CatalogueApi {
  _Api(this.rows);

  final List<CatalogueRow> rows;
  final calls = <String>[]; // "query|stock|offset"
  bool failNextPage = false;

  @override
  Future<Map<String, dynamic>> page(CatalogueView v, int offset, int limit) async {
    if (limit > 1) calls.add('${v.query}|${v.stock.name}|$offset'); // limit 1 is the totals card
    if (failNextPage && offset > 0) {
      failNextPage = false;
      throw const PostgrestException(message: 'boom', code: '500');
    }
    final q = v.query.toLowerCase();
    final match = [
      for (final r in rows)
        if ((q.isEmpty || '${r.productName} ${r.variantName} ${r.sku}'.toLowerCase().contains(q)) &&
            switch (v.stock) {
              StockFilter.all => true,
              StockFilter.low => r.stock >= 1 && r.stock <= 3,
              StockFilter.out => r.stock == 0,
            })
          r,
    ];
    int sum(int Function(CatalogueRow) f) => match.fold(0, (a, r) => a + f(r));
    return {
      'rows': [
        for (final r in match.skip(offset).take(limit))
          {
            'variant_id': r.variantId, 'product_id': r.productId, 'product_name': r.productName,
            'variant_name': r.variantName, 'sku': r.sku, 'price_paise': r.pricePaise, 'mrp_paise': r.mrpPaise,
            'stock': r.stock, 'variant_active': r.variantActive, 'product_active': r.productActive,
            'featured': r.featured, 'category_id': r.categoryId, 'brand_id': r.brandId,
            'updated_at': r.updatedAt.toIso8601String(), 'cover_path': r.coverPath,
          },
      ],
      'summary': offset > 0
          ? null
          : {
              'skus': match.length,
              'units': sum((r) => r.stock),
              'value_at_price_paise': sum((r) => r.pricePaise * r.stock),
              'value_at_mrp_paise': sum((r) => r.mrpPaise * r.stock),
              'low': match.where((r) => r.stock >= 1 && r.stock <= 3).length,
              'out': match.where((r) => r.stock == 0).length,
              'total_skus': rows.length,
            },
    };
  }
}

/// Hiding writes to the DB; here it just changes the loaded row.
class _Fixed extends CatalogueNotifier {
  _Fixed(super.view);

  @override
  Future<void> setVisible(List<CatalogueRow> rows, bool active) async {
    final ids = {for (final r in rows) r.variantId};
    replaceItems((items) => [for (final r in items) ids.contains(r.variantId) ? r.copyWith(variantActive: active) : r]);
  }
}

CatalogueRow _row(String id, String product, String variant, String sku, int rupees, int stock,
        {bool active = true, bool productActive = true, bool featured = false}) =>
    CatalogueRow(
      variantId: id,
      productId: 'p-$product',
      productName: product,
      variantName: variant,
      sku: sku,
      pricePaise: rupees * 100,
      mrpPaise: rupees * 108,
      stock: stock,
      variantActive: active,
      productActive: productActive,
      featured: featured,
      categoryId: 'c1',
      brandId: 'b1',
      updatedAt: DateTime(2026, 10, 29),
    );

final _rows = [
  _row('v1', 'Samsung Galaxy S25 Ultra 5G', '12 GB · 512 GB · Titanium Silverblue', 'SAM-S25U-12-512-SLV', 141999, 99999,
      featured: true),
  _row('v2', 'Xiaomi Redmi Note 14 Pro+ 5G', '8 GB · 256 GB · Phantom Purple', 'XIA-RN14PP-8-256-PRP', 29999, 2,
      productActive: false),
  _row('v3', 'Spigen Ultra Hybrid Case for iPhone 16 Pro Max', 'Crystal Clear', 'SPG-UH-IP16PM-CLR', 1299, 0, active: false),
];

Future<void> _pump(WidgetTester tester, {List<CatalogueRow>? rows, _Api? api}) => pumpScreen(tester, const AdminCatalogueScreen(), overrides: [
      catalogueApiProvider.overrideWithValue(api ?? _Api(rows ?? _rows)),
      catalogueProvider.overrideWith2(_Fixed.new),
      adminCategoriesProvider.overrideWithValue(
          const AsyncData([Category(id: 'c1', slug: 'smartphones', name: 'Smartphones', kind: CategoryKind.phone)])),
      adminBrandsProvider.overrideWithValue(const AsyncData([Brand(id: 'b1', slug: 'samsung', name: 'Samsung')])),
    ]);

void main() {
  testWidgets('summary and rows fit at 360 dp with large text', (tester) async {
    await _pump(tester);
    expect(find.text('Catalogue'), findsOneWidget);
    expect(find.byType(CatalogueSummaryCard), findsOneWidget);
    expect(find.text('3'), findsWidgets); // SKUs
    expect(find.text('Stock value at MRP'), findsOneWidget);
    expect(find.text('99999'), findsOneWidget); // the widest stock count
    expect(find.text('Featured'), findsOneWidget);
    // the list, not the search field or the filter chips (both scroll too)
    final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Product hidden'), 300, scrollable: list);
    await tester.scrollUntilVisible(find.textContaining('SPG-UH-IP16PM-CLR'), 300, scrollable: list);
    expect(find.text('Hidden'), findsOneWidget);
    expect(find.text('Out of stock'), findsWidgets);
  });

  testWidgets('selecting rows shows checkboxes and the bulk bar', (tester) async {
    await _pump(tester);
    expect(find.text('Bulk edit'), findsNothing);
    await tester.longPress(find.textContaining('SAM-S25U-12-512-SLV'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('1 variant selected'), findsOneWidget);
    expect(find.text('Bulk edit'), findsOneWidget);
    expect(find.byType(Checkbox), findsWidgets);
    await tester.tap(find.byTooltip('Select all loaded'));
    await tester.pump();
    expect(find.text('3 variants selected'), findsOneWidget);
    await tester.tap(find.text('Bulk edit'));
    await tester.pumpAndSettle();
    expect(find.text('Lower price by %…'), findsOneWidget); // the action picker
  });

  testWidgets('filters narrow the list; nothing matching says so', (tester) async {
    final api = _Api(_rows);
    await _pump(tester, api: api);
    await tester.enterText(find.byType(TextField), 's');
    await tester.enterText(find.byType(TextField), 'samsung');
    await tester.pump(const Duration(milliseconds: 350)); // the search waits for a pause in typing
    await tester.pump();
    expect(find.text('Showing 1 of 3 variants'), findsOneWidget, reason: 'the server’s totals for the search');
    expect(api.calls, ['|all|0', 'samsung|all|0'], reason: 'one request for the search, not one per letter');
    await tester.enterText(find.byType(TextField), 'no such phone');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('Nothing matches'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Nothing matches'), findsNothing);
    expect(find.text('Showing 1 of 3 variants'), findsNothing); // all shown again
  });

  testWidgets('hiding a variant from its card offers Undo', (tester) async {
    await _pump(tester);
    const sku = 'SAM-S25U-12-512-SLV';
    await tester.tap(find.byTooltip('Hide $sku from the shop'));
    await tester.pumpAndSettle();
    expect(find.text('$sku hidden from the shop'), findsOneWidget);
    expect(find.byTooltip('Show $sku in the shop'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide $sku from the shop'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // let the last message time out
  });

  testWidgets('pages of 50 load on scroll; a failed page offers a retry; a filter starts again at page 1', (tester) async {
    final many = [
      for (var i = 0; i < 120; i++)
        _row('v$i', 'Phone ${i.toString().padLeft(3, '0')}', '8 GB · 128 GB', 'SKU-$i', 9999, i % 7),
    ];
    final api = _Api(many);
    await _pump(tester, api: api);
    expect(find.text('120'), findsWidgets, reason: 'SKUs from the server, not the 50 loaded');
    expect(api.calls, ['|all|0']);

    final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    api.failNextPage = true;
    await tester.scrollUntilVisible(find.text('Couldn’t load more. Try again'), 600, scrollable: list);
    expect(api.calls, ['|all|0', '|all|50'], reason: 'page 2 asked for once, near the end of page 1');
    await tester.drag(list, const Offset(0, -300));
    await tester.pump();
    expect(api.calls, hasLength(2), reason: 'no retrying on its own while failed');

    await tester.tap(find.text('Couldn’t load more. Try again'));
    await tester.pumpAndSettle();
    expect(api.calls.last, '|all|50');
    await tester.scrollUntilVisible(find.text('8 GB · 128 GB · SKU-119'), 600, scrollable: list);
    expect(api.calls.last, '|all|100');
    expect(find.text('Couldn’t load more. Try again'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'all 120 loaded');

    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(StockFilter.out.label).last); // the sheet's, over the rows' tags
    await tester.pumpAndSettle();
    expect(api.calls.last, '|out|0', reason: 'a new filter is a new list from page 1');
    expect(find.text('Showing 18 of 120 variants'), findsOneWidget);
  });
}
