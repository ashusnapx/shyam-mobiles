// Offers for customers at 360x800 dp with 1.4x text (layout_harness.dart): the coupon sheet, the cart's discount
// line, the home banners, Offers, the offer page, Refer & earn, product chips and the code reaching place_order.
// No network: the offer RPCs are FakeOffersApi. Any overflow fails the test.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/account/data/addresses.dart';
import 'package:shyam_mobiles/features/account/data/profile.dart';
import 'package:shyam_mobiles/features/account/screens/account_screen.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/cart/screens/cart_screen.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/screens/home_screen.dart';
import 'package:shyam_mobiles/features/catalog/screens/product_screen.dart';
import 'package:shyam_mobiles/features/checkout/data/payment.dart';
import 'package:shyam_mobiles/features/checkout/screens/checkout_screen.dart';
import 'package:shyam_mobiles/features/offers/data/offers.dart';
import 'package:shyam_mobiles/features/offers/screens/offers_screen.dart';
import 'package:shyam_mobiles/features/offers/screens/refer_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repairs/layout_harness.dart';
import 'fakes.dart';

const _line = CartLine(
  variant: Variant(id: 'v1', productId: 'p1', sku: 'S25', name: '12 GB · 256 GB · Navy', pricePaise: 1299900, mrpPaise: 1399900, stock: 5),
  qty: 1,
  productId: 'p1',
  productSlug: 'galaxy-s25',
  productName: 'Samsung Galaxy S25 5G',
);

class _Cart extends CartNotifier {
  @override
  Future<List<CartLine>> build() async => const [_line];
}

class _Addresses extends AddressesNotifier {
  @override
  Future<List<Address>> build() async => const [
        Address(id: 'a1', name: 'Asha Verma', phone: '+919876543210', line1: 'Ward 4, Main Road', city: 'Waidhan', state: 'Madhya Pradesh', pincode: '486886'),
      ];
}

/// The server's answers for a ₹12,999 cart: DIWALI500 takes ₹500 off, BIGSPEND needs ₹25,000, anything else is unknown.
Quote _quote(String? code, PaymentMethod? method) => switch (code) {
      null => const Quote(subtotalPaise: 1299900, deliveryFeePaise: 0, discountPaise: 0, totalPaise: 1299900),
      'DIWALI500' => const Quote(
          subtotalPaise: 1299900,
          deliveryFeePaise: 0,
          discountPaise: 50000,
          totalPaise: 1249900,
          promotion: (id: 'd1', title: 'Flat ₹500 off phones', code: 'DIWALI500', kind: OfferKind.flat),
        ),
      'BIGSPEND' => const Quote(
          subtotalPaise: 1299900,
          deliveryFeePaise: 0,
          discountPaise: 0,
          totalPaise: 1299900,
          couponError: 'COUPON_MIN_ORDER',
          couponErrorDetail: '2500000',
        ),
      _ => const Quote(subtotalPaise: 1299900, deliveryFeePaise: 0, discountPaise: 0, totalPaise: 1299900, couponError: 'COUPON_NOT_FOUND'),
    };

final _bigSpend = Offer(id: '33333333-3333-3333-3333-333333333333', title: 'Big spender', code: 'BIGSPEND', kind: OfferKind.flat, value: 100000, minSubtotalPaise: 2500000, startsAt: DateTime(2026));

Future<void> _scrollToEnd(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pump();
  }
}

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

void main() {
  testWidgets('coupon sheet: a refused code explains itself, a good one applies and the cart shows the saving', (tester) async {
    final api = FakeOffersApi(offers: [diwali, _bigSpend, festiveSale], quote: _quote);
    await pumpScreen(tester, const CartScreen(), overrides: [
      cartProvider.overrideWith(_Cart.new),
      offersApiProvider.overrideWithValue(api),
    ]);
    await tester.pump();
    expect(find.text('Apply a coupon'), findsOneWidget);
    expect(find.textContaining('Discount'), findsNothing);
    expect(find.text('Checkout · ₹12,999'), findsOneWidget, reason: 'the server total');

    await tester.tap(find.text('Apply a coupon'));
    await tester.pumpAndSettle();
    final apply = find.widgetWithText(FilledButton, 'Apply').first; // the field's; each listed code has its own
    await tester.enterText(find.widgetWithText(TextField, 'Coupon code'), 'no1');
    await tester.tap(apply);
    await tester.pump();
    expect(find.text('Codes are 4 to 20 letters and numbers.'), findsOneWidget, reason: 'checked before asking the server');
    expect(api.calls.where((c) => c.startsWith('quote NO1')), isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'Coupon code'), 'nope1');
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text('That code isn’t valid. Check the spelling and try again.'), findsOneWidget);

    Finder applyIn(String title) =>
        find.descendant(of: find.widgetWithText(Card, title), matching: find.widgetWithText(FilledButton, 'Apply'));
    await tester.ensureVisible(applyIn('Big spender'));
    await tester.pump();
    await tester.tap(applyIn('Big spender'));
    await tester.pumpAndSettle();
    expect(find.text('This code needs a cart of ₹25,000 or more. Add a little more to use it.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Coupon code'), 'diwali500');
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text('Apply coupon'), findsNothing, reason: 'the sheet closed');
    expect(find.text('DIWALI500 applied. You save ₹500.'), findsOneWidget);
    expect(find.text('DIWALI500 applied'), findsOneWidget);
    expect(find.text('Discount · DIWALI500'), findsOneWidget);
    expect(find.text('−₹500'), findsOneWidget);
    expect(find.text('Checkout · ₹12,499'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Remove code DIWALI500'));
    await tester.pumpAndSettle();
    expect(find.text('Discount · DIWALI500'), findsNothing);
    expect(find.text('Checkout · ₹12,999'), findsOneWidget);
  });

  testWidgets('cart: a code that stops working says why, and can be removed', (tester) async {
    await pumpScreen(tester, const CartScreen(), overrides: [
      cartProvider.overrideWith(_Cart.new),
      offersApiProvider.overrideWithValue(FakeOffersApi(quote: _quote)),
    ]);
    _container(tester).read(couponCodeProvider.notifier).set('BIGSPEND');
    await tester.pumpAndSettle();
    expect(find.text('BIGSPEND can’t be used'), findsOneWidget);
    expect(find.textContaining('₹25,000 or more'), findsOneWidget);
    await _scrollToEnd(tester);
  });

  testWidgets('checkout sends the applied code to place_order and clears it after', (tester) async {
    final pay = _PaymentApi();
    await pumpScreen(tester, const CheckoutScreen(), routes: ['/checkout/result/:id'], overrides: [
      cartProvider.overrideWith(_Cart.new),
      addressesProvider.overrideWith(_Addresses.new),
      offersApiProvider.overrideWithValue(FakeOffersApi(quote: _quote)),
      paymentApiProvider.overrideWithValue(pay),
      currentUserProvider.overrideWithValue(null),
    ]);
    _container(tester).read(couponCodeProvider.notifier).set('DIWALI500');
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Cash on delivery'));
    await tester.tap(find.text('Cash on delivery'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Discount · DIWALI500'));
    expect(find.text('−₹500'), findsOneWidget);
    await scrollTo(tester, find.text('DIWALI500 applied'));
    await tester.tap(find.text('Place order · ₹12,499'));
    await tester.pumpAndSettle();
    expect(pay.placed, ['a1 cod DIWALI500']);
    expect(find.text('Page /checkout/result/order-1'), findsOneWidget);
    expect(_container(tester).read(couponCodeProvider), isNull);
  });

  testWidgets('home: running banners under the hero open their app route; a bad link never shows', (tester) async {
    PromoBanner banner(String id, String title, String link, {int tone = 0}) =>
        PromoBanner(id: id, title: title, subtitle: 'Flat ₹500 off every smartphone till Sunday', ctaLabel: 'Use code DIWALI500', link: link, tone: tone, startsAt: DateTime(2026));
    await pumpScreen(tester, const HomeScreen(), routes: ['/offers'], overrides: [
      homeProvider.overrideWith((ref) async => (
            categories: const <Category>[],
            featured: const [ProductCard(id: 'p1', slug: 'galaxy-s25', name: 'Samsung Galaxy S25', brandName: 'Samsung', categorySlug: 'smartphones', minPricePaise: 7499900, mrpPaise: 7999900, inStock: true)],
            accessories: const <ProductCard>[],
          )),
      offersApiProvider.overrideWithValue(FakeOffersApi(bannerRows: [
        banner('b1', 'Diwali dhamaka on every phone in the shop', '/offers', tone: 1),
        banner('b2', 'Repairs in an hour', '/repairs', tone: 2),
        banner('b3', 'Bad link', 'https://example.com'),
        PromoBanner(id: 'b4', title: 'Paused', link: '/offers', startsAt: DateTime(2026), isActive: false),
      ])),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Diwali dhamaka on every phone in the shop'), findsOneWidget);
    expect(find.text('Repairs in an hour'), findsOneWidget);
    expect(find.text('Bad link'), findsNothing);
    expect(find.text('Paused'), findsNothing, reason: 'staff see every row; home shows running ones only');
    await tester.tap(find.text('Diwali dhamaka on every phone in the shop'));
    await tester.pumpAndSettle();
    expect(find.text('Page /offers'), findsOneWidget);
  });

  testWidgets('offers: cards with terms, Copy code, Apply takes the code to the cart', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpScreen(tester, const OffersScreen(), routes: ['/cart'], overrides: [
      offersApiProvider.overrideWithValue(FakeOffersApi(offers: [diwali, festiveSale])),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Flat ₹500 off phones'), findsOneWidget);
    expect(find.text('₹500 off'), findsOneWidget);
    expect(find.textContaining('Ends in 3 days'), findsOneWidget);
    expect(find.textContaining('Selected products only'), findsOneWidget);
    await scrollTo(tester, find.text('No code needed'));

    await tester.tap(find.bySemanticsLabel('Copy code DIWALI500'));
    await tester.pump();
    expect(copied, 'DIWALI500');
    expect(find.text('Code DIWALI500 copied'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Apply DIWALI500'));
    await tester.pumpAndSettle();
    expect(find.text('Page /cart'), findsOneWidget);
    expect(_container(tester).read(couponCodeProvider), 'DIWALI500');
  });

  testWidgets('offer page: terms, code and its products; an ended one says so', (tester) async {
    final api = FakeOffersApi(offers: [diwali], productRows: [
      for (var i = 0; i < 3; i++)
        ProductCard(id: 'p$i', slug: 'phone-$i', name: 'Samsung Galaxy A5$i 5G', brandName: 'Samsung', categorySlug: 'smartphones', minPricePaise: 2499900, mrpPaise: 2799900, inStock: true),
    ]);
    await pumpScreen(tester, OfferDetailScreen(offerId: diwali.id), overrides: [offersApiProvider.overrideWithValue(api)]);
    await tester.pumpAndSettle();
    expect(find.text('Flat ₹500 off phones'), findsOneWidget);
    expect(find.text('DIWALI500'), findsOneWidget);
    expect(find.textContaining('Valid till'), findsOneWidget);
    await scrollTo(tester, find.text('Galaxy A52 5G'));
    expect(find.text('Products in this offer'), findsOneWidget);

    await pumpScreen(tester, const OfferDetailScreen(offerId: 'gone'), overrides: [offersApiProvider.overrideWithValue(api)]);
    await tester.pumpAndSettle();
    expect(find.text('This offer has ended'), findsOneWidget);
  });

  testWidgets('refer & earn: code, WhatsApp share, counts, and a friend’s code with plain errors', (tester) async {
    final api = FakeOffersApi(
      referral: const Referral(enabled: true, code: 'ASHA2026', friendPaise: 20000, rewardPaise: 20000, minOrderPaise: 199900, joined: 3, rewarded: 1, canEnterCode: true),
    );
    await pumpScreen(tester, const ReferScreen(), overrides: [offersApiProvider.overrideWithValue(api)]);
    await tester.pumpAndSettle();
    expect(find.text('Give ₹200, get ₹200'), findsOneWidget);
    expect(find.text('ASHA2026'), findsOneWidget);
    await scrollTo(tester, find.text('Friends joined'));
    expect(find.bySemanticsLabel('Friends joined: 3'), findsOneWidget);
    final share = referralShareUri(api.referral!);
    expect((share.scheme, share.host, share.path), ('https', 'wa.me', '/'));
    expect(share.queryParameters['text'], contains('ASHA2026'));

    await scrollTo(tester, find.text('Have a friend’s code?'));
    api.referralError = const PostgrestException(message: 'REFERRAL_SELF', code: 'P0001');
    await tester.enterText(find.widgetWithText(TextField, 'Friend’s code'), 'asha2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(find.text('That’s your own code. Share it with a friend instead.'), findsOneWidget);

    api.referralError = null;
    await tester.enterText(find.widgetWithText(TextField, 'Friend’s code'), 'rahul123');
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'referral RAHUL123');
    expect(find.textContaining('Use FRIEND8X2K for ₹200 off'), findsOneWidget);
    await _scrollToEnd(tester);

    api.referral = const Referral(enabled: false, code: '', friendPaise: 0, rewardPaise: 0, minOrderPaise: 0);
    await pumpScreen(tester, const ReferScreen(), overrides: [offersApiProvider.overrideWithValue(api)]);
    await tester.pumpAndSettle();
    expect(find.text('Refer & earn isn’t running right now'), findsOneWidget);
  });

  testWidgets('product page: a gold chip per offer, tap for its terms', (tester) async {
    final product = Product(
      id: 'p1',
      slug: 'galaxy-s25',
      name: 'Samsung Galaxy S25 5G',
      brand: const Brand(id: 'b', slug: 'samsung', name: 'Samsung'),
      category: const Category(id: 'c', slug: 'smartphones', name: 'Phones', kind: CategoryKind.phone),
      variants: [_line.variant],
    );
    await pumpScreen(tester, const ProductScreen(slug: 'galaxy-s25'), routes: ['/offers/:id'], overrides: [
      productProvider.overrideWith((ref, slug) async => product),
      offersApiProvider.overrideWithValue(FakeOffersApi(offers: [diwali, festiveSale])),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('₹500 off with DIWALI500'), findsOneWidget);
    expect(find.text('10% off · Festive sale: 10% off accessories'), findsOneWidget);
    await tester.tap(find.text('₹500 off with DIWALI500'));
    await tester.pumpAndSettle();
    expect(find.text('Page /offers/${diwali.id}'), findsOneWidget);
  });

  testWidgets('account: Offers & coupons always, Refer & earn only while it runs', (tester) async {
    const user = User(id: 'user-1', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-10-29T00:00:00Z', email: 'asha@example.com');
    final overrides = [currentUserProvider.overrideWithValue(user), profileProvider.overrideWithValue(const AsyncData(null))];
    await pumpScreen(tester, const AccountScreen(), overrides: overrides);
    expect(find.text('Offers & coupons'), findsOneWidget);
    expect(find.text('Refer & earn'), findsNothing);

    const on = StoreSettings(
      deliveryFeePaise: 4900,
      freeDeliveryMinPaise: 99900,
      codEnabled: true,
      codMaxPaise: 2500000,
      storePhone: '+919999999999',
      storeAddress: 'Main Road',
      repairNote: 'x',
      referralEnabled: true,
      referralFriendPaise: 15000,
      referralRewardPaise: 25000,
    );
    await pumpScreen(tester, const AccountScreen(), overrides: overrides, store: on, routes: ['/account/refer']);
    expect(find.text('Give ₹150, get ₹250'), findsOneWidget);
    await tester.tap(find.text('Refer & earn'));
    await tester.pumpAndSettle();
    expect(find.text('Page /account/refer'), findsOneWidget);
  });
}

class _PaymentApi implements PaymentApi {
  final placed = <String>[];

  @override
  Future<String> placeOrder(String addressId, PaymentMethod method, {String? couponCode}) async {
    placed.add('$addressId ${method.value} $couponCode');
    return 'order-1';
  }

  @override
  Future<Map<String, dynamic>> createPayment(String orderId) => throw UnimplementedError();

  @override
  Future<OrderStatus> verifyPayment(SheetPaid paid) => throw UnimplementedError();
}
