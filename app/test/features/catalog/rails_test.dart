// "Fits this phone", "Similar products" and "Recently viewed", with a fake RailsApi; the product page at 360 dp and
// 1.4x text with the gallery, share button and rails.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/data/rails.dart';
import 'package:shyam_mobiles/features/catalog/screens/product_screen.dart';
import 'package:shyam_mobiles/features/catalog/widgets/product_rail.dart';

import '../repairs/layout_harness.dart';
import 'screens_smoke_test.dart' show card, cards, product;

class FakeRailsApi implements RailsApi {
  FakeRailsApi({this.fitting = const [], this.near = const [], this.all = const []});

  final List<ProductCard> fitting;
  final List<ProductCard> near;
  final List<ProductCard> all;
  final calls = <String>[];

  @override
  Future<List<ProductCard>> fits(Set<String> names) async {
    calls.add('fits ${names.join(' | ')}');
    return fitting;
  }

  @override
  Future<List<ProductCard>> similar(String categorySlug, int pricePaise, String excludeId) async {
    calls.add('similar $categorySlug $pricePaise $excludeId');
    return near;
  }

  @override
  Future<List<ProductCard>> cards(List<String> ids) async => [for (final c in all) if (ids.contains(c.id)) c];

  @override
  Future<List<ProductCard>> latest() async => all;
}

void main() {
  test('closestByPrice: nearest first, a tie goes to the cheaper, at most 8', () {
    final many = [for (var i = 0; i < 12; i++) card('c$i', 'Phone $i', 'Brand', 10000 + i * 1000)];
    final picked = closestByPrice(many, 15000 * 100);
    expect([for (final c in picked) c.minPricePaise ~/ 100], [15000, 14000, 16000, 13000, 17000, 12000, 18000, 11000]);
  });

  test('recently viewed: newest first, no repeats, the last 10', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final recent = c.read(recentlyViewedProvider.notifier);
    for (var i = 0; i < 12; i++) {
      await recent.add('p$i');
    }
    await recent.add('p5');
    final ids = await c.read(recentlyViewedProvider.future);
    expect(ids, ['p5', 'p11', 'p10', 'p9', 'p8', 'p7', 'p6', 'p4', 'p3', 'p2']);
    expect((await SharedPreferences.getInstance()).getStringList('recently_viewed'), ids);
  });

  test('recent cards follow the viewing order and drop products that are gone', () async {
    SharedPreferences.setMockInitialValues({
      'recently_viewed': ['pixel', 'gone', 's25'],
    });
    final c = ProviderContainer(overrides: [railsApiProvider.overrideWithValue(FakeRailsApi(all: cards))]);
    addTearDown(c.dispose);
    final sub = c.listen(recentCardsProvider, (_, _) {});
    addTearDown(sub.close);
    expect([for (final p in await c.read(recentCardsProvider.future)) p.id], ['pixel', 's25']);
  });

  testWidgets('a phone page shows the gallery, Fits this phone and Similar products, and fits 360 dp at 1.4x',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = FakeRailsApi(fitting: [cards[3]], near: [cards[1], cards[4]]);
    final phone = Product(
      id: product.id,
      slug: product.slug,
      name: product.name,
      brand: product.brand,
      category: const Category(id: 'c', slug: 'smartphones', name: 'Smartphones', kind: CategoryKind.phone),
      specs: product.specs,
      images: const [
        ProductPhoto(id: '1', path: 'p/navy.webp', color: 'Navy'),
        ProductPhoto(id: '2', path: 'p/icy.webp', color: 'Icyblue'),
        ProductPhoto(id: '3', path: 'p/box.webp'),
      ],
      variants: product.variants,
    );
    await pumpScreen(tester, const ProductScreen(slug: 's25'), overrides: [
      productProvider.overrideWith((ref, slug) async => phone),
      railsApiProvider.overrideWithValue(api),
    ]);
    await tester.pump();
    expect(find.byTooltip('Share'), findsOneWidget);
    // Navy is picked (cheapest in stock): its photo, then the untagged box shot
    expect(find.bySemanticsLabel('Photo 1 of 2, opens full screen'), findsOneWidget);
    await scrollTo(tester, find.text('Similar products'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Fits this phone'), findsOneWidget);
    expect(api.calls, containsAll(['fits Galaxy S25 | Samsung Galaxy S25', 'similar smartphones 7499900 p']));
    await scrollTo(tester, find.text('Ultra Hybrid Case for iPhone 16'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rails hide when empty or failing; Home shows Recently viewed only once something was opened',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [railsApiProvider.overrideWithValue(FakeRailsApi(all: cards))],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            const ProductRail(title: 'Empty', value: AsyncData([])),
            ProductRail(title: 'Broken', value: AsyncError(Exception('offline'), StackTrace.empty)),
            const RecentlyViewedRail(),
          ]),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Empty'), findsNothing);
    expect(find.text('Broken'), findsNothing);
    expect(find.text('Recently viewed'), findsNothing);
    final container = ProviderScope.containerOf(tester.element(find.byType(ListView)));
    await container.read(recentlyViewedProvider.notifier).add('pixel');
    await tester.pump();
    await tester.pumpAndSettle(); // the rail rises in
    expect(find.text('Recently viewed'), findsOneWidget);
    expect(find.text('Pixel 9a'), findsOneWidget);
  });
}
