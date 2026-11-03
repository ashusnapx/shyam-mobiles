import 'dart:math' as math;

import '../../../core/models/models.dart';

/// What [o] takes off one unit at [pricePaise], as `private.evaluate_promotion` works it out for a one-line cart:
/// percent ⌊p × v / 100⌋ capped at the offer's maximum, flat min(v, p), never more than p − ₹1. Null when it can't
/// apply on its own (below the offer's minimum, or free delivery, which saves nothing on the price).
/// shortcut: a preview only; checkout's quote is the real number (it also knows the cart, limits and first orders).
int? offerSavingOn(Offer o, int pricePaise) {
  if (pricePaise < o.minSubtotalPaise) return null;
  final raw = switch (o.kind) {
    OfferKind.percent => math.min(pricePaise * o.value ~/ 100, o.maxDiscountPaise ?? pricePaise),
    OfferKind.flat => math.min(o.value, pricePaise),
    OfferKind.freeDelivery => 0,
  };
  final saving = math.min(raw, pricePaise - 100);
  return saving > 0 ? saving : null;
}

/// The offer that saves the most on one unit at [pricePaise], with that saving; null when none takes money off.
({Offer offer, int saving})? bestOffer(List<Offer> offers, int pricePaise) {
  ({Offer offer, int saving})? best;
  for (final o in offers) {
    final s = offerSavingOn(o, pricePaise);
    if (s != null && (best == null || s > best.saving)) best = (offer: o, saving: s);
  }
  return best;
}
