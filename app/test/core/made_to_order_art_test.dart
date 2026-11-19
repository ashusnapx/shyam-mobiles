import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shyam_mobiles/core/widgets/made_to_order_art.dart';
import 'package:shyam_mobiles/core/widgets/widgets.dart';

Future<void> _pump(WidgetTester t, Widget w) =>
    t.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 80, child: w))))));

void main() {
  test('icon by type: cover/case phone, glass and lens guard shield, flip cover book', () {
    expect(madeToOrderIcon('Back Cover (any phone)'), PhosphorIconsRegular.deviceMobile);
    expect(madeToOrderIcon('Silicone Case (any phone)'), PhosphorIconsRegular.deviceMobile);
    expect(madeToOrderIcon('Tempered Glass (any phone)'), PhosphorIconsRegular.shieldCheck);
    expect(madeToOrderIcon('Camera Lens Guard (any phone)'), PhosphorIconsRegular.shieldCheck);
    expect(madeToOrderIcon('Flip Cover (any phone)'), PhosphorIconsRegular.bookOpen);
  });

  testWidgets('a photo-less made-to-order product shows the tinted icon, not an image', (t) async {
    await _pump(t, const ProductArt(null, name: 'Flip Cover (any phone)', madeToOrder: true));
    expect(find.byIcon(PhosphorIconsRegular.bookOpen), findsOneWidget);
    expect(find.byType(ProductImage), findsNothing);
  });

  testWidgets('a normal product with no photo keeps the usual placeholder', (t) async {
    await _pump(t, const ProductArt(null, name: 'Galaxy', madeToOrder: false));
    expect(find.byType(ProductImage), findsOneWidget);
    expect(find.byType(MadeToOrderArt), findsNothing);
  });
}
