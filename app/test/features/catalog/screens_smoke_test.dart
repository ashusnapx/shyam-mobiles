// Renders the catalog screens at 360x800 dp with 1.3x text (Roboto metrics) and fails on any overflow.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/screens/home_screen.dart';
import 'package:shyam_mobiles/features/catalog/screens/product_screen.dart';
import 'package:shyam_mobiles/features/catalog/screens/search_screen.dart';
import 'package:shyam_mobiles/features/wishlist/data/wishlist.dart';
import 'package:shyam_mobiles/features/wishlist/screens/wishlist_screen.dart';

ProductCard card(String id, String name, String brand, int rupees, {bool inStock = true}) => ProductCard(
      id: id,
      slug: id,
      name: name,
      brandName: brand,
      categorySlug: 'smartphones',
      minPricePaise: rupees * 100,
      mrpPaise: rupees * 110,
      inStock: inStock,
    );

final cards = [
  card('s25', 'Samsung Galaxy S25', 'Samsung', 74999),
  card('rn14', 'Xiaomi Redmi Note 14 Pro 5G', 'Xiaomi', 23999),
  card('narzo', 'realme Narzo 80 Pro 5G', 'realme', 19999, inStock: false),
  card('case', 'Spigen Ultra Hybrid Case for iPhone 16', 'Spigen', 1299),
  card('pixel', 'Google Pixel 9a', 'Google', 49999),
];

const settings = StoreSettings(
  deliveryFeePaise: 4900,
  freeDeliveryMinPaise: 99900,
  codEnabled: true,
  codMaxPaise: 2500000,
  storePhone: '+919999999999',
  storeAddress: 'Main Road, near Bus Stand',
  storeHours: '10 am – 9 pm',
  repairNote: '',
  returnsPolicy: 'Unopened items can be returned within 7 days.',
);

Variant variant(String id, int rupees, int stock, String storage, String color) => Variant(
      id: id,
      productId: 'p',
      sku: id,
      name: '12 GB · $storage · $color',
      pricePaise: rupees * 100,
      mrpPaise: rupees * 108,
      stock: stock,
      attributes: {'ram': '12 GB', 'storage': storage, 'color': color, 'color_hex': '#2C3646'},
    );

final product = Product(
  id: 'p',
  slug: 's25',
  name: 'Samsung Galaxy S25',
  brand: const Brand(id: 'b', slug: 'samsung', name: 'Samsung'),
  category: const Category(id: 'c', slug: 'smartphones', name: 'Smartphones', kind: CategoryKind.phone),
  description: 'Compact flagship with Galaxy AI, a bright 120 Hz screen and 7 years of updates.',
  specs: const [
    Spec('Display', '6.2-inch Dynamic AMOLED 2X, 120 Hz'),
    Spec('Processor', 'Snapdragon 8 Elite for Galaxy'),
    Spec('Camera', '50 MP + 12 MP ultra-wide + 10 MP 3x tele; 12 MP front'),
    Spec('Battery', '4000 mAh, 25 W'),
  ],
  variants: [
    variant('navy256', 74999, 8, '256 GB', 'Navy'),
    variant('icy256', 74999, 0, '256 GB', 'Icyblue'),
    variant('navy512', 86999, 2, '512 GB', 'Navy'),
  ],
);

class FakeSearch extends SearchNotifier {
  FakeSearch(super.params);

  @override
  Future<SearchResults> build() async => (items: cards, total: 30, moreFailed: false);

  @override
  Future<void> loadMore({bool retry = false}) async {}
}

class FakeCart extends CartNotifier {
  final added = <String>[];

  @override
  Future<List<CartLine>> build() async => const [];

  @override
  Future<void> add(Variant variant, {int qty = 1}) async => added.add(variant.id);
}

class FakeWishlistApi implements WishlistApi {
  @override
  Future<Set<String>> productIds() async => {'s25', 'case'};
  @override
  Future<void> add(String userId, String productId) async {}
  @override
  Future<void> remove(String userId, String productId) async {}
}

Future<void> loadRoboto() async {
  final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold', 'Black']) {
    loader.addFont(File('$dir/Roboto-$w.ttf').readAsBytes().then(ByteData.sublistView));
  }
  await loader.load();
}

late GoRouter router;

Future<void> pump(
  WidgetTester tester,
  String location, {
  List overrides = const [],
  ColorScheme scheme = lightScheme,
  String? userId,
  StoreSettings store = settings,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  router = GoRouter(initialLocation: location, routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    GoRoute(path: '/search', builder: (_, s) => SearchScreen(category: s.uri.queryParameters['category'])),
    GoRoute(path: '/wishlist', builder: (_, _) => const WishlistScreen()),
    GoRoute(path: '/product/:slug', builder: (_, s) => ProductScreen(slug: s.pathParameters['slug']!)),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue(userId),
      wishlistApiProvider.overrideWithValue(FakeWishlistApi()),
      storeSettingsProvider.overrideWith((ref) async => store),
      categoriesProvider.overrideWith((ref) async => [
            for (final (i, s) in ['smartphones', 'cases-covers', 'screen-guards', 'chargers-cables', 'earbuds-headphones', 'power-banks'].indexed)
              Category(id: '$i', slug: s, name: s, kind: CategoryKind.accessory),
          ]),
      brandsProvider.overrideWith((ref) async => const [Brand(id: 'b', slug: 'samsung', name: 'Samsung')]),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: ThemeData(colorScheme: scheme, fontFamily: 'Roboto'),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> scrollThrough(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pump();
  }
}

void main() {
  setUpAll(loadRoboto);

  final homeData = (categories: <Category>[], featured: cards, accessories: cards.sublist(3));

  for (final scheme in [lightScheme]) {
    testWidgets('home renders without overflow (${scheme.brightness.name})', (tester) async {
      await pump(tester, '/', scheme: scheme, overrides: [homeProvider.overrideWith((ref) async => homeData)]);
      expect(find.text('Galaxy S25'), findsWidgets);
      await scrollThrough(tester);
      expect(find.text('Visit the store'), findsOneWidget);
    });
  }

  testWidgets('store card with 3 shop photos fits, opens the viewer and links to Maps', (tester) async {
    const withPhotos = StoreSettings(
      deliveryFeePaise: 4900,
      freeDeliveryMinPaise: 99900,
      codEnabled: true,
      codMaxPaise: 2500000,
      storePhone: '+917987559272',
      storeAddress: 'Rajeev Complex, Waidhan, District Singrauli, Madhya Pradesh 486886',
      storeLat: 24.0670269,
      storeLng: 82.6307508,
      storeMapsUrl: 'https://maps.google.com/?cid=3396347197360889573',
      storePhotos: ['store/1.jpg', 'store/2.jpg', 'store/3.jpg'], // no network in tests: the fallback well shows
      storeHours: '10 am – 9 pm',
      repairNote: '',
    );
    await pump(tester, '/', store: withPhotos, overrides: [homeProvider.overrideWith((ref) async => homeData)]);
    await scrollThrough(tester);
    expect(find.text('Visit the store'), findsOneWidget);
    expect(find.text('Photos, reviews & hours on Google Maps'), findsOneWidget);
    expect(find.bySemanticsLabel('Photo of the shop, 1 of 3'), findsOneWidget);

    await tester.drag(find.bySemanticsLabel('Photo of the shop, 1 of 3'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Photo of the shop, 2 of 3'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Photo of the shop, 2 of 3'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsNothing);
    expect(find.text('Visit the store'), findsOneWidget);
  });

  testWidgets('home skeleton renders while loading', (tester) async {
    await pump(tester, '/', overrides: [homeProvider.overrideWith((ref) => Completer<HomeData>().future)]);
    expect(find.text('Featured'), findsOneWidget);
  });

  testWidgets('search renders results, chips and count', (tester) async {
    const SearchParams initial = (q: '', category: 'smartphones', brand: null, maxPricePaise: null, sort: SearchSort.relevance);
    await pump(tester, '/search?category=smartphones', overrides: [searchProvider(initial).overrideWith(() => FakeSearch(initial))]);
    expect(find.text('30 results'), findsOneWidget);
    expect(find.text('smartphones'), findsOneWidget); // selected category chip shows its name
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.byTooltip('Save to wishlist'), findsWidgets);
  });

  testWidgets('product renders picker, delivery, specs and sticky bar', (tester) async {
    await pump(tester, '/product/s25', overrides: [productProvider.overrideWith((ref, slug) async => product)]);
    expect(find.text('Galaxy S25'), findsOneWidget);
    expect(find.text('Add to cart'), findsOneWidget);
    expect(find.text('Buy now'), findsOneWidget);
    expect(find.textContaining('+₹12,000', findRichText: true), findsOneWidget);
    await tester.tap(find.textContaining('512 GB', findRichText: true));
    await tester.pump();
    expect(find.text('Only 2 left'), findsOneWidget);
    await scrollThrough(tester);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);
  });

  testWidgets('after sign-in, ?add= adds that variant once and clears the param', (tester) async {
    final cart = FakeCart();
    await pump(tester, '/product/s25?add=navy512', userId: 'u1', overrides: [
      productProvider.overrideWith((ref, slug) async => product),
      cartProvider.overrideWith(() => cart),
    ]);
    await tester.pump();
    expect(cart.added, ['navy512']);
    expect(router.state.uri.toString(), '/product/s25');
    expect(find.text('Added to cart'), findsOneWidget);
    expect(find.text('Only 2 left'), findsOneWidget); // the resumed variant is selected
    await tester.pump(const Duration(milliseconds: 100));
    expect(cart.added, ['navy512']);
  });

  testWidgets('unknown product shows the not-available state', (tester) async {
    await pump(tester, '/product/nope', overrides: [productProvider.overrideWith((ref, slug) async => null)]);
    expect(find.text('This product isn’t available'), findsOneWidget);
  });

  testWidgets('wishlist shows saved cards', (tester) async {
    await pump(tester, '/wishlist', userId: 'u1', overrides: [
      wishlistCardsProvider.overrideWith((ref) async => [cards[0], cards[3]]),
    ]);
    expect(find.text('Galaxy S25'), findsOneWidget);
    expect(find.byTooltip('Remove from wishlist'), findsNWidgets(2));
  });
}
