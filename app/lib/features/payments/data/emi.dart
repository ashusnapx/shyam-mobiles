import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase.dart';

/// One bank and tenure from the `emi-plans` Edge Function: Razorpay's EMI plans for the shop's account, which the
/// server reads once a day. [rate] is the bank's yearly interest in percent; [noCost] means the shop pays it.
class EmiPlan {
  const EmiPlan({
    required this.bank,
    required this.name,
    required this.months,
    required this.rate,
    required this.minPaise,
    this.noCost = false,
  });

  final String bank; // Razorpay's code, e.g. HDFC
  final String name;
  final int months;
  final double rate;
  final int minPaise;
  final bool noCost;

  factory EmiPlan.fromJson(Map<String, dynamic> j) => EmiPlan(
        bank: j['bank'],
        name: j['name'],
        months: j['months'],
        rate: (j['rate'] as num).toDouble(),
        minPaise: j['min_paise'],
        noCost: j['no_cost'] == true,
      );

  /// The monthly instalment on [pricePaise], to the nearest rupee: the price split evenly when it's no-cost, else the
  /// bank's reducing-balance EMI, P·r·(1+r)ⁿ / ((1+r)ⁿ − 1) with r the monthly rate.
  int monthlyPaise(int pricePaise) {
    final r = noCost ? 0 : rate / 1200;
    final exact = r == 0 ? pricePaise / months : pricePaise * r * math.pow(1 + r, months) / (math.pow(1 + r, months) - 1);
    return (exact / 100).round() * 100;
  }
}

/// What the product page says about EMI on [pricePaise]: the cheapest monthly instalment over the plans whose minimum
/// it meets, its tenure, whether any of them is no-cost, and those plans (by bank, then months). Null when none.
({int monthlyPaise, int months, bool noCost, List<EmiPlan> plans})? emiOffer(List<EmiPlan> plans, int pricePaise) {
  final fits = [for (final p in plans) if (p.minPaise <= pricePaise && p.months > 0) p];
  if (fits.isEmpty || pricePaise <= 0) return null;
  final cheapest = fits.reduce((a, b) => b.monthlyPaise(pricePaise) < a.monthlyPaise(pricePaise) ? b : a);
  return (
    monthlyPaise: cheapest.monthlyPaise(pricePaise),
    months: cheapest.months,
    noCost: fits.any((p) => p.noCost),
    plans: fits,
  );
}

/// The shop's EMI plans, fetched once per app run when they load (a failure is retried on the next product page).
final emiPlansProvider = FutureProvider.autoDispose<List<EmiPlan>>((ref) async {
  final res = await ref.watch(supabaseProvider).functions.invoke('emi-plans', body: const <String, dynamic>{});
  final plans = [for (final p in (res.data as Map)['plans'] as List) EmiPlan.fromJson(Map<String, dynamic>.from(p))];
  ref.keepAlive();
  return plans;
});
