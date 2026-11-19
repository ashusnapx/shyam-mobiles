// Made-to-order accessories for any phone: search offers them for a model-like query (after the real results), the
// product page needs "Your phone model", and the cart, checkout and order pages say who it's for. Plus Mor, the
// product page's slow-load view: never under 400 ms, still with reduced motion.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/widgets/mascot.dart';
import 'package:shyam_mobiles/features/account/data/addresses.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/cart/screens/cart_screen.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog_repository.dart';
import 'package:shyam_mobiles/features/catalog/data/phone_models.dart';
import 'package:shyam_mobiles/features/catalog/data/rails.dart';
import 'package:shyam_mobiles/features/catalog/screens/product_screen.dart';
import 'package:shyam_mobiles/features/catalog/screens/search_screen.dart';
import 'package:shyam_mobiles/features/offers/data/offers.dart';
import 'package:shyam_mobiles/features/orders/data/orders.dart';
import 'package:shyam_mobiles/features/orders/screens/order_detail_screen.dart';
import 'package:shyam_mobiles/features/reviews/data/reviews_repository.dart';

import '../../fakes/fake_catalog_repository.dart';
import '../../fakes/fake_reviews_repository.dart';
import '../offers/fakes.dart';
import '../repairs/layout_harness.dart';

const _cover = Variant(
  id: 'mto1',
  productId: 'bc',
  sku: 'MTO-BACK-COVER',
  name: 'For your phone',
  pricePaise: 19900,
  mrpPaise: 19900,
  stock: 0,
  madeToOrder: true,
  leadDays: 3,
);

final _coverProduct = Product(
  id: 'bc',
  slug: 'back-cover-any-phone',
  name: 'Back cover',
  brand: const Brand(id: 'g', slug: 'generic', name: 'Generic'),
  category: const Category(id: 'cc', slug: 'cases-covers', name: 'Cases & covers', kind: CategoryKind.accessory),
  variants: const [_cover],
);

ProductCard _card(String id, String name, {bool mto = false, int rupees = 199}) => ProductCard(
  id: id,
  slug: id,
  name: name,
  brandName: 'Generic',
  categorySlug: 'cases-covers',
  minPricePaise: rupees * 100,
  mrpPaise: rupees * 100,
  inStock: true,
  madeToOrder: mto,
  leadDays: mto ? 2 : null,
);

class _Cart extends CartNotifier {
  _Cart([this.lines = const []]);

  final List<CartLine> lines;
  final added = <String>[];

  @override
  Future<List<CartLine>> build() async => lines;

  @override
  Future<void> add(Variant variant, {int qty = 1, String? forModel}) async => added.add('${variant.id} $forModel');
}

class _Addresses extends AddressesNotifier {
  @override
  Future<List<Address>> build() async => const [];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'zoom_hint_seen': true}));

  group('model queries', () {
    test('a brand word or "word number" is a model; specs and plain accessories are not', () {
      for (final q in ['samsung', 'galaxy a15 cover', 'iphone 15 pro max', 'note 13', 'Nothing Phone 2a', 'iQOO z9']) {
        expect(isModelQuery(q), isTrue, reason: q);
      }
      for (final q in ['back cover', 'charger 65w', 'power bank 10000 mah', 'cover 2', '']) {
        expect(isModelQuery(q), isFalse, reason: q);
      }
    });

    test('tidies the model as typed and drops the accessory words', () {
      expect(modelOf('samsung  galaxy a15 5g back cover'), 'Samsung Galaxy A15 5G');
      expect(modelOf('iphone se tempered glass'), 'iPhone SE');
      expect(modelOf('redmi note 13 pro+ ka cover'), 'Redmi Note 13 Pro+');
      expect(tidyModel('x'), isNull, reason: 'under 2 characters');
      expect(tidyModel('<b>A15</b>'), isNull, reason: 'characters a model never has');
      expect(tidyModel('a' * 61), isNull, reason: 'over 60 characters');
      expect(modelKey('Galaxy A 15'), modelKey('galaxy a15'));
    });
  });

  testWidgets('search: real results first, then "Accessories for <model>", which opens the type with the model', (
    tester,
  ) async {
    final repo = FakeCatalogRepository()
      ..cardList = [
        _card('a15', 'Samsung Galaxy A15 5G', rupees: 13999),
        _card('back-cover-any-phone', 'Back cover', mto: true),
        _card('tempered-glass-any-phone', 'Tempered glass', mto: true, rupees: 149),
      ];
    await pumpScreen(
      tester,
      const SearchScreen(query: 'galaxy a15'),
      routes: ['/product/:slug'],
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpAndSettle();
    final header = find.text('Accessories for Galaxy A15');
    await scrollTo(tester, header);
    expect(header, findsOneWidget);
    expect(find.text('from ₹149 · ready in 2 days'), findsOneWidget, reason: 'cheapest first, honest lead time');
    expect(find.textContaining('in stock'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Samsung Galaxy A15 5G')).dy,
      lessThan(tester.getTopLeft(header).dy),
      reason: 'the real phone comes first',
    );

    await tester.tap(find.text('Back cover').last);
    await tester.pumpAndSettle();
    expect(find.text('Page /product/back-cover-any-phone?for=Galaxy+A15'), findsOneWidget);
  });

  testWidgets('search: a model the shop has never listed still gets the section, not "couldn\'t find"', (tester) async {
    final repo = FakeCatalogRepository()..cardList = [_card('back-cover-any-phone', 'Back cover', mto: true)];
    await pumpScreen(
      tester,
      const SearchScreen(query: 'vivo y400 pro cover'),
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpAndSettle();
    expect(find.text('Accessories for vivo Y400 Pro'), findsOneWidget);
    expect(find.text('We couldn’t find that'), findsNothing);
  });

  testWidgets('product page: the model is prefilled, required, and goes on the cart line', (tester) async {
    final cart = _Cart();
    await pumpScreen(
      tester,
      const ProductScreen(slug: 'back-cover-any-phone', forModel: 'galaxy a15'),
      overrides: [
        productProvider.overrideWith((ref, slug) async => _coverProduct),
        cartProvider.overrideWith(() => cart),
        catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()..models = ['Redmi Note 13 Pro 5G']),
        reviewsRepositoryProvider.overrideWithValue(FakeReviewsRepository()),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Galaxy A15'), findsOneWidget, reason: 'prefilled from ?for=, tidied');
    expect(find.text('Arranged for your phone · ships in 3 days'), findsOneWidget);
    expect(find.text('Arranged for your phone'), findsOneWidget);
    expect(find.text('In stock'), findsNothing);

    final field = find.byType(TextField);
    await tester.enterText(field, ' ');
    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();
    expect(find.text('Type your phone model, like Galaxy A15'), findsOneWidget);
    expect(cart.added, isEmpty);

    await tester.enterText(field, 'redmi');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redmi Note 13 Pro 5G'), warnIfMissed: false); // a learned suggestion
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();
    expect(cart.added, ['mto1 Redmi Note 13 Pro 5G']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cart: a made-to-order line says who it is for; without a model it blocks checkout', (tester) async {
    CartLine line(String? model) => CartLine(
      variant: _cover,
      qty: 1,
      productId: 'bc',
      productSlug: 'back-cover-any-phone',
      productName: 'Back cover',
      forModel: model,
    );
    await pumpScreen(
      tester,
      const CartScreen(),
      overrides: [
        cartProvider.overrideWith(() => _Cart([line('Galaxy A15')])),
        addressesProvider.overrideWith(_Addresses.new),
        offersApiProvider.overrideWithValue(FakeOffersApi()),
        fitsProvider.overrideWith((ref, slug) => const <ProductCard>[]),
        recentCardsProvider.overrideWith((ref) => const <ProductCard>[]),
        homeProvider.overrideWithValue(
          const AsyncData((categories: <Category>[], featured: <ProductCard>[], accessories: <ProductCard>[])),
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('For: Galaxy A15'), findsOneWidget);
    expect(find.text('Arranged for your phone · ships in 3 days'), findsOneWidget);
    expect(find.text('Out of stock'), findsNothing, reason: 'no stock is not "out of stock" here');
    expect(lineWarning(line(null))?.text, 'Tap to add your phone model');
    expect(line(null).purchasable, isFalse);
    expect(line('Galaxy A15').purchasable, isTrue);
  });

  testWidgets('order page: "For:" on the made-to-order line', (tester) async {
    final order = Order(
      id: 'o1',
      number: 'SM100024',
      status: OrderStatus.confirmed,
      paymentMethod: PaymentMethod.cod,
      paymentStatus: PaymentStatus.pending,
      subtotalPaise: 19900,
      deliveryFeePaise: 4900,
      totalPaise: 24800,
      address: const Address(
        name: 'Asha Verma',
        phone: '+919876543210',
        line1: 'Ward 4',
        city: 'Waidhan',
        state: 'MP',
        pincode: '486886',
      ),
      createdAt: DateTime(2026, 11, 19),
      items: const [
        OrderItem(
          id: 'i1',
          productId: 'bc',
          productName: 'Back cover',
          variantName: 'For your phone',
          unitPricePaise: 19900,
          qty: 1,
          forModel: 'Galaxy A15',
        ),
      ],
      events: [OrderEvent(status: OrderStatus.confirmed, createdAt: DateTime(2026, 11, 19))],
    );
    await pumpScreen(
      tester,
      const OrderDetailScreen(orderId: 'o1'),
      overrides: [
        orderProvider('o1').overrideWith((ref) async => order),
        fitsProvider.overrideWith((ref, slug) async => const <ProductCard>[]),
        reviewsRepositoryProvider.overrideWithValue(FakeReviewsRepository()),
      ],
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('For: Galaxy A15 · arranged for your phone'));
    expect(find.text('For: Galaxy A15 · arranged for your phone'), findsOneWidget);
  });

  group('Mor, the slow-load view', () {
    testWidgets('a fast load never shows it', (tester) async {
      await pumpScreen(
        tester,
        const ProductScreen(slug: 'back-cover-any-phone'),
        overrides: [
          productProvider.overrideWith(
            (ref, slug) => Future.delayed(const Duration(milliseconds: 200), () => _coverProduct),
          ),
          cartProvider.overrideWith(_Cart.new),
          catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
          reviewsRepositoryProvider.overrideWithValue(FakeReviewsRepository()),
        ],
      ); // 300 ms in: loaded
      expect(find.byType(MascotLoader), findsNothing);
      expect(find.text('Did you know?'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Did you know?'), findsNothing);
    });

    testWidgets('a slow load shows Mor and a fact after 400 ms, labelled for screen readers', (tester) async {
      final never = Completer<Product?>();
      await pumpScreen(
        tester,
        const ProductScreen(slug: 'back-cover-any-phone'),
        overrides: [productProvider.overrideWith((ref, slug) => never.future), cartProvider.overrideWith(_Cart.new)],
      ); // 300 ms in
      expect(find.text('Did you know?'), findsNothing, reason: 'nothing flashes before 400 ms');
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Did you know?'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Loading\. .+')), findsOneWidget);
      expect(moFacts, hasLength(40));
    });

    testWidgets('reduced motion: Mor holds still', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => MediaQuery(
              data: MediaQuery.of(c).copyWith(disableAnimations: true),
              child: const Scaffold(body: MascotLoader()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Did you know?'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'no bob, no blink');

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MascotLoader())));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'it bobs when motion is fine');
    });
  });
}
