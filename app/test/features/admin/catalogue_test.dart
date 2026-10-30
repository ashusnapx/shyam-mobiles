import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/features/admin/data/catalogue.dart';

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

  test('admin_catalogue rows and totals parse, bigint stock values included', () {
    final r = CatalogueRow.fromJson({
      'variant_id': 'v1', 'product_id': 'p1', 'product_name': 'Samsung Galaxy S25', 'variant_name': '8 GB · 256 GB',
      'sku': 'SAM-S25', 'price_paise': 7499900, 'mrp_paise': 8099900, 'stock': 3, 'variant_active': true,
      'product_active': false, 'featured': true, 'category_id': 'c1', 'brand_id': 'b1',
      'updated_at': '2026-10-25T10:00:00Z', 'cover_path': 'p1/1.webp',
    });
    expect((r.variantId, r.visible, r.featured, r.coverPath), ('v1', false, true, 'p1/1.webp'));
    expect(r.updatedAt, DateTime.utc(2026, 10, 25, 10));
    final s = catalogueSummaryFromJson({
      'skus': 2, 'units': 120000, 'value_at_price_paise': 8999880000000, 'value_at_mrp_paise': 9719880000000,
      'low': 1, 'out': 0, 'total_skus': 40,
    });
    expect(s, (skus: 2, units: 120000, valueAtPricePaise: 8999880000000, valueAtMrpPaise: 9719880000000, low: 1, out: 0, total: 40));
  });
}
