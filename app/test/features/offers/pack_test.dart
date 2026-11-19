// Phone packs: the accessory types and the saving match the server's rules, and the "Complete your pack" card
// replaces the accessory rail on a phone page only while a pack runs, adding nothing until it's tapped.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog_repository.dart';
import 'package:shyam_mobiles/features/catalog/data/rails.dart';
import 'package:shyam_mobiles/features/catalog/screens/product_screen.dart';
import 'package:shyam_mobiles/features/offers/data/offers_repository.dart';
import 'package:shyam_mobiles/features/offers/data/packs.dart';
import 'package:shyam_mobiles/features/reviews/data/reviews_repository.dart';

import '../../fakes/fake_catalog_repository.dart';
import '../../fakes/fake_offers_repository.dart';
import '../../fakes/fake_reviews_repository.dart';
import '../catalog/screens_smoke_test.dart' show product;
import '../repairs/layout_harness.dart';

const _pack = PackOffer(id: 'pk', title: 'Phone pack', percent: 10, types: [PackType.glass, PackType.cover], categoryIds: {'c'});

ProductCard _card(String id, String name, String category, int paise, {bool mto = false}) => ProductCard(
      id: id,
      slug: id,
      name: name,
      brandName: 'B',
      categorySlug: category,
      minPricePaise: paise,
      mrpPaise: paise,
      inStock: true,
      madeToOrder: mto,
      leadDays: mto ? 2 : null,
    );

Product _accessory(String id, String name, int paise, {bool mto = false}) => Product(
      id: id,
      slug: id,
      name: name,
      brand: const Brand(id: 'g', slug: 'g', name: 'B'),
      category: const Category(id: 'a', slug: 'a', name: 'Accessories', kind: CategoryKind.accessory),
      variants: [
        Variant(id: '$id-v', productId: id, sku: id, name: 'One', pricePaise: paise, mrpPaise: paise, stock: mto ? 0 : 4,
            madeToOrder: mto),
      ],
    );

class _Cart extends CartNotifier {
  final added = <String>[];

  @override
  Future<List<CartLine>> build() async => const [];

  @override
  Future<void> add(Variant variant, {int qty = 1, String? forModel}) async => added.add('${variant.id} $forModel');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'zoom_hint_seen': true}));

  test('accessory types follow the server: lens first, then category or name', () {
    expect(accessoryType('screen-guards', 'Camera lens guard'), PackType.lens);
    expect(accessoryType('screen-guards', 'Clear guard'), PackType.glass);
    expect(accessoryType('cases-covers', 'Spigen Tough Armor'), PackType.cover);
    expect(accessoryType('chargers-cables', 'Samsung 25W Super Fast Charger'), PackType.charger);
    expect(accessoryType('chargers-cables', 'Anker USB-C cable'), isNull, reason: 'a cable is not a charger');
    expect(accessoryType('earbuds-headphones', 'JBL Tune 520BT'), PackType.earphones);
  });

  test('the saving: accessories only, the whole pack, and the cap', () {
    expect(_pack.savingPaise(1000000, 49900), 4990);
    expect(const PackOffer(id: 'w', title: 'W', percent: 10, types: [PackType.glass], categoryIds: {}, whole: true)
        .savingPaise(1000000, 49900), 104990);
    expect(const PackOffer(id: 'm', title: 'M', percent: 10, types: [PackType.glass], categoryIds: {}, whole: true,
            maxDiscountPaise: 50000)
        .savingPaise(1000000, 49900), 50000);
  });

  Future<_Cart> pump(WidgetTester tester, {required List<PackOffer> packs}) async {
    final cart = _Cart();
    final catalog = FakeCatalogRepository()
      ..cardList = [_card('back-cover', 'Back cover', 'cases-covers', 19900, mto: true)]
      ..productsBySlug.addAll({
        'glass1': _accessory('glass1', 'Spigen Glass for Galaxy S25', 79900),
        'back-cover': _accessory('back-cover', 'Back cover', 19900, mto: true),
      });
    await pumpScreen(tester, const ProductScreen(slug: 's25'), overrides: [
      productProvider.overrideWith((ref, slug) async => slug == 's25' ? product : catalog.productsBySlug[slug]),
      fitsProvider.overrideWith((ref, slug) async => [_card('glass1', 'Spigen Glass for Galaxy S25', 'screen-guards', 79900)]),
      catalogRepositoryProvider.overrideWithValue(catalog),
      offersRepositoryProvider.overrideWithValue(FakeOffersRepository()..packOffers = packs),
      reviewsRepositoryProvider.overrideWithValue(FakeReviewsRepository()),
      cartProvider.overrideWith(() => cart),
    ]);
    await tester.pumpAndSettle();
    return cart;
  }

  testWidgets('a running pack: one card with the phone, a fitting glass and a cover made for it; added only on tap',
      (tester) async {
    final cart = await pump(tester, packs: [_pack]);
    await scrollTo(tester, find.text('Complete your pack'));
    expect(find.text('Fits this phone'), findsNothing, reason: 'the card replaces the rail');
    expect(find.text('Spigen Glass for Galaxy S25'), findsOneWidget);
    expect(find.textContaining('For Galaxy S25 · arranged for your phone'), findsOneWidget);
    expect(find.textContaining('Save 10%'), findsOneWidget);
    expect(cart.added, isEmpty, reason: 'nothing pre-added');

    final add = find.text('Add pack to cart');
    await scrollTo(tester, add);
    await Scrollable.ensureVisible(tester.element(add), alignment: 0.5); // clear of the sticky bar
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(cart.added, [
      '${product.activeVariants.where((v) => v.inStock).reduce((a, b) => b.pricePaise < a.pricePaise ? b : a).id} null',
      'glass1-v null',
      'back-cover-v Galaxy S25',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no running pack: no card, the accessory rail stays', (tester) async {
    await pump(tester, packs: const []);
    expect(find.text('Complete your pack', skipOffstage: false), findsNothing);
  });
}
