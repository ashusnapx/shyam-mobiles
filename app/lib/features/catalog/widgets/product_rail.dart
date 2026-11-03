import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/generative.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/rails.dart';
import 'product_tile.dart';

const _tileWidth = 132.0; // two and a half show at 360 dp (the peek says there's more), prices above the fold

/// A titled, sideways-scrolling row of product tiles, on its [band] when given. Hidden when there's nothing to show
/// or it failed (a rail is a nice-to-have: no error screen for it).
class ProductRail extends StatelessWidget {
  const ProductRail({super.key, required this.title, required this.value, this.onSeeAll, this.band});

  final String title;
  final AsyncValue<List<ProductCard>> value;
  final VoidCallback? onSeeAll; // the header's "See all": the full list of what the rail shows
  final Tint? band; // one of [sectionTints]

  @override
  Widget build(BuildContext context) {
    if (value.hasError || (value.hasValue && value.value!.isEmpty)) return const SizedBox.shrink();
    final rail = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title, onSeeAll: onSeeAll, accent: band?.$2),
        AsyncBody<List<ProductCard>>(
          value: value,
          loading: Skeletonizer(child: _Row(fakeCards(3))),
          data: (cards) => _Row(cards).enter(context),
        ),
      ],
    );
    return band == null ? rail : SectionBand(tint: band!, child: rail);
  }
}

/// A section on its own soft band of a fixed [tint] ([sectionTints]): full width and still (a big band never
/// drifts). The section's title pill takes the tint's accent.
class SectionBand extends StatelessWidget {
  const SectionBand({super.key, required this.tint, required this.child});

  final Tint tint;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.md), // a white gap between bands
    child: AuroraBackground(
      palette: tintPalette(tint),
      still: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: child,
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.cards);

  final List<ProductCard> cards;

  // a Row, not a ListView: tiles take their natural height at any text size (≤ 10 tiles, so building all is fine)
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.md,
      // white cards with a hairline, so they float on a band
      children: [
        for (final c in cards)
          SizedBox(
            width: _tileWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(Radii.lg),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Padding(padding: const EdgeInsets.all(6), child: ProductTile(c)),
            ),
          ),
      ],
    ),
  );
}

/// Home's "Recently viewed"; nothing until two products have been opened on this phone (one is just a visit).
class RecentlyViewedRail extends ConsumerWidget {
  const RecentlyViewedRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if ((ref.watch(recentlyViewedProvider).value?.length ?? 0) < 2) return const SizedBox.shrink();
    return ProductRail(title: 'Recently viewed', band: sectionTints.recent, value: ref.watch(recentCardsProvider));
  }
}
