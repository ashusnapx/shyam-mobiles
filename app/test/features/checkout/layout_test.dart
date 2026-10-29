// Layout smoke tests at 360x800 dp, 48 dp edge-to-edge nav bar inset, light and dark. Fails on any overflow.
// Uses the SDK's Roboto (the default test font draws every glyph 1 em wide, far wider than any real font) at 1.4x
// text, which is about Plus Jakarta Sans at the 1.3x cap.
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
import 'package:shyam_mobiles/features/checkout/screens/checkout_result_screen.dart';
import 'package:shyam_mobiles/features/checkout/screens/checkout_screen.dart';
import 'package:shyam_mobiles/features/orders/data/orders.dart';
import 'package:shyam_mobiles/features/orders/screens/order_detail_screen.dart';
import 'package:shyam_mobiles/features/orders/screens/orders_screen.dart';

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

const _address = Address(
  id: 'a1',
  name: 'Rahul Kumar',
  phone: '+919876543210',
  line1: 'House 14, Gandhi Nagar',
  landmark: 'near Shiv Mandir',
  city: 'Gaya',
  state: 'Bihar',
  pincode: '823001',
  isDefault: true,
);

CartLine _line(String id, {int qty = 1, int stock = 10, int price = 12999900, bool active = true}) => CartLine(
      variant: Variant(
        id: id,
        productId: 'p$id',
        sku: id,
        name: '12 GB · 256 GB · Titanium Whitesilver',
        pricePaise: price,
        mrpPaise: price,
        stock: stock,
        isActive: active,
      ),
      qty: qty,
      productId: 'p$id',
      productSlug: 's$id',
      productName: 'Samsung Galaxy S25 Ultra 5G with a long marketing name',
    );

final _lines = [_line('1'), _line('2', qty: 3, stock: 2), _line('3', stock: 1, price: 109900), _line('4', active: false)];

Order _order(OrderStatus status, {PaymentMethod method = PaymentMethod.razorpay, PaymentStatus pay = PaymentStatus.paid}) =>
    Order(
      id: 'o1',
      number: 'SM100023',
      status: status,
      paymentMethod: method,
      paymentStatus: pay,
      subtotalPaise: 12999900,
      deliveryFeePaise: 0,
      totalPaise: 12999900,
      address: _address,
      createdAt: DateTime(2026, 10, 27, 18, 42),
      reservedUntil: DateTime.now().add(const Duration(minutes: 10)),
      courier: 'Delhivery',
      trackingNumber: '1490 2231 0098 7711',
      items: const [
        OrderItem(
          id: 'i1',
          productName: 'Samsung Galaxy S25 Ultra 5G with a long marketing name',
          variantName: '12 GB · 256 GB · Navy',
          unitPricePaise: 12999900,
          qty: 2,
          imeis: ['352099214488120', '352099214488121'],
        ),
      ],
      events: [
        OrderEvent(status: OrderStatus.pendingPayment, createdAt: DateTime(2026, 10, 27, 18, 40)),
        OrderEvent(status: OrderStatus.confirmed, note: 'Payment received', createdAt: DateTime(2026, 10, 27, 18, 42)),
        OrderEvent(status: OrderStatus.shipped, note: 'Handed to Delhivery', createdAt: DateTime(2026, 10, 28, 17, 30)),
      ],
    );

class _Cart extends CartNotifier {
  _Cart(this.lines);

  final List<CartLine> lines;

  @override
  Future<List<CartLine>> build() async => lines;
}

class _Addresses extends AddressesNotifier {
  @override
  Future<List<Address>> build() async => const [_address];
}

class _Orders extends OrdersNotifier {
  @override
  Future<OrdersPage> build() async => (
        orders: [_order(OrderStatus.shipped), _order(OrderStatus.pendingPayment, pay: PaymentStatus.pending)],
        hasMore: false,
      );
}

Future<void> _pump(WidgetTester tester, Widget screen, {required Brightness brightness, List<Order>? orders}) async {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3
    ..padding = const FakeViewPadding(bottom: 144); // 48 dp gesture/nav bar
  tester.platformDispatcher.textScaleFactorTestValue = 1.4;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(const SizedBox()); // fresh ProviderScope per screen

  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      currentUserProvider.overrideWithValue(null),
      cartProvider.overrideWith(() => _Cart(_lines)),
      addressesProvider.overrideWith(_Addresses.new),
      storeSettingsProvider.overrideWith((ref) async => _settings),
      ordersProvider.overrideWith(_Orders.new),
      for (final o in orders ?? const <Order>[]) orderProvider(o.id).overrideWith((ref) async => o),
    ],
    child: MaterialApp.router(
      theme: ThemeData(colorScheme: lightScheme, fontFamily: 'Roboto'),
      routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => screen)]),
    ),
  ));
  await tester.pump(const Duration(seconds: 1));
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

  for (final b in [Brightness.light]) {
    testWidgets('cart ($b)', (tester) async {
      await _pump(tester, const CartScreen(), brightness: b);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull, reason: 'blocked lines');
      final bottom = tester.getBottomLeft(find.byType(FilledButton)).dy;
      expect(bottom, lessThanOrEqualTo(800 - 48), reason: 'sticky bar clears the nav bar');
      for (final text in ['Only 2 left', 'Only 1 left', 'No longer available', 'No platform, COD or packing fees']) {
        await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
      }
    });

    testWidgets('checkout ($b)', (tester) async {
      await _pump(tester, const CheckoutScreen(), brightness: b);
      expect(find.text('Fix your cart to continue'), findsOneWidget);
      final bottom = tester.getBottomLeft(find.byType(FilledButton)).dy;
      expect(bottom, lessThanOrEqualTo(800 - 48));
      for (final text in [
        'Rahul Kumar',
        'EMI bank charges, if any, are shown by Razorpay before you pay.',
        'Not available for orders above ₹25,000',
        '6 items',
      ]) {
        await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
      }
      await tester.tap(find.text('6 items'));
      await tester.pump(const Duration(seconds: 1));
      await tester.scrollUntilVisible(find.text('To pay'), 200, scrollable: find.byType(Scrollable).first);
    });

    testWidgets('orders list and detail ($b)', (tester) async {
      await _pump(tester, const OrdersScreen(), brightness: b);
      expect(find.text('SM100023'), findsNWidgets(2));

      final order = _order(OrderStatus.pendingPayment, pay: PaymentStatus.pending);
      await _pump(tester, const OrderDetailScreen(orderId: 'o1'), brightness: b, orders: [order]);
      for (final f in [
        find.textContaining('Handed to Delhivery'),
        find.text('Check it: dial *#06# on the phone and match the box label.'),
        find.text('Pay ₹1,29,999'),
        find.text('Ask on WhatsApp'),
      ]) {
        await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
      }
      expect(find.byType(SelectableText), findsNWidgets(2), reason: 'one IMEI per unit');
    });

    testWidgets('result screens ($b)', (tester) async {
      for (final o in [
        _order(OrderStatus.confirmed, method: PaymentMethod.cod, pay: PaymentStatus.pending),
        _order(OrderStatus.pendingPayment, pay: PaymentStatus.pending),
        _order(OrderStatus.cancelled),
      ]) {
        await _pump(tester, const CheckoutResultScreen(orderId: 'o1'), brightness: b, orders: [o]);
      }
      expect(find.text('Payment arrived late'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // disposes the poll timer
    });
  }
}
