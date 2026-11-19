// The Home hero card: one tone, one image, little text, one action. Fits 360 dp at large text, no glass panel,
// a countdown replaces the kicker, a screen reader gets one label, and white text passes AA on every tone.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/theme/generative.dart' show contrast;
import 'package:shyam_mobiles/core/widgets/widgets.dart' show GlassSurface;
import 'package:shyam_mobiles/features/offers/widgets/hero_card.dart';

import '../repairs/layout_harness.dart';

PromoBanner _banner({DateTime? ends, String title = 'Festive phone sale'}) => PromoBanner(
    id: 'b1', title: title, subtitle: 'Up to ₹2,000 off on every phone in the shop this week, while stock lasts',
    link: '/offers', startsAt: DateTime(2026), endsAt: ends, tone: 3);

void main() {
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
