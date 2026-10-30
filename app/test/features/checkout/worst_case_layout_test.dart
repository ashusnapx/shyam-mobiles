// An address with every field at its DB maximum, in mixed scripts, and 200-character product names through cart,
// checkout and order detail at 360x800 dp with 1.4x text. Fails on any overflow.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/features/account/data/addresses.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/cart/screens/cart_screen.dart';
import 'package:shyam_mobiles/features/checkout/screens/checkout_screen.dart';
import 'package:shyam_mobiles/features/offers/data/offers.dart';
import 'package:shyam_mobiles/features/orders/data/orders.dart';
import 'package:shyam_mobiles/features/orders/screens/order_detail_screen.dart';

import '../offers/fakes.dart';

/// [unit] repeated and cut to exactly [n] code points, the way Postgres counts.
String _fill(String unit, int n) => String.fromCharCodes((unit * n).runes.take(n));

final _address = Address(
  id: 'a1',
  name: _fill('राम कुमार Verma ', 80),
  phone: '+919876543210',
  line1: _fill('Flat 1204, Tower B, श्री साई अपार्टमेंट्स, ', 120),
  line2: _fill('Sector 21, Near the old water tank, ', 120),
  landmark: _fill('Behind Shiv Mandir, opposite SBI ATM ', 80),
  city: _fill('Bodh Gaya Nagar Panchayat ', 60),
  district: _fill('Gaya District Rural ', 60),
  state: 'Dadra and Nagar Haveli and Daman and Diu',
  pincode: '823001',
  isDefault: true,
);

const _name = 'Samsung Galaxy S25 Ultra 5G AI Smartphone (Titanium Silverblue, 12GB RAM, 256GB Storage) '
    'with No Cost EMI and Additional Exchange Offers, Snapdragon 8 Elite, 200 MP Camera, S Pen included in the box!!';

const _settings = StoreSettings(
  deliveryFeePaise: 4900,
  freeDeliveryMinPaise: 99900,
  codEnabled: true,
  codMaxPaise: 2500000,
  storePhone: '+919999999999',
  storeAddress: '',
  storeHours: '',
  repairNote: '',
);

CartLine _line(String id, {int qty = 5}) => CartLine(
      variant: Variant(
        id: id,
        productId: 'p$id',
        sku: id,
        name: _fill('12 GB · 256 GB · Titanium Silverblue ', 80),
        pricePaise: 99999900,
        mrpPaise: 99999900,
        stock: 9,
      ),
      qty: qty,
      productId: 'p$id',
      productSlug: 's$id',
      productName: _name,
    );

final _order = Order(
  id: 'o1',
  number: 'SM100023',
  status: OrderStatus.shipped,
  paymentMethod: PaymentMethod.cod,
  paymentStatus: PaymentStatus.pending,
  subtotalPaise: 999999500,
  deliveryFeePaise: 0,
  discountPaise: 100000000,
  couponCode: 'ABCDEFGHIJKLMNOPQRST', // the longest code
  totalPaise: 899999500,
  address: _address,
  createdAt: DateTime(2026, 10, 27, 18, 42),
  courier: _fill('Delhivery Express Surface ', 60),
  trackingNumber: _fill('1490 2231 0098 7711 ', 60),
  items: [
    OrderItem(
      id: 'i1',
      productName: _name,
      variantName: _fill('12 GB · 256 GB · Titanium Silverblue ', 80),
      unitPricePaise: 199999900,
      qty: 5,
      imeis: [for (var i = 0; i < 5; i++) '35209921448812$i'],
    ),
  ],
  events: [
    OrderEvent(status: OrderStatus.confirmed, createdAt: DateTime(2026, 10, 27, 18, 42)),
    OrderEvent(status: OrderStatus.shipped, note: _fill('Handed to the courier with a note at the limit. ', 500), createdAt: DateTime(2026, 10, 28)),
  ],
);

class _Cart extends CartNotifier {
  @override
  Future<List<CartLine>> build() async => [for (var i = 0; i < 10; i++) _line('$i')];
}

class _Addresses extends AddressesNotifier {
  @override
  Future<List<Address>> build() async => [_address];
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3
    ..padding = const FakeViewPadding(bottom: 144);
  tester.platformDispatcher.textScaleFactorTestValue = 1.4;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      currentUserProvider.overrideWithValue(null),
      cartProvider.overrideWith(_Cart.new),
      addressesProvider.overrideWith(_Addresses.new),
      storeSettingsProvider.overrideWith((ref) async => _settings),
      offersApiProvider.overrideWithValue(FakeOffersApi(offers: [diwali, festiveSale])),
      orderProvider('o1').overrideWith((ref) async => _order),
    ],
    child: MaterialApp.router(
      theme: ThemeData(colorScheme: lightScheme, fontFamily: 'Roboto'),
      routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => screen)]),
    ),
  ));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pump();
  }
}

void main() {
  setUpAll(() async {
    final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final w in ['Regular', 'Medium', 'Bold', 'Black']) {
      final f = File('$dir/Roboto-$w.ttf');
      if (f.existsSync()) roboto.addFont(f.readAsBytes().then(ByteData.sublistView));
    }
    await roboto.load();
  });

  test('fixtures sit exactly at the DB limits', () {
    expect(_address.name.runes.length, 80);
    expect(_address.line1.runes.length, 120);
    expect(_address.landmark!.runes.length, 80);
    expect(_address.city.runes.length, 60);
    expect(_name.length, 200);
  });

  testWidgets('cart: 10 lines of 200-character names at the qty cap', (tester) async {
    await _pump(tester, const CartScreen());
    await _scrollToEnd(tester);
  });

  testWidgets('checkout: the max-length address and a total near the int limit', (tester) async {
    await _pump(tester, const CheckoutScreen());
    await _scrollToEnd(tester);
  });

  testWidgets('order detail: max-length address, courier, note and 5 IMEIs', (tester) async {
    await _pump(tester, const OrderDetailScreen(orderId: 'o1'));
    await _scrollToEnd(tester);
  });
}
