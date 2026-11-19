// Checkout edits the cart in place: qty re-quotes, Remove has Undo, an emptied cart goes back to the cart, COD
// shows why it is off, the sticky bar carries the server total. 360 dp at 1.4x text (see pumpScreen): no overflow.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/account/data/addresses.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/checkout/screens/checkout_screen.dart';
import 'package:shyam_mobiles/features/offers/data/offers.dart';

import '../offers/fakes.dart';
import '../repairs/layout_harness.dart';

CartLine _line(String id, int qty, {int price = 1299900}) => CartLine(
      variant: Variant(id: id, productId: 'p$id', sku: id, name: '8 GB · 128 GB', pricePaise: price, mrpPaise: price + 100000, stock: 5),
      qty: qty,
      productId: 'p$id',
      productSlug: 's$id',
      productName: 'Phone $id with a rather long marketing name',
    );

class _Cart extends CartNotifier {
  _Cart(this.start);

  final List<CartLine> start;
  final calls = <String>[];

  @override
  Future<List<CartLine>> build() async => start;

  @override
  Future<void> setQty(String variantId, int qty) async {
    calls.add('qty $variantId $qty');
    state = AsyncData([for (final l in state.value!) l.variant.id == variantId ? l.copyWith(qty: qty) : l]);
  }

  @override
  Future<void> remove(String variantId) async {
    calls.add('remove $variantId');
    state = AsyncData([...state.value!.where((l) => l.variant.id != variantId)]);
  }

  @override
  Future<void> add(Variant variant, {int qty = 1, String? forModel}) async {
    calls.add('add ${variant.id} $qty');
    state = AsyncData([...state.value!, _line(variant.id, qty)]);
  }
}

class _Addresses extends AddressesNotifier {
  @override
  Future<List<Address>> build() async => const [
        Address(id: 'a1', name: 'Asha Verma', phone: '+919876543210', line1: 'Ward 4', city: 'Waidhan', state: 'Madhya Pradesh', pincode: '486886', isDefault: true),
      ];
}

Quote _quote(String? code, PaymentMethod? m, {int total = 1299900}) =>
    Quote(subtotalPaise: total, deliveryFeePaise: 0, discountPaise: 0, totalPaise: total);

Future<(_Cart, FakeOffersApi)> _open(WidgetTester tester, List<CartLine> lines, {int total = 1299900}) async {
  final cart = _Cart(lines);
  final api = FakeOffersApi(quote: (c, m) => _quote(c, m, total: total));
  await pumpScreen(tester, const CheckoutScreen(), routes: ['/cart'], overrides: [
    cartProvider.overrideWith(() => cart),
    addressesProvider.overrideWith(_Addresses.new),
    offersApiProvider.overrideWithValue(api),
  ]);
  await tester.pumpAndSettle();
  return (cart, api);
}

void main() {
  testWidgets('every line is visible and the sticky bar shows the server total', (tester) async {
    await _open(tester, [_line('1', 2), _line('2', 1)]);
    expect(find.text('Items (3)'), findsOneWidget);
    expect(find.textContaining('Phone 1'), findsOneWidget);
    expect(find.textContaining('Phone 2'), findsOneWidget);
    expect(find.text('Total ₹12,999'), findsOneWidget);
    expect(find.text('Pay ₹12,999'), findsOneWidget);
    expect(find.text('View details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('qty change writes the cart and asks the server for a new quote', (tester) async {
    final (cart, api) = await _open(tester, [_line('1', 1)]);
    final before = api.calls.length;
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();
    expect(cart.calls, ['qty 1 2']);
    expect(api.calls.length, greaterThan(before));
  });

  testWidgets('remove shows Undo, and Undo puts the line back', (tester) async {
    final (cart, _) = await _open(tester, [_line('1', 1), _line('2', 1)]);
    await tester.tap(find.byTooltip('Remove Phone 1 with a rather long marketing name'));
    await tester.pumpAndSettle();
    expect(cart.calls, ['remove 1']);
    expect(find.textContaining('Phone 1'), findsOneWidget, reason: 'only the snackbar names it now');
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(cart.calls, ['remove 1', 'add 1 1']);
    expect(find.text('Items (2)'), findsOneWidget);
  });

  testWidgets('removing the last line goes back to the cart', (tester) async {
    await _open(tester, [_line('1', 1)]);
    await tester.tap(find.byTooltip('Remove Phone 1 with a rather long marketing name'));
    await tester.pumpAndSettle();
    expect(find.text('Page /cart'), findsOneWidget);
  });

  testWidgets('COD off over the limit: the reason shows and the row cannot be picked', (tester) async {
    await _open(tester, [_line('1', 1, price: 3000000)], total: 3000000);
    await scrollTo(tester, find.text('Not available for orders above ₹25,000'));
    await tester.tap(find.text('Cash on delivery'));
    await tester.pumpAndSettle();
    expect(find.text('Pay ₹30,000'), findsOneWidget, reason: 'still paying online');
  });

  testWidgets('COD picked: the button says Place order', (tester) async {
    await _open(tester, [_line('1', 1)]);
    await scrollTo(tester, find.text('Cash on delivery'));
    await tester.tap(find.text('Cash on delivery'));
    await tester.pumpAndSettle();
    expect(find.text('Place order'), findsOneWidget);
  });

  testWidgets('View details scrolls to the bill', (tester) async {
    await _open(tester, [_line('1', 1), _line('2', 1), _line('3', 1)]);
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(find.text('Discount on MRP').hitTestable(), findsOneWidget);
    expect(find.text('You save ₹3,000 on this order'), findsOneWidget);
  });
}
