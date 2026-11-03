import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shyam_mobiles/core/theme/generative.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/core/widgets/blocks.dart';
import 'package:shyam_mobiles/core/widgets/widgets.dart';

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
      theme: ThemeData(colorScheme: lightScheme),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: child),
      ),
    );

void main() {
  test('every tone, world, category and section colour passes AA on its background', () {
    final pairs = <String, Tint>{
      for (final t in TagTone.values) 'tone ${t.name}': toneColors(t),
      'shop': Worlds.shop,
      'search': Worlds.search,
      'repairs': Worlds.repairs,
      'cart': Worlds.cart,
      'account': Worlds.account,
      'admin': Worlds.admin,
      'offers': Worlds.offers,
      for (final e in categoryTints.entries) e.key: e.value,
      'deals band': sectionTints.deals,
      'similar band': sectionTints.similar,
    };
    for (final MapEntry(:key, value: (bg, fg)) in pairs.entries) {
      expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: key);
    }
  });

  test('red is only the bad tone; closed states are grey', () {
    for (final t in TagTone.values.where((t) => t != TagTone.bad)) {
      expect(toneColors(t).$1, isNot(lightScheme.errorContainer), reason: t.name);
    }
    expect(toneColors(TagTone.neutral), (lightScheme.surfaceContainerHigh, BrandColors.graphite));
  });

  test('a new category slug gets a stable colour from the fixed table', () {
    expect(categoryTint('smartphones'), (BrandColors.indigoMist, BrandColors.indigo));
    expect(categoryTint('smart-watches'), categoryTint('smart-watches'));
    expect(categoryTints.values, contains(categoryTint('smart-watches')));
  });

  testWidgets('stacked PriceTag is the same height with or without a discount', (tester) async {
    Future<double> height(int? mrp) async {
      await tester.pumpWidget(_app(
        Center(child: SizedBox(width: 120, child: PriceTag(pricePaise: 6999900, mrpPaise: mrp, stacked: true))),
        scale: 1.3,
      ));
      return tester.getSize(find.byType(PriceTag)).height;
    }

    final discounted = await height(12999900);
    expect(find.text('46% off'), findsOneWidget);
    expect(find.bySemanticsLabel('MRP ₹1,29,999'), findsOneWidget);
    expect(await height(null), discounted);
    expect(await height(6999900), discounted, reason: 'MRP equal to price: no saving line, same height');
    expect(tester.takeException(), isNull);
  });

  testWidgets('product-page PriceTag says how much you save', (tester) async {
    await tester.pumpWidget(_app(const PriceTag(pricePaise: 6999900, mrpPaise: 7299900, showSaving: true)));
    expect(find.text('You save ₹3,000 (4%)'), findsOneWidget);
    expect(find.text('4% off'), findsNothing);
    await tester.pumpWidget(_app(const PriceTag(pricePaise: 6999900, mrpPaise: 6999900, showSaving: true)));
    expect(find.textContaining('You save'), findsNothing);
  });

  testWidgets('SectionHeader: a header, and a 48 dp "See all" when it links somewhere', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(SectionHeader('Featured phones', accent: BrandColors.indigo, onSeeAll: () => taps++)));
    expect(find.bySemanticsLabel('Featured phones'), findsOneWidget);
    final link = find.widgetWithText(TextButton, 'See all');
    expect(tester.getSize(link).height, greaterThanOrEqualTo(48));
    await tester.tap(link);
    expect(taps, 1);
    await tester.pumpWidget(_app(const SectionHeader('Items')));
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('EmptyState paints its circles in the given world', (tester) async {
    await tester.pumpWidget(_app(const EmptyState(
      icon: PhosphorIconsRegular.shoppingBag,
      title: 'Your cart is empty',
      tone: Worlds.cart,
    )));
    final icon = tester.widget<Icon>(find.byIcon(PhosphorIconsRegular.shoppingBag));
    expect(icon.color, BrandColors.emerald);
  });
}
