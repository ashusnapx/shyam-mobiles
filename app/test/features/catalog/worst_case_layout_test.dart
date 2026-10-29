// The worst a real catalogue can look, at 360x800 dp and 1.3x text: no overflow, no crash.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';

import 'screens_smoke_test.dart' show card, loadRoboto, pump, scrollThrough, variant;

const _long = 'Samsung Galaxy S25 Ultra 5G AI Smartphone (Titanium Silverblue, 12GB RAM, 256GB Storage) '
    'with No Cost EMI and Additional Exchange Offers, Snapdragon 8 Elite, 200 MP Camera, S Pen included in the box!!';

class _Search extends SearchNotifier {
  _Search(super.params, this.items);

  final List<ProductCard> items;

  @override
  Future<SearchResults> build() async => (items: items, total: items.length, moreFailed: false);

  @override
  Future<void> loadMore({bool retry = false}) async {}
}

SearchParams _params(String category) =>
    (q: '', category: category, brand: null, maxPricePaise: null, sort: SearchSort.relevance);

void main() {
  setUpAll(loadRoboto);

  test('the fixture name really is 200 characters', () => expect(_long.length, 200));

  testWidgets('empty catalogue: home has no featured, no accessories, no categories', (tester) async {
    await pump(tester, '/', overrides: [
      homeProvider.overrideWith((ref) async => (categories: <Category>[], featured: <ProductCard>[], accessories: <ProductCard>[])),
    ]);
    expect(find.text('The shelves are empty'), findsOneWidget);
  });

  testWidgets('categories but no products: no hero, no accessories row', (tester) async {
    await pump(tester, '/', overrides: [
      homeProvider.overrideWith((ref) async => (
            categories: const [Category(id: 'c', slug: 'smartphones', name: 'Smartphones', kind: CategoryKind.phone)],
            featured: <ProductCard>[],
            accessories: <ProductCard>[],
          )),
    ]);
    await scrollThrough(tester);
    expect(find.text('Visit the store'), findsOneWidget);
  });

  testWidgets('search: 200-character names, all out of stock', (tester) async {
    final p = _params('smartphones');
    await pump(tester, '/search?category=smartphones', overrides: [
      searchProvider(p).overrideWith(() => _Search(p, [
            for (var i = 0; i < 6; i++) card('p$i', _long, 'Samsung', 129999 + i, inStock: false),
          ])),
    ]);
    expect(find.text('Out of stock'), findsWidgets);
    await scrollThrough(tester);
  });

  testWidgets('search with no results', (tester) async {
    final none = _params('power-banks');
    await pump(tester, '/search?category=power-banks', overrides: [
      searchProvider(none).overrideWith(() => _Search(none, const [])),
    ]);
    await tester.pump();
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('product: 200-character name, 40 variants with long colours, the cheapest one sold out', (tester) async {
    const storages = ['64 GB', '128 GB', '256 GB', '512 GB', '1 TB', '2 TB', '4 TB', '8 TB'];
    const colours = ['Titanium Silverblue', 'Titanium Whitesilver', 'Titanium Jetblack', 'Icy Blue Mint', 'Coral'];
    final product = Product(
      id: 'p',
      slug: 'long',
      name: _long,
      brand: const Brand(id: 'b', slug: 'samsung', name: 'Samsung'),
      category: const Category(id: 'c', slug: 'smartphones', name: 'Smartphones', kind: CategoryKind.phone),
      description: 'x ' * 2500,
      specs: [for (var i = 0; i < 20; i++) Spec('Spec label $i', 'A long value for spec $i ' * 8)],
      variants: [
        for (final (i, s) in storages.indexed)
          for (final (j, c) in colours.indexed) variant('v$i$j', 49999 + i * 10000, i == 0 && j == 0 ? 0 : 3, s, c),
      ],
    );
    expect(product.variants, hasLength(40));
    await pump(tester, '/product/long', overrides: [productProvider.overrideWith((ref, slug) async => product)]);
    expect(find.text('Add to cart'), findsOneWidget);
    await scrollThrough(tester);
    await scrollThrough(tester);
  });
}
