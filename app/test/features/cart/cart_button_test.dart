// The product page (no bottom nav) has a cart in its top bar, with the count. The cart and the brand link open over
// the page, so Back returns to it (going to the Cart or Search tab dropped the product).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/screens/product_screen.dart';

import '../catalog/screens_smoke_test.dart' show product;
import '../repairs/layout_harness.dart';

void main() {
  testWidgets('product page: the cart button shows the count and opens the cart; Back returns', (tester) async {
    await pumpScreen(tester, const ProductScreen(slug: 's25'), routes: ['/bag'], overrides: [
      productProvider.overrideWith((ref, slug) async => product),
      cartCountProvider.overrideWithValue(3),
    ]);
    expect(find.byTooltip('Cart, 3 items'), findsOneWidget);
    expect(find.descendant(of: find.byTooltip('Cart, 3 items'), matching: find.text('3')), findsOneWidget);
    await tester.tap(find.byTooltip('Cart, 3 items'));
    await tester.pumpAndSettle();
    expect(find.text('Page /bag'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cart, 3 items'), findsOneWidget, reason: 'back on the product page');
  });

  testWidgets('product page: the brand opens its list over the page; Back returns', (tester) async {
    await pumpScreen(tester, const ProductScreen(slug: 's25'), routes: ['/browse'], overrides: [
      productProvider.overrideWith((ref, slug) async => product),
      cartCountProvider.overrideWithValue(0),
    ]);
    await tester.tap(find.text('SAMSUNG'));
    await tester.pumpAndSettle();
    expect(find.text('Page /browse?brand=samsung'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('SAMSUNG'), findsOneWidget, reason: 'back on the product page');
  });

  testWidgets('an empty cart: no badge', (tester) async {
    await pumpScreen(tester, const ProductScreen(slug: 's25'), overrides: [
      productProvider.overrideWith((ref, slug) async => product),
      cartCountProvider.overrideWithValue(0),
    ]);
    expect(find.byTooltip('Cart'), findsOneWidget);
    expect(tester.widget<Badge>(find.descendant(of: find.byTooltip('Cart'), matching: find.byType(Badge))).isLabelVisible,
        isFalse);
  });
}
