import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/cart/screens/cart_screen.dart';

CartLine _line({int qty = 1, int stock = 10, bool variantActive = true, bool productActive = true}) => CartLine(
      variant: Variant(
        id: 'v1',
        productId: 'p1',
        sku: 'S',
        name: '8 GB · 128 GB',
        pricePaise: 100000,
        mrpPaise: 100000,
        stock: stock,
        isActive: variantActive,
      ),
      qty: qty,
      productId: 'p1',
      productSlug: 'phone',
      productName: 'Phone',
      productActive: productActive,
    );

void main() {
  test('fine line: no warning', () {
    expect(lineWarning(_line(qty: 2, stock: 10)), isNull);
  });

  test('inactive product or variant: no longer available', () {
    expect(lineWarning(_line(productActive: false)), (text: 'No longer available', blocking: true));
    expect(lineWarning(_line(variantActive: false)), (text: 'No longer available', blocking: true));
  });

  test('stock below qty blocks; low stock only informs', () {
    expect(lineWarning(_line(qty: 3, stock: 2)), (text: 'Only 2 left', blocking: true));
    expect(lineWarning(_line(qty: 1, stock: 0)), (text: 'Out of stock', blocking: true));
    expect(lineWarning(_line(qty: 1, stock: 1)), (text: 'Only 1 left', blocking: false));
  });

  test('blocking always matches CartLine.purchasable (what place_order checks)', () {
    for (final active in [true, false]) {
      for (final stock in [0, 1, 2, 3, 4, 9]) {
        for (final qty in [1, 2, 3, 5]) {
          final l = _line(qty: qty, stock: stock, variantActive: active);
          expect(lineWarning(l)?.blocking ?? false, !l.purchasable, reason: 'active=$active stock=$stock qty=$qty');
        }
      }
    }
  });
}
