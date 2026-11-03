import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/catalog/data/best_offer.dart';

Offer offer(OfferKind kind, int value, {String id = 'o', int? max, int min = 0, String? code}) => Offer(
      id: id,
      title: id,
      kind: kind,
      value: value,
      code: code,
      maxDiscountPaise: max,
      minSubtotalPaise: min,
      startsAt: DateTime(2026),
    );

void main() {
  test('percent floors to the paisa and stops at the cap, like evaluate_promotion', () {
    expect(offerSavingOn(offer(OfferKind.percent, 10), 129999), 12999);
    expect(offerSavingOn(offer(OfferKind.percent, 10, max: 500000), 6999900), 500000);
  });

  test('flat takes its value, never the whole price: at least ₹1 is left to pay', () {
    expect(offerSavingOn(offer(OfferKind.flat, 20000), 129900), 20000);
    expect(offerSavingOn(offer(OfferKind.flat, 20000), 15000), 14900);
    expect(offerSavingOn(offer(OfferKind.flat, 20000), 100), isNull);
  });

  test('no saving below the minimum or for free delivery', () {
    expect(offerSavingOn(offer(OfferKind.percent, 10, min: 500000), 499999), isNull);
    expect(offerSavingOn(offer(OfferKind.percent, 10, min: 500000), 500000), 50000);
    expect(offerSavingOn(offer(OfferKind.freeDelivery, 0), 6999900), isNull);
  });

  test('the best offer is the one that saves the most on this price', () {
    final offers = [
      offer(OfferKind.freeDelivery, 0, id: 'ship'),
      offer(OfferKind.flat, 200000, id: 'flat'),
      offer(OfferKind.percent, 5, id: 'pct', max: 300000),
    ];
    expect(bestOffer(offers, 6999900)?.offer.id, 'pct'); // 5% is ₹3,499 → capped at ₹3,000, more than ₹2,000
    expect(bestOffer(offers, 6999900)?.saving, 300000);
    expect(bestOffer(offers, 1000000)?.offer.id, 'flat'); // 5% of ₹10,000 is only ₹500
    expect(bestOffer([offers.first], 6999900), isNull);
  });
}
