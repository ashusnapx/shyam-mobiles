// Every number the app shows or previews, checked against the server's own arithmetic (place_order in
// supabase/migrations/20261028000200_rpcs.sql). The server is the source of truth; these pin the mirror.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/format.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/theme/theme.dart';
import 'package:shyam_mobiles/core/widgets/widgets.dart';
import 'package:shyam_mobiles/features/admin/data/rules.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/catalog/screens/product_screen.dart';
import 'package:shyam_mobiles/features/checkout/screens/checkout_screen.dart';

StoreSettings _settings({int fee = 4900, int freeMin = 99900, bool cod = true, int codMax = 2500000}) => StoreSettings(
      deliveryFeePaise: fee,
      freeDeliveryMinPaise: freeMin,
      codEnabled: cod,
      codMaxPaise: codMax,
      storePhone: '+919999999999',
      storeAddress: '',
      repairNote: '',
    );

/// place_order, line for line: fee = 0 when subtotal >= free_delivery_min, COD refused when
/// not cod_enabled or subtotal + fee > cod_max.
({int fee, int total, bool cod}) _server(StoreSettings s, int subtotal) {
  final fee = subtotal >= s.freeDeliveryMinPaise ? 0 : s.deliveryFeePaise;
  return (fee: fee, total: subtotal + fee, cod: s.codEnabled && !(subtotal + fee > s.codMaxPaise));
}

CartLine _line(String id, int price, int qty, {int stock = 5}) => CartLine(
      variant: Variant(id: id, productId: 'p', sku: id, name: '', pricePaise: price, mrpPaise: price, stock: stock),
      qty: qty,
      productId: 'p',
      productSlug: 'p',
      productName: 'P',
    );

void main() {
  test('formatInr: Indian grouping, paise only when present, negatives, int4 max and beyond', () {
    const cases = {
      0: '₹0',
      1: '₹0.01',
      9: '₹0.09',
      99: '₹0.99',
      100: '₹1',
      4950: '₹49.50',
      4905: '₹49.05',
      99900: '₹999',
      109900: '₹1,099',
      9999999: '₹99,999.99',
      10000000: '₹1,00,000',
      12999900: '₹1,29,999',
      1000000000: '₹1,00,00,000',
      2147483647: '₹2,14,74,836.47', // int4 max: the largest price_paise the DB can hold
      123456789012345601: '₹1,23,45,67,89,01,23,456.01', // a double would lose these paise
      -50: '-₹0.50',
      -100: '-₹1',
      -4950: '-₹49.50',
      -12999900: '-₹1,29,999',
    };
    cases.forEach((paise, text) => expect(formatInr(paise), text, reason: '$paise'));
  });

  test('discountPercent: whole percent, rounded down, never negative', () {
    const cases = [
      // (price, mrp, %)
      (7499900, 8099900, 7), // 7.4 → 7
      (100, 200, 50),
      (199, 200, 0), // 0.5 → 0: never overstate
      (1, 100, 99),
      (100, 100, 0),
      (200, 100, 0), // MRP below price (bad data): no discount
      (0, 0, 0),
      (2147483647 - 1, 2147483647, 0),
      (1, 2147483647, 99),
    ];
    for (final (price, mrp, off) in cases) {
      expect(discountPercent(price, mrp), off, reason: '$price/$mrp');
    }
  });

  testWidgets('PriceTag hides MRP and "% off" when there is no discount', (tester) async {
    Future<void> pump(int price, int? mrp) => tester.pumpWidget(MaterialApp(
          theme: lightTheme,
          home: Scaffold(body: PriceTag(pricePaise: price, mrpPaise: mrp)),
        ));
    await pump(7499900, 8099900);
    expect(find.text('₹74,999'), findsOneWidget);
    expect(find.text('₹80,999'), findsOneWidget);
    expect(find.text('7% off'), findsOneWidget);
    for (final (price, mrp) in [(7499900, 7499900), (7499900, 7000000), (19900, 20000), (19900, null)]) {
      await pump(price, mrp);
      expect(find.textContaining('off'), findsNothing, reason: '$price/$mrp');
      expect(find.byType(Text), findsOneWidget, reason: 'only the price: $price/$mrp');
    }
  });

  test('cart subtotal is Σ price × qty', () {
    expect(cartSubtotalPaise(const []), 0);
    expect(cartSubtotalPaise([_line('a', 12999900, 1)]), 12999900);
    expect(cartSubtotalPaise([_line('a', 12999900, 2), _line('b', 49950, 5)]), 12999900 * 2 + 49950 * 5);
    expect(cartSubtotalPaise([_line('a', 2147483647, 5)]), 2147483647 * 5); // Dart int is 64-bit
  });

  group('delivery fee, COD and the free-delivery nudge match place_order', () {
    final settings = [
      _settings(),
      _settings(fee: 0),
      _settings(freeMin: 0),
      _settings(cod: false),
      _settings(codMax: 0),
      _settings(fee: 4900, freeMin: 2500000, codMax: 2500000), // fee pushes the total over the COD limit
      _settings(fee: 9999, freeMin: 100, codMax: 5000),
    ];
    // Around every threshold, where off-by-one bugs live.
    Set<int> subtotals(StoreSettings s) => {
          for (final base in [1, s.freeDeliveryMinPaise, s.codMaxPaise, s.codMaxPaise - s.deliveryFeePaise])
            for (final d in [-2, -1, 0, 1, 2])
              if (base + d > 0) base + d,
          12999900,
        };

    for (final (i, s) in settings.indexed) {
      test('settings #$i', () {
        for (final sub in subtotals(s)) {
          final server = _server(s, sub);
          final fee = s.deliveryFeeFor(sub);
          expect(fee, server.fee, reason: 'fee at $sub');
          expect(s.codAllowedFor(sub + fee), server.cod, reason: 'COD at $sub');
          expect(codUnavailableReason(s, sub + fee) == null, server.cod, reason: 'COD reason at $sub');
          final gap = s.freeDeliveryGapFor(sub);
          if (server.fee == 0) {
            expect(gap, 0, reason: 'no nudge when delivery is free at $sub');
          } else {
            expect(gap, greaterThan(0));
            // Adding exactly the nudged amount makes delivery free; a paisa less doesn't.
            expect(_server(s, sub + gap).fee, 0, reason: 'nudge at $sub');
            expect(_server(s, sub + gap - 1).fee, s.deliveryFeePaise, reason: 'nudge at $sub is the minimum');
          }
          final button = checkoutButton(method: PaymentMethod.razorpay, totalPaise: server.total, hasAddress: true, cartOk: true);
          expect(button.label, 'Pay ${formatInr(sub + fee)}');
        }
      });
    }

    test('COD is on the total including delivery, limit inclusive', () {
      final s = _settings(fee: 4900, freeMin: 9999900, codMax: 2500000);
      expect(codUnavailableReason(s, 2500000 - 4900 + s.deliveryFeeFor(2500000 - 4900)), isNull); // total = limit
      expect(codUnavailableReason(s, 2500000 - 4899 + s.deliveryFeeFor(2500000 - 4899)),
          'Not available for orders above ₹25,000'); // subtotal under the limit, total ₹0.01 over
    });
  });

  test('delivery terms on the product page say the threshold is inclusive', () {
    expect(deliveryTerms(_settings()), ' on orders of ₹999 or more · Cash on delivery up to ₹25,000');
    expect(deliveryTerms(_settings(fee: 0, cod: false)), ' on every order');
    expect(deliveryTerms(_settings(freeMin: 0)), ' on every order · Cash on delivery up to ₹25,000');
    expect(deliveryTerms(_settings(freeMin: 99950)), ' on orders of ₹999.50 or more · Cash on delivery up to ₹25,000');
  });

  test('order totals: Σ items is the subtotal, + delivery is the total', () {
    final o = Order.fromJson({
      'id': 'o1', 'number': 'SM100001', 'status': 'confirmed', 'payment_method': 'cod', 'payment_status': 'pending',
      'subtotal_paise': 2 * 12999900 + 49950, 'delivery_fee_paise': 0, 'total_paise': 2 * 12999900 + 49950,
      'address': {'name': 'A', 'phone': '+919876543210', 'line1': 'x', 'city': 'Gaya', 'state': 'Bihar', 'pincode': '823001'},
      'created_at': '2026-10-29T10:00:00Z',
      'items': [
        {'id': 'i1', 'product_name': 'Phone', 'variant_name': '', 'unit_price_paise': 12999900, 'qty': 2},
        {'id': 'i2', 'product_name': 'Case', 'variant_name': '', 'unit_price_paise': 49950, 'qty': 1},
      ],
    });
    expect(o.items.fold<int>(0, (s, i) => s + i.lineTotalPaise), o.subtotalPaise);
    expect(o.subtotalPaise + o.deliveryFeePaise, o.totalPaise);
    expect(formatInr(o.items.first.lineTotalPaise), '₹2,59,998');
  });

  test('admin shortInr: rounded down at each unit boundary', () {
    const cases = {
      9999999: '₹99,999', // paise dropped below a lakh
      10000000: '₹1L',
      10500000: '₹1.05L',
      48299999: '₹4.82L',
      999999999: '₹99.99L',
      1000000000: '₹1Cr',
      1200000000: '₹1.2Cr',
      1999999999: '₹1.99Cr',
      100000000000: '₹100Cr',
    };
    cases.forEach((paise, text) => expect(shortInr(paise), text, reason: '$paise'));
  });

  test('admin rupee fields: parse what staff type, refuse what the DB would', () {
    const ok = {'49': 4900, '49.5': 4950, '49.05': 4905, '1,00,000': 10000000, '₹ 999': 99900, '0': 0};
    ok.forEach((text, paise) => expect(parseRupees(text), paise, reason: text));
    for (final bad in ['', ' ', '-1', '1e3', '12.345', '.5', '4 9.9.9', '२५', '21474836.48', '999999999']) {
      expect(parseRupees(bad), isNull, reason: bad);
    }
  });
}
