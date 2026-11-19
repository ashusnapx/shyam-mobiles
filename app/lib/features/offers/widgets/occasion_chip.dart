import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/tokens.dart';
import '../data/auto_apply.dart';
import '../data/offers.dart';
import 'offer_widgets.dart' show offerHeadline;

/// Home's "Wedding season · 5% off applied at checkout" while an auto-apply offer runs (Campaign calendar): one line,
/// with the code only when it is readable ([readableCode]). It fills the code too, so "applied" is true; the cart
/// still shows the server's verdict.
class OccasionChip extends ConsumerWidget {
  const OccasionChip({super.key, this.now});

  static const height = 44.0;

  final DateTime? now; // tests pin the clock

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(availableOffersProvider).value;
    final at = now ?? DateTime.now();
    final best = offers == null ? null : bestAutoApply(offers, at);
    if (best == null) return const SizedBox.shrink();
    ref.read(autoCouponProvider.notifier).fill(offers!, at);
    final applied = ref.watch(couponCodeProvider) == best.code;
    final text = '${occasionOf(best.title)} · ${offerHeadline(best)}${readableCode(best.code) ? ' with ${best.code}' : ''}'
        '${applied ? ' applied' : ''} at checkout';
    const bg = BrandColors.mint, fg = BrandColors.mintInk;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.chip),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.chip),
          onTap: () => context.push('/offers/${best.id}'),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: Row(
                children: [
                  const Icon(PhosphorIconsFill.checkCircle, size: IconSizes.md, color: fg),
                  const SizedBox(width: Space.sm),
                  // one line: a long name shrinks to fit rather than wrapping
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(text, maxLines: 1, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                    ),
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
