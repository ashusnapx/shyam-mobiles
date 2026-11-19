// Auto-apply (Campaign calendar): the best running auto-apply code fills itself in at cart and checkout when none is
// typed, shows as "MEN5 applied · Men’s Day 5% off", goes back out quietly when the server refuses it, and Home says so.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/offers/data/auto_apply.dart';
import 'package:shyam_mobiles/features/offers/data/offers.dart';
import 'package:shyam_mobiles/features/offers/widgets/occasion_chip.dart';
import 'package:shyam_mobiles/features/offers/widgets/offer_widgets.dart';

import '../repairs/layout_harness.dart';

Offer _offer(String code, {int value = 5, int min = 0, bool auto = true, DateTime? ends, OfferKind kind = OfferKind.percent}) => Offer(
    id: code, title: code == 'MEN5' ? 'Men’s Day sale' : 'Big $code', code: code, kind: kind, value: value,
    minSubtotalPaise: min, startsAt: DateTime(2026, 11, 18), endsAt: ends ?? DateTime(2026, 11, 20), autoApply: auto);

class _Typed extends CouponCode {
  @override
  String? build() => 'MINE10';
}

void main() {
  final now = DateTime(2026, 11, 19, 10);

  test('the best running auto-apply offer for this cart', () {
    final men = _offer('MEN5');
    final flat = _offer('FLAT200', kind: OfferKind.flat, value: 20000);
    expect(bestAutoApply([men, flat], now, subtotalPaise: 200000)?.code, 'FLAT200'); // ₹200 beats 5% of ₹2,000
    expect(bestAutoApply([men, flat], now, subtotalPaise: 1000000)?.code, 'MEN5'); // 5% of ₹10,000 = ₹500
    expect(bestAutoApply([_offer('BIG', min: 500000), men], now, subtotalPaise: 100000)?.code, 'MEN5');
    expect(bestAutoApply([_offer('X', auto: false)], now), isNull);
    expect(bestAutoApply([_offer('OLD', ends: DateTime(2026, 11, 19, 9))], now), isNull);
    expect(bestAutoApply([men], now, skip: {'MEN5'}), isNull);
    expect(occasionOf('Men’s Day sale'), 'Men’s Day');
    expect(occasionOf('Weekend deal'), 'Weekend deal');
  });

  Future<ProviderContainer> pump(WidgetTester tester, Widget w) async {
    await pumpScreen(tester, Scaffold(body: Column(children: [w])), overrides: [
      availableOffersProvider.overrideWith((ref) async => [_offer('MEN5', ends: DateTime(2099))]),
    ]);
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(Column).first));
  }

  testWidgets('cart: no code typed, the auto code fills in and says why', (tester) async {
    final c = await pump(tester, const CouponRow(quote: Quote(subtotalPaise: 1000000, deliveryFeePaise: 0, discountPaise: 0, totalPaise: 1000000)));
    expect(c.read(couponCodeProvider), 'MEN5');
    await pumpScreen(tester, const Scaffold(body: Column(children: [CouponRow(quote: Quote(subtotalPaise: 1000000, deliveryFeePaise: 0,
        discountPaise: 50000, totalPaise: 950000, promotion: (id: 'MEN5', title: 'Men’s Day sale', code: 'MEN5', kind: OfferKind.percent)))])),
        overrides: [availableOffersProvider.overrideWith((ref) async => [_offer('MEN5', ends: DateTime(2099))])]);
    await tester.pumpAndSettle();
    expect(find.text('MEN5 applied · Men’s Day 5% off'), findsOneWidget);
  });

  testWidgets('a refused auto code goes back out quietly, and isn’t filled again', (tester) async {
    final c = await pump(tester, const CouponRow(quote: Quote(subtotalPaise: 100, deliveryFeePaise: 0, discountPaise: 0, totalPaise: 100,
        couponError: 'COUPON_MIN_ORDER')));
    await tester.pumpAndSettle();
    expect(c.read(couponCodeProvider), isNull);
    expect(find.textContaining('can’t be used'), findsNothing);
  });

  testWidgets('a code the customer typed is never replaced', (tester) async {
    await pumpScreen(tester, const Scaffold(body: Column(children: [CouponRow(quote: null)])), overrides: [
      availableOffersProvider.overrideWith((ref) async => [_offer('MEN5', ends: DateTime(2099))]),
      couponCodeProvider.overrideWith(_Typed.new),
    ]);
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(Column).first));
    expect(c.read(couponCodeProvider), 'MINE10');
  });

  testWidgets('home chip: one 44 dp line, the occasion, the deal, readable code, applied at checkout', (tester) async {
    await pump(tester, OccasionChip(now: now));
    expect(find.text('Men’s Day · 5% off with MEN5 applied at checkout'), findsOneWidget);
    expect(tester.getSize(find.byType(OccasionChip)).height, OccasionChip.height + 12); // 44 and the gap above it
  });

  testWidgets('home chip: a random-looking code is never shown', (tester) async {
    await pumpScreen(tester, Scaffold(body: Column(children: [OccasionChip(now: now)])), overrides: [
      availableOffersProvider.overrideWith((ref) async => [Offer(id: 'r', title: 'Festive sale', code: 'X7K2QZ9', kind: OfferKind.percent, value: 5, startsAt: DateTime(2026, 11, 18), endsAt: DateTime(2099), autoApply: true)]),
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('X7K2QZ9'), findsNothing);
    expect(find.text('Festive · 5% off applied at checkout'), findsOneWidget);
  });

  test('readable codes: letters then digits only', () {
    for (final ok in ['WEDDING5', 'MENSDAY5', 'DIWALI10', 'diwali10']) {
      expect(readableCode(ok), isTrue, reason: ok);
    }
    for (final bad in ['X7K2QZ9', 'A7K2', 'FLAT-200', '5OFF', 'WEDDING', 'AB5', '', null]) {
      expect(readableCode(bad), isFalse, reason: '$bad');
    }
  });
}
