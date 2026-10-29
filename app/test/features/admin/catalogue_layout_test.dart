// The Catalogue screen at 360x800 dp with large text: rows, summary, selection and the bulk bar must not overflow.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/admin.dart';
import 'package:shyam_mobiles/features/admin/data/catalogue.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_catalogue_screen.dart';

import '../repairs/layout_harness.dart';

class _Fixed extends CatalogueNotifier {
  _Fixed(this.rows);

  final List<CatalogueRow> rows;

  @override
  Future<List<CatalogueRow>> build() async => rows;

  @override
  Future<void> setVisible(List<CatalogueRow> rows, bool active) async {
    final ids = {for (final r in rows) r.variantId};
    state = AsyncData([for (final r in state.value!) ids.contains(r.variantId) ? r.copyWith(variantActive: active) : r]);
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

Future<void> _pump(WidgetTester tester) => pumpScreen(tester, const AdminCatalogueScreen(), overrides: [
      catalogueProvider.overrideWith(() => _Fixed(_rows)),
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
    await tester.tap(find.byTooltip('Select all shown'));
    await tester.pump();
    expect(find.text('3 variants selected'), findsOneWidget);
    await tester.tap(find.text('Bulk edit'));
    await tester.pumpAndSettle();
    expect(find.text('Lower price by %…'), findsOneWidget); // the action picker
  });

  testWidgets('filters narrow the list; nothing matching says so', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'samsung');
    await tester.pump();
    expect(find.text('Showing 1 of 3 variants'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'no such phone');
    await tester.pump();
    expect(find.text('Nothing matches'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
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
}
