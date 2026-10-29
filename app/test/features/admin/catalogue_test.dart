import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/features/admin/data/catalogue.dart';

CatalogueRow row(
  String id, {
  String product = 'Samsung Galaxy S25',
  String variant = '8 GB · 256 GB',
  String sku = 'SAM-S25',
  int price = 7499900,
  int mrp = 8099900,
  int stock = 5,
  bool active = true,
  bool productActive = true,
  String category = 'phones',
  String brand = 'samsung',
  int updatedDay = 1,
}) =>
    CatalogueRow(
      variantId: id,
      productId: 'p-$product',
      productName: product,
      variantName: variant,
      sku: sku,
      pricePaise: price,
      mrpPaise: mrp,
      stock: stock,
      variantActive: active,
      productActive: productActive,
      featured: false,
      categoryId: category,
      brandId: brand,
      updatedAt: DateTime(2026, 10, updatedDay),
    );

void main() {
  group('bulkPrice: whole rupees, never under ₹1 or over the MRP', () {
    // (price, mrp, percent?, amount) → new price, all paise
    const table = <(int, int, bool, int, int)>[
      (7499900, 8099900, true, -10, 6749900), // ₹74,999 −10% = ₹67,499.10 → ₹67,499
      (7499900, 8099900, true, 5, 7874900), // +5% = ₹78,748.95 → ₹78,749
      (7499900, 8099900, true, 20, 8099900), // would pass the MRP: stops at it
      (4950, 9900, true, 10, 5400), // ₹49.50 +10% = ₹54.45 → ₹54
      (4950, 9900, true, -1, 4900), // ₹49.005 → ₹49
      (10000, 20000, true, -90, 1000), // ₹100 −90% = ₹10
      (150, 1000, true, -90, 100), // ₹0.15 → never under ₹1
      (7499900, 8099900, false, -500, 7449900), // −₹500
      (7499900, 8099900, false, 10000, 8099900), // +₹10,000 passes the MRP: stops at it
      (4950, 9900, false, 10, 6000), // ₹59.50 rounds half up to ₹60
      (50000, 60000, false, -1000, 100), // −₹1,000 on ₹500: floor of ₹1
      (12345, 12345, true, 0, 12300), // ₹123.45: paise are rounded away
      (99999900, 100000000, true, 300, 100000000), // +300% capped by MRP
    ];
    for (final (price, mrp, percent, amount, want) in table) {
      test('$price ${percent ? '$amount%' : '₹$amount'} (MRP $mrp) → $want', () {
        final got = bulkPrice(price, mrp, percent: percent, amount: amount);
        expect(got, want);
        expect(got >= 100 || got == mrp, isTrue);
        expect(got <= mrp, isTrue);
      });
    }
  });

  test('bulkStock stays within 0..99,999', () {
    expect(bulkStock(5, StockOp.set, 12), 12);
    expect(bulkStock(5, StockOp.add, 3), 8);
    expect(bulkStock(5, StockOp.remove, 3), 2);
    expect(bulkStock(2, StockOp.remove, 5), 0);
    expect(bulkStock(0, StockOp.add, -1), 0);
    expect(bulkStock(99998, StockOp.add, 5), maxStock);
    expect(bulkStock(5, StockOp.set, 999999), maxStock);
  });

  group('summarize', () {
    const table = <(List<(int, int, int)>, CatalogueSummary)>[
      ([], (skus: 0, units: 0, valueAtPricePaise: 0, valueAtMrpPaise: 0, low: 0, out: 0)),
      (
        [(100000, 120000, 2), (50000, 50000, 0), (1000, 1500, 10), (2000, 2000, 3)],
        (skus: 4, units: 15, valueAtPricePaise: 200000 + 10000 + 6000, valueAtMrpPaise: 240000 + 15000 + 6000, low: 2, out: 1),
      ),
    ];
    for (final (rows, want) in table) {
      test('${rows.length} rows', () {
        final input = [
          for (final (i, (price, mrp, stock)) in rows.indexed) row('$i', price: price, mrp: mrp, stock: stock),
        ];
        expect(summarize(input), want);
      });
    }
  });

  group('applyView', () {
    final rows = [
      row('a', product: 'Samsung Galaxy S25', sku: 'SAM-S25-NVY', price: 7499900, stock: 8, updatedDay: 3),
      row('b', product: 'Redmi Note 14', sku: 'XI-RN14', brand: 'xiaomi', price: 1999900, stock: 0, updatedDay: 9),
      row('c', product: 'Spigen Case', sku: 'SPG-01', category: 'cases', brand: 'spigen', price: 129900, stock: 2, active: false),
      row('d', product: 'apple iPhone 16', sku: 'APL-16', brand: 'apple', price: 7990000, stock: 3, productActive: false, updatedDay: 5),
    ];
    List<String> ids(CatalogueView v) => [for (final r in applyView(rows, v)) r.variantId];
    CatalogueView view({
      String q = '',
      String? category,
      String? brand,
      StockFilter stock = StockFilter.all,
      VisibilityFilter visibility = VisibilityFilter.all,
      CatalogueSort sort = CatalogueSort.name,
    }) =>
        (query: q, categoryId: category, brandId: brand, stock: stock, visibility: visibility, sort: sort);

    final table = <(String, CatalogueView, List<String>)>[
      ('everything by name, ignoring case', view(), ['d', 'b', 'a', 'c']),
      ('search by name', view(q: 'galaxy'), ['a']),
      ('search by SKU', view(q: 'xi-rn'), ['b']),
      ('category', view(category: 'cases'), ['c']),
      ('brand', view(brand: 'xiaomi'), ['b']),
      ('low is 1–3 left', view(stock: StockFilter.low), ['d', 'c']),
      ('out is 0', view(stock: StockFilter.out), ['b']),
      ('shown needs variant and product shown', view(visibility: VisibilityFilter.shown), ['b', 'a']),
      ('hidden: either one hidden', view(visibility: VisibilityFilter.hidden), ['d', 'c']),
      ('stock, lowest first', view(sort: CatalogueSort.stock), ['b', 'c', 'd', 'a']),
      ('price, lowest first', view(sort: CatalogueSort.price), ['c', 'b', 'a', 'd']),
      ('recently updated first', view(sort: CatalogueSort.updated), ['b', 'd', 'a', 'c']),
      ('filters combine', view(q: 's', stock: StockFilter.low, visibility: VisibilityFilter.hidden), ['c']),
    ];
    for (final (name, v, want) in table) {
      test(name, () => expect(ids(v), want));
    }
  });

  test('catalogueRowsFrom flattens products into variant rows', () {
    final rows = catalogueRowsFrom([
      {
        'id': 'p1',
        'name': 'Samsung Galaxy S25',
        'is_active': true,
        'is_featured': true,
        'category_id': 'c1',
        'brand_id': 'b1',
        'updated_at': '2026-10-20T10:00:00Z',
        'images': [
          {'path': 'p1/2.webp', 'sort': 1},
          {'path': 'p1/1.webp', 'sort': 0},
        ],
        'variants': [
          {'id': 'v1', 'sku': 'S1', 'name': '8/128', 'price_paise': 100, 'mrp_paise': 200, 'stock': 1, 'is_active': true, 'updated_at': '2026-10-25T10:00:00Z'},
          {'id': 'v2', 'sku': 'S2', 'name': '8/256', 'price_paise': 300, 'mrp_paise': 400, 'stock': 0, 'is_active': false, 'updated_at': '2026-10-01T10:00:00Z'},
        ],
      },
      {
        'id': 'p2', 'name': 'No variants yet', 'is_active': true, 'is_featured': false, 'category_id': 'c1',
        'brand_id': 'b1', 'updated_at': '2026-10-20T10:00:00Z', 'images': <Object>[], 'variants': <Object>[],
      },
    ]);
    expect([for (final r in rows) r.variantId], ['v1', 'v2']);
    expect(rows.first.coverPath, 'p1/1.webp');
    expect(rows.first.featured, isTrue);
    expect(rows.first.updatedAt, DateTime.utc(2026, 10, 25, 10)); // the variant's, it's later
    expect(rows.last.updatedAt, DateTime.utc(2026, 10, 20, 10)); // the product's, it's later
    expect(rows.last.visible, isFalse);
  });

  test('fetchAllPages keeps asking until a short page, and drops repeats', () async {
    final asked = <(int, int)>[];
    final all = [for (var i = 0; i < 5; i++) {'id': 'p$i'}];
    final got = await fetchAllPages((from, to) async {
      asked.add((from, to));
      // a product added at the top after the first page shifts the rest along: p1 comes again on page two
      final now = from == 0 ? all : [{'id': 'new'}, ...all];
      return now.sublist(from.clamp(0, now.length), (to + 1).clamp(0, now.length));
    }, size: 2);
    expect(asked, [(0, 1), (2, 3), (4, 5), (6, 7)]);
    expect([for (final r in got) r['id']], ['p0', 'p1', 'p2', 'p3', 'p4']);
  });
}
