import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/emi.dart';

/// "EMI from ₹2,083/month · No-cost EMI available" under a price; tap for every bank and tenure. Takes no space while
/// the plans load, when they fail, when EMI isn't on for the shop, or when [pricePaise] is below every bank's minimum.
class EmiLine extends ConsumerWidget {
  const EmiLine({super.key, required this.pricePaise});

  final int pricePaise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(emiPlansProvider).value;
    final offer = plans == null ? null : emiOffer(plans, pricePaise);
    if (offer == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: () => showEmiPlans(context, offer.plans, pricePaise),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44), // a comfortable tap target for a one-line link
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.calendarDots, size: 18, color: c.secondary),
              const SizedBox(width: Space.sm),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: 'EMI from ${formatInr(offer.monthlyPaise)}/month',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (offer.noCost)
                      TextSpan(text: ' · No-cost EMI available', style: TextStyle(color: c.secondary, fontWeight: FontWeight.w700)),
                  ]),
                  style: t.bodyMedium,
                ),
              ),
              const SizedBox(width: Space.xs),
              Icon(PhosphorIconsRegular.caretRight, size: 14, color: c.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every bank and tenure for [pricePaise], cheapest month first within each bank.
Future<void> showEmiPlans(BuildContext context, List<EmiPlan> plans, int pricePaise) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _EmiSheet(plans: plans, pricePaise: pricePaise),
    );

class _EmiSheet extends StatelessWidget {
  const _EmiSheet({required this.plans, required this.pricePaise});

  final List<EmiPlan> plans;
  final int pricePaise;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final banks = <String, List<EmiPlan>>{};
    for (final p in plans) {
      (banks[p.name] ??= []).add(p);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl + MediaQuery.paddingOf(context).bottom),
        children: [
          Semantics(header: true, child: Text('EMI on ${formatInr(pricePaise)}', style: t.titleLarge)),
          const SizedBox(height: Space.xs),
          Text(
            'Pick EMI on the payment screen at checkout, with a credit card from one of these banks. Banks add GST on '
            'the interest. No-cost EMI: the interest comes off the price, so you pay ${formatInr(pricePaise)} in all.',
            style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
          for (final MapEntry(key: bank, value: list) in banks.entries) ...[
            const SizedBox(height: Space.lg),
            Text(bank, style: t.titleSmall),
            for (final p in list..sort((a, b) => a.months - b.months))
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Row(
                  children: [
                    Expanded(child: Text('${p.months} months', style: t.bodyMedium)),
                    Text(
                      '${formatInr(p.monthlyPaise(pricePaise))}/mo',
                      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    const SizedBox(width: Space.sm),
                    SizedBox(
                      width: 84,
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: p.noCost
                            ? const Tag('No-cost', tone: TagTone.ok)
                            : Text('${_rate(p.rate)}% a year', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _rate(double r) => r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
