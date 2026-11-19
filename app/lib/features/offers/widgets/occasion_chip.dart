import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/tokens.dart';
import '../data/auto_apply.dart';
import '../data/offers.dart';
import 'offer_widgets.dart' show offerHeadline;

/// Home's "Happy Men’s Day · 5% off with MEN5, already applied" while an auto-apply offer runs (Campaign calendar).
/// It fills the code too, so "already applied" is true; the cart still shows the server's verdict.
class OccasionChip extends ConsumerWidget {
  const OccasionChip({super.key, this.now});

  final DateTime? now; // tests pin the clock

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(availableOffersProvider).value;
    final at = now ?? DateTime.now();
    final best = offers == null ? null : bestAutoApply(offers, at);
    if (best == null) return const SizedBox.shrink();
    ref.read(autoCouponProvider.notifier).fill(offers!, at);
    final applied = ref.watch(couponCodeProvider) == best.code;
    final occasion = occasionOf(best.title);
    final text = '${occasion == best.title ? best.title : 'Happy $occasion'} · ${offerHeadline(best)} with ${best.code}'
        '${applied ? ', already applied' : ''}';
    final (bg, fg) = Worlds.offers;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.chip),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.chip),
          onTap: () => context.push('/offers/${best.id}'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
              child: Row(
                children: [
                  Icon(PhosphorIconsFill.sealPercent, size: IconSizes.md, color: fg),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
