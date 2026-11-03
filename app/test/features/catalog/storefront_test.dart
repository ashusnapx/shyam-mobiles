// The storefront's anatomy: one tile layout everywhere, Home's order, and the product page's selling blocks.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shyam_mobiles/core/format.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/data/rails.dart';
import 'package:shyam_mobiles/features/catalog/widgets/product_tile.dart';
import 'package:shyam_mobiles/features/offers/data/offers.dart';
import 'package:shyam_mobiles/features/wishlist/data/wishlist.dart';

import 'rails_test.dart' show FakeRailsApi;
import 'screens_smoke_test.dart';

void main() {
  setUpAll(loadRoboto);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tiles in a row line up: full names, the price block the same height with or without a discount',
      (tester) async {
    await pump(tester, '/wishlist', userId: 'u1', overrides: [
      wishlistCardsProvider.overrideWithBuild((ref, _) async => (
            items: [
              card('s25', 'Samsung Galaxy S25', 'Samsung', 74999),
              ProductCard(
                id: 'case',
                slug: 'case',
                name: 'OnePlus 13',
                brandName: 'OnePlus',
                categorySlug: 'smartphones',
                minPricePaise: 6999900,
                mrpPaise: 6999900, // no discount
                inStock: false,
              ),
            ],
            hasMore: false,
            moreFailed: false,
          )),
    ]);
    expect(find.text('OnePlus 13'), findsOneWidget, reason: 'the full name, never "13"');
    expect(find.text('ONEPLUS'), findsNothing, reason: 'no brand eyebrow over a name that already starts with it');
    final tiles = find.byType(ProductTile);
    expect(tester.getSize(tiles.at(0)).height, tester.getSize(tiles.at(1)).height);
    expect(find.text('9% off'), findsOneWidget);

    final soldOut = tester.widget<Text>(find.text('Out of stock'));
    expect(soldOut.style?.color, BrandColors.graphite, reason: 'sold out is closed, not an error');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a saved heart is plum, not red', (tester) async {
    await pump(tester, '/wishlist', userId: 'u1', overrides: [
      wishlistCardsProvider.overrideWithBuild((ref, _) async => (items: [cards[0]], hasMore: false, moreFailed: false)),
    ]);
    final heart = tester.widget<Icon>(find.descendant(of: find.byTooltip('Remove from wishlist'), matching: find.byType(Icon)));
    expect(heart.color, BrandColors.plum);
  });

  testWidgets('home: carousel, why buy here, categories, phones, then the one repair strip; deals link to their cap',
      (tester) async {
    final phones = [cards[0], cards[1], cards[4]];
    await pump(tester, '/', overrides: [
      homeProvider.overrideWith((ref) async => (
            categories: const [Category(id: 'c', slug: 'smartphones', name: 'Smartphones', kind: CategoryKind.phone)],
            featured: phones,
            accessories: [cards[3]],
          )),
      railsApiProvider.overrideWithValue(FakeRailsApi(all: cards)),
    ]);
    await tester.pumpAndSettle();
    final order = [
      for (final s in tester.widget<CustomScrollView>(find.byType(CustomScrollView)).slivers)
        if (s.key case ValueKey<String>(:final value)) value,
    ];
    expect(order.take(9), ['top', 'hero', 'trust', 'categories', 'recent', 'phones', 'repair', 'budget', 'deals']);
    expect(order, containsAllInOrder(['deals', 'brands', 'more', 'store']));
    expect(find.text('Genuine products'), findsOneWidget);
    expect(find.text('Cash on delivery'), findsOneWidget);
    expect(find.text('Free delivery over ₹999'), findsOneWidget);
    expect(find.text('Repairs'), findsNothing, reason: 'Repairs is a tab and a strip, not a category');

    await tester.tap(find.text('Genuine products'));
    await tester.pumpAndSettle();
    expect(find.text('Why buy from us'), findsOneWidget);
    expect(find.text('No platform, COD or packing fees'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Deals under ₹1,500'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final dealsSeeAll = find.descendant(
      of: find.ancestor(of: find.text('Deals under ₹1,500'), matching: find.byType(Row)).first,
      matching: find.text('See all'),
    );
    tester.widget<TextButton>(find.ancestor(of: dealsSeeAll, matching: find.byWidgetPredicate((w) => w is TextButton))).onPressed!();
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/search?max=150000');
  });

  testWidgets('product page: full name, You save, the best offer with its price, why buy here, and the WhatsApp bar',
      (tester) async {
    final sale = Offer(
      id: 'sale',
      title: 'Festive phone sale',
      kind: OfferKind.flat,
      value: 200000,
      startsAt: DateTime(2026),
      endsAt: DateTime(2026, 11, 29, 12),
    );
    final coupon = Offer(id: 'c', title: 'Coupon', kind: OfferKind.percent, value: 1, code: 'ACC1', startsAt: DateTime(2026));
    await pump(tester, '/product/s25', overrides: [
      productProvider.overrideWith((ref, slug) async => product),
      productOffersProvider.overrideWith((ref, id) async => [coupon, sale]),
      railsApiProvider.overrideWithValue(FakeRailsApi()),
    ]);
    await tester.pump();
    expect(find.text('Samsung Galaxy S25'), findsOneWidget);
    expect(find.text('You save ${formatInr(8099892 - 7499900)} (7%)'), findsOneWidget); // the fixture's MRP is price × 1.08
    expect(find.textContaining('EMI options at checkout'), findsNothing);
    expect(
      find.textContaining('Pay ₹72,999 at checkout · Festive phone sale · No code needed · Ends 29 Nov', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('+1 more offer'), findsOneWidget);
    expect(find.byTooltip('Ask on WhatsApp'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Genuine and sealed'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Why buy from us'), findsOneWidget);
    expect(find.text('Check the IMEI with *#06# when it arrives'), findsOneWidget);
    expect(find.text('Returns & warranty policy'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('About this phone'), 300, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sold-out pick with nothing else in stock asks on WhatsApp to hear when it’s back', (tester) async {
    final gone = Product(
      id: 'p',
      slug: 's25',
      name: product.name,
      brand: product.brand,
      category: product.category,
      variants: [variant('only', 74999, 0, '256 GB', 'Navy')],
    );
    await pump(tester, '/product/s25', overrides: [
      productProvider.overrideWith((ref, slug) async => gone),
      productOffersProvider.overrideWith((ref, id) async => const []),
      railsApiProvider.overrideWithValue(FakeRailsApi()),
    ]);
    await tester.pump();
    expect(find.text('Ask on WhatsApp when it’s back'), findsOneWidget);
    expect(find.text('Add to cart'), findsNothing);
  });
}
