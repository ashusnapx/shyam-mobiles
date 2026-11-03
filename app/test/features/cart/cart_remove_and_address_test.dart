// The cart at 360x800 dp with 1.4x text: every line has one visible Remove (the minus stops at qty 1), with Undo; and "Deliver to" picks the address checkout then uses. No network: fakes for cart, addresses, quote.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/account/data/addresses.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/data/rails.dart';
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

/// The cart's rails read the catalogue: empty here, so only the cart itself shows.
final _noRails = [
  fitsProvider.overrideWith((ref, slug) => const <ProductCard>[]),
  recentCardsProvider.overrideWith((ref) => const <ProductCard>[]),
  homeProvider.overrideWithValue(const AsyncData((categories: <Category>[], featured: <ProductCard>[], accessories: <ProductCard>[]))),
];

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

void main() {
  testWidgets('remove: one visible button on every line, with Undo at the old qty; the minus stops at 1', (tester) async {
    final cart = _Cart();
    await pumpScreen(tester, const CartScreen(), overrides: [
      cartProvider.overrideWith(() => cart),
      addressesProvider.overrideWith(() => _Addresses(const [_home])),
      offersApiProvider.overrideWithValue(FakeOffersApi()),
      ..._noRails,
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsNWidgets(2), reason: 'one per line, always on screen');
    expect(find.byTooltip('Remove'), findsNothing, reason: 'one way to remove: no second bin in the stepper');
    final minus = find.byTooltip('Decrease quantity');
    expect(minus, findsNWidgets(2));
    expect(tester.widget<IconButton>(find.ancestor(of: find.byIcon(PhosphorIconsRegular.minus).first, matching: find.byType(IconButton))).onPressed,
        isNull, reason: 'qty 1: the minus is disabled');

    await tester.tap(find.text('Remove').first);
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
    expect(find.text('Your cart is empty'), findsOneWidget);
    expect(find.text('Shop phones'), findsOneWidget);
    expect(find.text('See offers'), findsOneWidget);
  });

  testWidgets('deliver to: the default first, Change picks another, and checkout starts with that one', (tester) async {
    await pumpScreen(tester, const CartScreen(), overrides: [
      cartProvider.overrideWith(_Cart.new),
      addressesProvider.overrideWith(() => _Addresses(const [_home, _shop])),
      offersApiProvider.overrideWithValue(FakeOffersApi()),
      ..._noRails,
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
      ..._noRails,
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Galaxy M35 is no longer available and was removed from your cart.'), findsOneWidget);
  });

  testWidgets('no saved address: the cart asks for one', (tester) async {
    await pumpScreen(tester, const CartScreen(), routes: ['/account/addresses/new'], overrides: [
      cartProvider.overrideWith(_Cart.new),
      addressesProvider.overrideWith(() => _Addresses(const [])),
      offersApiProvider.overrideWithValue(FakeOffersApi()),
      ..._noRails,
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

  testWidgets('saving, free-delivery progress and the WhatsApp row come from the lines and the server quote', (tester) async {
    await pumpScreen(tester, const CartScreen(), overrides: [
      cartProvider.overrideWith(_Cart.new),
      addressesProvider.overrideWith(() => _Addresses(const [_home])),
      offersApiProvider.overrideWithValue(FakeOffersApi()),
      ..._noRails,
    ]);
    await tester.pumpAndSettle();
    expect(find.text('You get free delivery'), findsOneWidget, reason: '₹51,996 is over the ₹999 free-delivery line');
    await scrollTo(tester, find.text('Need help? Send this cart on WhatsApp'));
    expect(find.text('Cash on delivery available'), findsNothing, reason: 'over the ₹25,000 COD limit');
    expect(find.textContaining('final amount is confirmed'), findsNothing);
  });

  test('cart saving: MRP minus price on each line times qty, plus the discount', () {
    final l = CartLine(
      variant: const Variant(id: 'v', productId: 'p', sku: 's', name: '', pricePaise: 6999900, mrpPaise: 7299900, stock: 5),
      qty: 2,
      productId: 'p',
      productSlug: 'p',
      productName: 'OnePlus 13',
    );
    expect(cartSavingPaise([l], 50000), 2 * 300000 + 50000);
    expect(cartSavingPaise([_line('v1', 'A15', 1)], 0), 0, reason: 'no MRP gap, no discount');
  });

  test('the cart as a WhatsApp message starts with the first name and ends with the total', () {
    final lines = [_line('v1', 'Samsung Galaxy A15', 1), _line('v2', 'Redmi Note 14', 2)];
    expect(
      cartWhatsAppText(lines, 3899700, name: 'Ravi'),
      'Hi, I’m Ravi. I want to order:\n'
      '1 × Samsung Galaxy A15 (8 GB · 128 GB) ₹12,999\n'
      '2 × Redmi Note 14 (8 GB · 128 GB) ₹25,998\n'
      'Total ₹38,997',
    );
    expect(cartWhatsAppText(lines, 3899700).split('\n').first, 'Hi, I want to order:');
  });
}
