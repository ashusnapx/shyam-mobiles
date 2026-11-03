import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/generative.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/rails.dart';
import 'product_tile.dart';

const _tileWidth = 132.0; // two and a peek show at 360 dp, in a panel too (the peek says there's more)

/// A titled, sideways-scrolling row of product cards, inside its [band] panel when given. Hidden (no header, no
/// space) when there's nothing to show or it failed: a rail is a nice-to-have, no error screen for it.
class ProductRail extends StatelessWidget {
  const ProductRail({super.key, required this.title, required this.value, this.onSeeAll, this.band});

  final String title;
  final AsyncValue<List<ProductCard>> value;
  final VoidCallback? onSeeAll; // the header's "See all": the full list of what the rail shows
  final Tint? band; // one of [sectionTints]; at most one tinted band per screen, [sectionTints.explore] is neutral

  @override
  Widget build(BuildContext context) {
    if (value.hasError || (value.hasValue && value.value!.isEmpty)) return const SizedBox.shrink();
    final side = band == null ? Space.gutter : Space.lg; // a panel already sits a gutter in
    final rail = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title, onSeeAll: onSeeAll, accent: band?.$2, gutter: side, top: band == null ? null : Space.lg),
        AsyncBody<List<ProductCard>>(
          value: value,
          loading: Skeletonizer(child: _Row(fakeCards(3), side: side)),
          data: (cards) => _Row(cards, side: side).enter(context),
        ),
      ],
    );
    return band == null ? rail : SectionBand(tint: band!, child: rail);
  }
}

/// A section on its own panel of a fixed [tint] ([sectionTints]): inset a gutter from the screen's edges, rounded,
/// and still (a big panel never drifts). The section's title bar takes the tint's accent.
class SectionBand extends StatelessWidget {
  const SectionBand({super.key, required this.tint, required this.child});

  final Tint tint;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(Radii.xl),
      child: AuroraBackground(
        palette: tintPalette(tint),
        still: true,
        child: Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: child),
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.cards, {required this.side});

  final List<ProductCard> cards;
  final double side;

  // a Row, not a ListView: tiles take their natural height at any text size (≤ 10 tiles, so building all is fine)
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    // room above and below for the cards' shadow
    padding: EdgeInsets.fromLTRB(side, Space.xs, side, Space.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.md,
      children: [for (final c in cards) SizedBox(width: _tileWidth, child: ProductTile(c))],
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
