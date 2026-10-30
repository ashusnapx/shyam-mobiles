// The cart at 360x800 dp with 1.4x text: every line has a visible Remove (and the minus turns into one at qty 1),
// each with Undo; and "Deliver to" picks the address checkout then uses. No network: fakes for cart, addresses, quote.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/account/data/addresses.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/cart/screens/cart_screen.dart';
import 'package:shyam_mobiles/features/checkout/screens/checkout_screen.dart';
import 'package:shyam_mobiles/features/offers/data/offers.dart';

import '../offers/fakes.dart';
import '../repairs/layout_harness.dart';

CartLine _line(String id, String name, int qty) => CartLine(
      variant: Variant(id: id, productId: 'p$id', sku: id, name: '8 GB · 128 GB', pricePaise: 1299900, mrpPaise: 1299900, stock: 5),
      qty: qty,
      productId: 'p$id',
      productSlug: 's$id',
      productName: name,
    );

class _Cart extends CartNotifier {
  final calls = <String>[];

  @override
  Future<List<CartLine>> build() async => [_line('v1', 'Samsung Galaxy A15', 1), _line('v2', 'Redmi Note 14', 3)];

  @override
  Future<void> remove(String variantId) async {
    calls.add('remove $variantId');
    state = AsyncData([...state.value!.where((l) => l.variant.id != variantId)]);
  }

  @override
  Future<void> add(Variant variant, {int qty = 1}) async => calls.add('add ${variant.id} $qty');
}

class _DroppedCart extends _Cart {
  var _said = false;

  @override
  List<String?> takeRemoved() {
    if (_said) return const [];
    _said = true;
    return const ['Galaxy M35'];
  }
}

const _home = Address(id: 'a1', name: 'Asha Verma', phone: '+919876543210', line1: 'Ward 4', city: 'Waidhan', state: 'Madhya Pradesh', pincode: '486886', isDefault: true);
const _shop = Address(id: 'a2', name: 'Ravi Gupta', phone: '+919812345678', line1: 'Main Road', city: 'Singrauli', state: 'Madhya Pradesh', pincode: '486889');

class _Addresses extends AddressesNotifier {
  _Addresses(this.list);

  final List<Address> list;

  @override
  Future<List<Address>> build() async => list;
}

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

void main() {
  testWidgets('remove: a visible button on every line and the bin at qty 1, both with Undo at the old qty', (tester) async {
    final cart = _Cart();
    await pumpScreen(tester, const CartScreen(), overrides: [
      cartProvider.overrideWith(() => cart),
      addressesProvider.overrideWith(() => _Addresses(const [_home])),
      offersApiProvider.overrideWithValue(FakeOffersApi()),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsNWidgets(2), reason: 'one per line, always on screen');
    expect(find.byTooltip('Remove'), findsOneWidget, reason: 'the qty-1 line’s minus is a bin');
    expect(find.byTooltip('Decrease quantity'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(cart.calls, ['remove v1']);
    expect(find.text('Removed Samsung Galaxy A15'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(cart.calls.last, 'add v1 1');

    await scrollTo(tester, find.text('Remove'));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(cart.calls, contains('remove v2'));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(cart.calls.last, 'add v2 3', reason: 'back at its old qty');
  });

  testWidgets('deliver to: the default first, Change picks another, and checkout starts with that one', (tester) async {
    await pumpScreen(tester, const CartScreen(), overrides: [
      cartProvider.overrideWith(_Cart.new),
      addressesProvider.overrideWith(() => _Addresses(const [_home, _shop])),
      offersApiProvider.overrideWithValue(FakeOffersApi()),
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Asha Verma', findRichText: true), findsOneWidget);
    expect(find.textContaining('Waidhan 486886', findRichText: true), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Change delivery address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ravi Gupta'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Singrauli 486889', findRichText: true), findsOneWidget);
    expect(_container(tester).read(selectedAddressProvider)?.id, 'a2');

    await pumpScreen(tester, const CheckoutScreen(), overrides: [
      cartProvider.overrideWith(_Cart.new),
      addressesProvider.overrideWith(() => _Addresses(const [_home, _shop])),
      offersApiProvider.overrideWithValue(FakeOffersApi()),
      selectedAddressProvider.overrideWithBuild((ref, _) => _shop),
      currentUserProvider.overrideWithValue(null),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Ravi Gupta'), findsOneWidget, reason: 'checkout delivers where the cart said');
    expect(find.text('Asha Verma'), findsNothing);
  });

  testWidgets('a line the shop hid and the cart dropped is named once', (tester) async {
    await pumpScreen(tester, const CartScreen(), overrides: [
      cartProvider.overrideWith(_DroppedCart.new),
      addressesProvider.overrideWith(() => _Addresses(const [_home])),
      offersApiProvider.overrideWithValue(FakeOffersApi()),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Galaxy M35 is no longer available and was removed from your cart.'), findsOneWidget);
  });

  testWidgets('no saved address: the cart asks for one', (tester) async {
    await pumpScreen(tester, const CartScreen(), routes: ['/account/addresses/new'], overrides: [
      cartProvider.overrideWith(_Cart.new),
      addressesProvider.overrideWith(() => _Addresses(const [])),
      offersApiProvider.overrideWithValue(FakeOffersApi()),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Add a delivery address'), findsOneWidget);
    await tester.tap(find.text('Add a delivery address'));
    await tester.pumpAndSettle();
    expect(find.text('Page /account/addresses/new'), findsOneWidget);
  });

  test('no pick: the default; a pick is kept, even one the list hasn’t reloaded with yet', () {
    expect(deliveryAddressFrom(const [_home, _shop], null)?.id, 'a1');
    expect(deliveryAddressFrom(const [_home, _shop], _shop)?.id, 'a2');
    expect(deliveryAddressFrom(const [], null), isNull);
    // just added: the form returns the row before the list reloads
    const fresh = Address(id: 'a3', name: 'New', phone: '+919999999999', line1: 'x', city: 'y', state: 'z', pincode: '486886');
    expect(deliveryAddressFrom(const [_home], fresh)?.id, 'a3');
  });
}
