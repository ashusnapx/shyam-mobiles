// The Home hero card: one tone, one image, little text, one action. Fits 360 dp at large text, no glass panel,
// a countdown replaces the kicker, a screen reader gets one label, and white text passes AA on every tone.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/theme/generative.dart' show contrast;
import 'package:shyam_mobiles/core/widgets/widgets.dart' show GlassSurface, ProductImage, markNoCutout;
import 'package:shyam_mobiles/features/catalog/data/hero.dart' show HeroItem;
import 'package:shyam_mobiles/features/offers/widgets/hero_card.dart';

import '../repairs/layout_harness.dart';

PromoBanner _banner({DateTime? ends, String title = 'Festive phone sale'}) => PromoBanner(
    id: 'b1', title: title, subtitle: 'Up to ₹2,000 off on every phone in the shop this week, while stock lasts',
    link: '/offers', startsAt: DateTime(2026), endsAt: ends, tone: 3);

void main() {
  _heroLayoutTests();
  testWidgets('fits 360 dp at large text: 196 dp tall, no overflow, no glass panel', (tester) async {
    final long = _banner(ends: DateTime.now().add(const Duration(days: 10, hours: 7, minutes: 30)), title: 'Festive mega phone exchange sale for everyone');
    await pumpScreen(tester, Scaffold(body: ListView(children: [PromoBannerCard(long)])));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(HeroCard)).height, 196);
    expect(find.byType(GlassSurface), findsNothing);
  });

  testWidgets('a product slide keeps its price line to one line and fits too', (tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: ListView(children: [
          HeroCard(
            tone: heroTone(0),
            title: 'Samsung Galaxy S25 Ultra Titanium Edition 1 TB',
            cta: 'Buy now',
            price: (price: '₹1,24,999', mrp: '₹1,39,999', save: 'Save ₹15,000'),
            visual: const HeroVisual(items: [(path: null, opacity: 1.0)]),
            onTap: () {},
            semanticsLabel: 'x',
          ),
        ]),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(HeroCard)).height, 196);
    expect(find.text('Save ₹15,000'), findsOneWidget);
  });

  testWidgets('countdown replaces the kicker, in capitals, with a timer', (tester) async {
    await pumpScreen(tester, Scaffold(body: PromoBannerCard(_banner(ends: DateTime.now().add(const Duration(days: 10, hours: 7, minutes: 30))))));
    expect(find.text('ENDS IN 10D 7H'), findsOneWidget);
    expect(find.text('OFFER'), findsNothing);
    await pumpScreen(tester, Scaffold(body: PromoBannerCard(_banner())));
    expect(find.text('OFFER'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stop the countdown timer
  });

  testWidgets('one semantics label per slide, ending in its action', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(tester, Scaffold(body: PromoBannerCard(_banner(title: 'Festive phone sale', ends: DateTime.now().add(const Duration(days: 10, hours: 7))))));
    expect(find.bySemanticsLabel('Offer: Festive phone sale, ends in 10 days, Shop now'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });

  test('white text passes AA on every tone: the kicker pill, the light behind the product, the 70% MRP', () {
    const white = Colors.white;
    for (final tone in heroTones) {
      final lit = Color.alphaBlend(white.withValues(alpha: 0.12), tone);
      final pill = Color.alphaBlend(white.withValues(alpha: 0.18), lit);
      expect(contrast(white, tone), greaterThanOrEqualTo(4.5), reason: '$tone');
      expect(contrast(white, pill), greaterThanOrEqualTo(4.5), reason: 'pill on $tone');
      expect(contrast(Color.alphaBlend(white.withValues(alpha: 0.7), lit), lit), greaterThanOrEqualTo(4.5), reason: 'MRP on $tone');
    }
  });
}

// The visual lives in its own column: it never reaches the title, the value line or the CTA, at 360 dp and 1.3x text.
void _heroLayoutTests() {
  const cut = [(path: 'a/1.jpg', opacity: 1.0), (path: 'b/2.jpg', opacity: 1.0), (path: 'c/3.jpg', opacity: 1.0)];
  Future<void> check(WidgetTester tester, List<HeroItem> items) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScreen(
      tester,
      Scaffold(
        body: ListView(children: [
          HeroCard(
            tone: heroTone(0),
            title: 'Exchange your old phone',
            cta: 'Get estimate',
            valueLine: 'Trade in for a better one',
            visual: HeroVisual(items: items),
            onTap: () {},
            semanticsLabel: 'x',
          ),
        ]),
      ),
    );
    for (var pass = 0; pass < 2; pass++) { // before and after the cut-out loads fail
      final visual = tester.getRect(find.byType(HeroVisual));
      for (final f in [find.text('Exchange your old phone'), find.text('Trade in for a better one'), find.text('Get estimate')]) {
        expect(tester.getRect(f).right, lessThanOrEqualTo(visual.left), reason: 'text overlaps the visual');
      }
      expect(tester.getSize(find.byType(HeroCard)).height, 196);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('product slide: the visual stays out of the text column', (tester) async {
    await check(tester, [cut.first]);
  });

  testWidgets('fan slide: the visual stays out of the text column', (tester) async {
    await check(tester, cut);
  });

  testWidgets('fallback slide: contained 104 dp tile, no tilt, never over the text', (tester) async {
    markNoCutout('a/1.jpg');
    markNoCutout('b/2.jpg');
    await check(tester, cut.take(2).toList());
    final tile = tester.getRect(find.byType(ProductImage));
    expect(tile.width, lessThanOrEqualTo(104));
    expect(tester.getRect(find.byType(HeroVisual)).contains(tile.center), isTrue);
    expect(find.descendant(of: find.byType(HeroVisual), matching: find.byType(Transform)).evaluate().where((e) => (e.widget as Transform).transform.storage[1] != 0), isEmpty);
  });
}
