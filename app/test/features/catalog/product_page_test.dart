// The product page at 360 dp and 1.4x text: a sold-out option can be looked at (and offers the one in stock), and
// the gallery zooms in place with a button and says so once.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/screens/product_screen.dart';
import 'package:shyam_mobiles/features/catalog/widgets/gallery.dart';

import '../repairs/layout_harness.dart';
import 'screens_smoke_test.dart' show product, variant;

final _withPhotos = Product(
  id: product.id,
  slug: product.slug,
  name: product.name,
  brand: product.brand,
  category: product.category,
  images: const [
    ProductPhoto(id: '1', path: 'p/navy.webp', color: 'Navy'),
    ProductPhoto(id: '2', path: 'p/icy.webp', color: 'Icyblue'),
  ],
  variants: [
    variant('navy256', 74999, 8, '256 GB', 'Navy'),
    variant('icy256', 74999, 0, '256 GB', 'Icyblue'), // sold out
    variant('navy512', 86999, 2, '512 GB', 'Navy'),
  ],
);

Future<void> _pump(WidgetTester tester) async {
  await pumpScreen(tester, const ProductScreen(slug: 's25'), overrides: [
    productProvider.overrideWith((ref, slug) async => _withPhotos),
  ]);
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'zoom_hint_seen': true}));

  testWidgets('a sold-out colour can be picked to see it; the bar says so and offers the one in stock', (tester) async {
    await _pump(tester);
    expect(find.text('Add to cart'), findsOneWidget, reason: 'opens on the in-stock Navy');
    final icy = find.bySemanticsLabel('Icyblue, sold out');
    await scrollTo(tester, icy);
    await Scrollable.ensureVisible(tester.element(icy), alignment: 0.5); // clear of the floating top buttons
    await tester.pumpAndSettle();
    await tester.tap(icy);
    await tester.pumpAndSettle();
    expect(find.text('Add to cart'), findsNothing);
    expect(find.text('Buy now'), findsNothing);
    expect(find.textContaining('Out of stock', findRichText: true), findsWidgets);
    expect(find.text('See Navy in stock'), findsOneWidget);
    expect(tester.widget<ProductGallery>(find.byType(ProductGallery, skipOffstage: false)).paths, ['p/icy.webp'],
        reason: 'its own photo shows');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('See Navy in stock'));
    await tester.pumpAndSettle();
    expect(find.text('Add to cart'), findsOneWidget);
    expect(find.text('See Navy in stock'), findsNothing);
  });

  testWidgets('the Zoom button zooms in place and stops the page scrolling, so one finger pans', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Zoom out'), findsOneWidget);
    final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer).first);
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), greaterThan(2));
    expect(viewer.panEnabled, isTrue);
    expect(tester.widget<ListView>(find.byType(ListView).first).physics, isA<NeverScrollableScrollPhysics>());

    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(tester.widget<ListView>(find.byType(ListView).first).physics, isNot(isA<NeverScrollableScrollPhysics>()));
  });

  testWidgets('the zoom hint shows the first time only', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    await tester.pump();
    double hint() => tester
        .widget<AnimatedOpacity>(find.ancestor(of: find.text('Pinch or double-tap to zoom'), matching: find.byType(AnimatedOpacity)))
        .opacity;
    expect(hint(), 1);
    expect((await SharedPreferences.getInstance()).getBool('zoom_hint_seen'), isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(hint(), 0);

    await _pump(tester);
    await tester.pump();
    expect(hint(), 0, reason: 'seen once on this phone');
  });
}
