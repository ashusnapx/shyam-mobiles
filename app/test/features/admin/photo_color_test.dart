// The product editor's per-photo colour at 360 dp and 1.4x text.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/admin.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_product_edit_screen.dart';

import '../repairs/layout_harness.dart';

const _brand = Brand(id: 'br1', slug: 'samsung', name: 'Samsung');
const _category = Category(id: 'c1', slug: 'phones', name: 'Phones', kind: CategoryKind.phone);

Variant _variant(String id, String color) => Variant(
      id: id,
      productId: 'p1',
      sku: 'S25-$id',
      name: '12 GB · 256 GB · $color',
      pricePaise: 7499900,
      mrpPaise: 8099900,
      stock: 3,
      attributes: {'ram': '12 GB', 'storage': '256 GB', 'color': color},
    );

void main() {
  testWidgets('each photo shows its colour, "Any colour" when untagged, and the choices are the variant colours',
      (tester) async {
    await pumpScreen(tester, const AdminProductEditScreen(productId: 'p1'), overrides: [
      adminBrandsProvider.overrideWithValue(const AsyncData([_brand])),
      adminCategoriesProvider.overrideWithValue(const AsyncData([_category])),
      adminProductProvider.overrideWith((ref, id) => Product(
            id: 'p1',
            slug: 'samsung-galaxy-s25',
            name: 'Samsung Galaxy S25',
            brand: _brand,
            category: _category,
            images: const [
              ProductPhoto(id: 'a', path: 'p1/1.webp', color: 'Titanium Silverblue'),
              ProductPhoto(id: 'b', path: 'p1/2.webp', sort: 1),
            ],
            variants: [_variant('v1', 'Titanium Silverblue'), _variant('v2', 'Navy')],
          )),
    ]);
    await scrollTo(tester, find.text('Any colour'));
    expect(find.text('Titanium Silverblue'), findsOneWidget);
    await tester.tap(find.text('Any colour'));
    await tester.pumpAndSettle();
    expect(find.text('Navy'), findsOneWidget); // in the sheet
    expect(find.text('Any colour'), findsNWidgets(2)); // the field, and the sheet's first row
    expect(tester.takeException(), isNull);
  });
}
