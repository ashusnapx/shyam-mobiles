// The product page (no bottom nav) has a cart in its top bar, with the count, that opens the Cart tab.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/screens/product_screen.dart';

import '../catalog/screens_smoke_test.dart' show product;
import '../repairs/layout_harness.dart';

void main() {
  testWidgets('product page: the cart button shows the count and opens /cart', (tester) async {
    await pumpScreen(tester, const ProductScreen(slug: 's25'), routes: ['/cart'], overrides: [
      productProvider.overrideWith((ref, slug) async => product),
      cartCountProvider.overrideWithValue(3),
    ]);
    expect(find.byTooltip('Cart, 3 items'), findsOneWidget);
    expect(find.descendant(of: find.byTooltip('Cart, 3 items'), matching: find.text('3')), findsOneWidget);
    await tester.tap(find.byTooltip('Cart, 3 items'));
    await tester.pumpAndSettle();
    expect(find.text('Page /cart'), findsOneWidget);
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
