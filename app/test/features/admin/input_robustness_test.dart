import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/admin.dart';
import 'package:shyam_mobiles/features/admin/data/rules.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_order_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_product_edit_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_settings_screen.dart';

import '../repairs/layout_harness.dart';

Finder _field(String label) => find.widgetWithText(TextFormField, label);

String _text(WidgetTester tester, String label) => tester.widget<TextFormField>(_field(label).first).controller!.text;

Future<void> _type(WidgetTester tester, String label, String text) async {
  await scrollTo(tester, _field(label).first);
  await tester.enterText(_field(label).first, text);
  await tester.pump();
}

const _brand = Brand(id: 'br1', slug: 'samsung', name: 'Samsung');
const _category = Category(id: 'c1', slug: 'phones', name: 'Phones', kind: CategoryKind.phone);

Variant _variant(int i, {int stock = 5}) => Variant(
      id: 'v$i',
      productId: 'p1',
      sku: 'SAM-S25U-$i',
      name: '12 GB · ${128 * (i % 4 + 1)} GB · Colour number $i with a long marketing name',
      pricePaise: 12999900 + i * 100000,
      mrpPaise: 13499900 + i * 100000,
      stock: stock,
      attributes: {'ram': '12 GB', 'storage': '${128 * (i % 4 + 1)} GB', 'color': 'Colour $i', 'color_hex': '#9FB4C7'},
    );

final _product = Product(
  id: 'p1',
  slug: 'samsung-galaxy-s25',
  name: 'Samsung Galaxy S25 Ultra 5G ' * 7, // ~200 characters of legacy data
  brand: _brand,
  category: _category,
  description: 'Flagship.',
  variants: [for (var i = 0; i < 40; i++) _variant(i, stock: i == 0 ? 0 : 5)],
);

Order _order(OrderStatus status) => Order(
      id: 'o1',
      number: 'SM100031',
      status: status,
      paymentMethod: PaymentMethod.cod,
      paymentStatus: PaymentStatus.pending,
      subtotalPaise: 7499900,
      deliveryFeePaise: 0,
      totalPaise: 7499900,
      address: const Address(
        name: 'Asha Verma',
        phone: '+919876543210',
        line1: 'Flat 12B',
        city: 'Gurugram',
        state: 'Haryana',
        pincode: '122016',
      ),
      createdAt: DateTime(2026, 10, 29, 18, 42),
      items: const [
        OrderItem(id: 'i1', productName: 'Samsung Galaxy S25', variantName: '12 GB · 256 GB', unitPricePaise: 7499900, qty: 1),
      ],
      events: [OrderEvent(status: status, createdAt: DateTime(2026, 10, 29, 18, 42))],
    );

void main() {
  testWidgets('product editor: 200-character name and 40 variants lay out; slug and name obey the DB', (tester) async {
    await pumpScreen(tester, const AdminProductEditScreen(productId: 'p1'), overrides: [
      adminBrandsProvider.overrideWithValue(const AsyncData([_brand])),
      adminCategoriesProvider.overrideWithValue(const AsyncData([_category])),
      adminProductProvider.overrideWith((ref, id) => _product),
    ]);
    await _type(tester, 'Slug (web address)', 'Galaxy S25 Ultra ü');
    expect(_text(tester, 'Slug (web address)'), 'galaxy-s25-ultra-', reason: 'lowercased, spaces to dashes, ü dropped');
    await _type(tester, 'Name', '📱📱');
    await tester.tap(find.text('Save details'));
    await tester.pump();
    expect(find.text('Use letters, not only symbols or emoji.'), findsOneWidget);
    await scrollTo(tester, find.text('SAM-S25U-39 · 5 in stock'));
    expect(find.text('SAM-S25U-0 · out of stock'), findsOneWidget);
  });

  testWidgets('variant sheet: SKU ASCII only, money and stock bounded, colour code formatted', (tester) async {
    await pumpScreen(tester, const AdminProductEditScreen(productId: 'p1'), overrides: [
      adminBrandsProvider.overrideWithValue(const AsyncData([_brand])),
      adminCategoriesProvider.overrideWithValue(const AsyncData([_category])),
      adminProductProvider.overrideWith((ref, id) => _product),
    ]);
    await scrollTo(tester, find.widgetWithText(TextButton, 'Add variant'));
    await tester.tap(find.widgetWithText(TextButton, 'Add variant'));
    await tester.pumpAndSettle();

    await _type(tester, 'SKU', 'SAM S25 ／8 ü 256');
    expect(_text(tester, 'SKU'), 'SAM-S25-8--256', reason: 'spaces to dashes; full-width slash and ü dropped');
    await _type(tester, 'SKU', 'A' * 100);
    expect(_text(tester, 'SKU'), 'A' * 60);
    await _type(tester, 'Price', '₹1,29,999');
    expect(_text(tester, 'Price'), '129999');
    await _type(tester, 'MRP', '-5');
    expect(_text(tester, 'MRP'), '5');
    await _type(tester, 'Stock', '1234567');
    expect(_text(tester, 'Stock'), '12345');
    await _type(tester, 'Colour code', '1f2b4d');
    expect(_text(tester, 'Colour code'), '#1F2B4D');
    await _type(tester, 'RAM', '8' * 50);
    expect(_text(tester, 'RAM').length, 20, reason: 'so "RAM · storage · colour" fits the 80-character name');

    await _type(tester, 'Price', '1500000'); // ₹15,00,000: past the business cap
    await _type(tester, 'MRP', '1500000');
    await tester.tap(find.widgetWithText(FilledButton, 'Add variant'));
    await tester.pump();
    expect(find.text('Keep it at or under ₹10,00,000.'), findsNWidgets(2));
    await _type(tester, 'Price', '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Add variant'));
    await tester.pump();
    expect(find.text('Enter an amount above ₹0.'), findsOneWidget);
  });

  testWidgets('settings: fees and limits bounded, phone normalised, long texts capped', (tester) async {
    await pumpScreen(tester, const AdminSettingsScreen());
    await _type(tester, 'Delivery fee', '12345678'); // too many digits: the keystrokes are refused
    expect(_text(tester, 'Delivery fee'), '49');
    await _type(tester, 'Delivery fee', '10001');
    await _type(tester, 'Store phone (also WhatsApp)', '+91 79875-59272');
    expect(_text(tester, 'Store phone (also WhatsApp)'), '79875 59272');
    await _type(tester, 'Address', 'x' * 5000);
    expect(_text(tester, 'Address'), 'x' * 300);
    expect(find.text('300/300'), findsOneWidget);
    await _type(tester, 'Opening hours', 'h' * 500);
    expect(_text(tester, 'Opening hours').length, 60);
    await tester.tap(find.text('Save settings'));
    await tester.pump();
    expect(find.text('Keep it at or under ₹10,000.'), findsOneWidget);
  });

  testWidgets('order: a double tap opens one ship sheet; the courier needs a real name; IMEI paste', (tester) async {
    await pumpScreen(tester, const AdminOrderScreen(orderId: 'o1'), overrides: [
      adminOrderProvider.overrideWith((ref, id) => _order(OrderStatus.packed)),
    ]);
    await tester.tap(find.text('Ship'));
    await tester.tap(find.text('Ship'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Mark shipped'), findsOneWidget, reason: 'one sheet, not two stacked');
    await tester.enterText(_field('Courier'), '🚚');
    await tester.tap(find.text('Mark shipped'));
    await tester.pump();
    expect(find.text('Use letters, not only symbols or emoji.'), findsOneWidget);
    Navigator.of(tester.element(find.text('Mark shipped'))).pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add IMEI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add IMEI'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('IMEI'), 'IMEI1: 35-209900-176148-1 IMEI2: 35-209900-176149-9');
    await tester.pump();
    expect(_text(tester, 'IMEI'), '352099001761481');
    expect(find.text('15/15'), findsOneWidget);
  });

  test('rupee validator: business caps, inside int4 paise', () {
    expect(rupeesError('49', maxPaise: maxFeePaise), isNull);
    expect(rupeesError('10000', maxPaise: maxFeePaise), isNull);
    expect(rupeesError('10000.01', maxPaise: maxFeePaise), 'Keep it at or under ₹10,000.');
    expect(rupeesError('1000000', maxPaise: maxAmountPaise), isNull);
    expect(rupeesError('', maxPaise: maxAmountPaise), 'Enter an amount.');
    expect(rupeesError('', maxPaise: maxAmountPaise, optional: true), isNull);
    expect(rupeesError('0', minPaise: 1, maxPaise: maxAmountPaise), 'Enter an amount above ₹0.');
    expect(rupeesError('abc', maxPaise: maxAmountPaise), 'Enter an amount like 499 or 74999.50.');
    expect(skuPattern.hasMatch('SAM-S25/8.256_NVY'), isTrue);
    expect(skuPattern.hasMatch('-SAM'), isFalse);
    expect(skuPattern.hasMatch('SAM S25'), isFalse);
    expect(skuPattern.hasMatch('A' * 61), isFalse);
    expect(slugPattern.hasMatch('a' * 160), isTrue);
    expect(slugPattern.hasMatch('a' * 161), isFalse);
    expect(slugFor('Samsung Galaxy S25+ ${'x' * 300}').length, lessThanOrEqualTo(160));
  });
}
