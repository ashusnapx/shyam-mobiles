import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart' show currentUserIdProvider;
import 'offers.dart';

// Campaign calendar: an offer staff mark "Apply it for customers" fills its code into the cart and checkout while it
// runs, when no code is typed. The server still checks the code and the one-offer rule still picks the better deal.

/// What [o] would take off [subtotalPaise] (null: the cart isn't known yet, so just its size).
int _estimate(Offer o, int? subtotalPaise) => switch (o.kind) {
      OfferKind.percent when subtotalPaise != null => [subtotalPaise * o.value ~/ 100, ?o.maxDiscountPaise].reduce((a, b) => a < b ? a : b),
      OfferKind.percent => o.value * 100,
      OfferKind.flat => o.value,
      _ => 0, // free delivery, packs: no code saving to compare (a wildcard: compiles before and after the pack kind)
    };

/// The running auto-apply offer worth the most on this cart (ties: the one ending first), or null. Offers the cart is
/// too small for, and codes in [skip] (already tried or removed this session), are left out.
Offer? bestAutoApply(Iterable<Offer> offers, DateTime now, {int? subtotalPaise, Set<String> skip = const {}}) {
  Offer? best;
  for (final o in offers) {
    final code = o.code;
    if (!o.autoApply || code == null || skip.contains(code) || o.startsAt.isAfter(now)) continue;
    if (o.endsAt != null && !o.endsAt!.isAfter(now)) continue;
    if (subtotalPaise != null && subtotalPaise < o.minSubtotalPaise) continue;
    if (best == null) {
      best = o;
      continue;
    }
    final (a, b) = (_estimate(o, subtotalPaise), _estimate(best, subtotalPaise));
    final endsSooner = (o.endsAt ?? DateTime(9999)).isBefore(best.endsAt ?? DateTime(9999));
    if (a > b || (a == b && endsSooner)) best = o;
  }
  return best;
}

/// "Men’s Day sale" → "Men’s Day": the occasion an auto-apply offer is named for.
String occasionOf(String title) => title.replaceFirst(RegExp(r'\s+sale$', caseSensitive: false), '');

/// A code worth showing a customer: letters, then 1-3 digits (WEDDING5, MENSDAY5). Anything else looks random.
bool readableCode(String? code) => code != null && RegExp(r'^[A-Za-z]{3,10}\d{1,3}$').hasMatch(code);

/// The offer whose code the app filled in this session (null: none, or the customer typed their own).
final autoCouponProvider = NotifierProvider<AutoCoupon, Offer?>(AutoCoupon.new);

class AutoCoupon extends Notifier<Offer?> {
  final _tried = <String>{}; // each code once a session: one the customer removed, or the server refused, stays out

  @override
  Offer? build() {
    ref.watch(currentUserIdProvider);
    _tried.clear();
    return null;
  }

  /// Fills the best running auto-apply code when no code is set. Safe to call from build: the write waits a tick.
  void fill(List<Offer> offers, DateTime now, {int? subtotalPaise}) {
    if (ref.read(couponCodeProvider) != null) return;
    final best = bestAutoApply(offers, now, subtotalPaise: subtotalPaise, skip: _tried);
    if (best == null) return;
    _tried.add(best.code!);
    scheduleMicrotask(() {
      if (ref.read(couponCodeProvider) != null) return;
      state = best;
      ref.read(couponCodeProvider.notifier).set(best.code);
    });
  }

  /// The server refused the filled code (too small a cart, used up, a better sale): take it back out, quietly.
  void refused(String code) {
    if (state?.code != code) return;
    scheduleMicrotask(() {
      state = null;
      if (ref.read(couponCodeProvider) == code) ref.read(couponCodeProvider.notifier).set(null);
    });
  }
}
