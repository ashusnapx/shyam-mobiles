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
  final VoidCallback? onSeeAll; // the header's "See all"
  final String? band; // a [SectionBand] seed: 'deals', 'phones', 'fits'…

  @override
  Widget build(BuildContext context) {
    if (value.hasError || (value.hasValue && value.value!.isEmpty)) return const SizedBox.shrink();
    final palette = band == null ? null : softPalette(band!);
    final rail = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RailHeader(title, onSeeAll: onSeeAll, accent: palette?.accent),
        AsyncBody<List<ProductCard>>(
          value: value,
          loading: Skeletonizer(child: _Row(fakeCards(3))),
          data: (cards) => _Row(cards).enter(context),
        ),
      ],
    );
    return band == null ? rail : SectionBand(seed: band!, child: rail);
  }
}

/// A section on its own soft band, its colours made by maths from [seed] ([softPalette]): full width and still (a big
/// band never drifts). The section's title pill takes the palette's accent.
class SectionBand extends StatelessWidget {
  const SectionBand({super.key, required this.seed, required this.child});

  final String seed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.md), // a white gap between bands
    child: AuroraBackground(
      palette: softPalette(seed),
      seed: seed,
      still: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: child,
      ),
    ),
  );
}

/// A compact section title in the brand face, with an [accent] pill before it on a band and an optional "See all".
class RailHeader extends StatelessWidget {
  const RailHeader(this.title, {super.key, this.onSeeAll, this.accent});

  final String title;
  final VoidCallback? onSeeAll;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.lg, Space.md, Space.xs, onSeeAll == null ? Space.sm : 0),
      child: Row(
        children: [
          if (accent != null) ...[
            DecoratedBox(
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
              child: const SizedBox(width: 4, height: 16),
            ),
            const SizedBox(width: Space.sm),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: t.displaySmall?.copyWith(fontSize: t.titleLarge?.fontSize, letterSpacing: -0.3, height: 1.2),
              ),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 40),
                padding: const EdgeInsets.symmetric(horizontal: Space.md),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('See all'),
            ),
        ],
      ),
    );
  }
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

/// Home's "Recently viewed"; nothing until a product has been opened on this phone.
class RecentlyViewedRail extends ConsumerWidget {
  const RecentlyViewedRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(recentlyViewedProvider).value?.isEmpty ?? true) return const SizedBox.shrink();
    return ProductRail(title: 'Recently viewed', band: 'recent', value: ref.watch(recentCardsProvider));
  }
}

/// The product page's rails: "Fits this phone" (phones only) and "Similar".
class ProductRails extends ConsumerWidget {
  const ProductRails({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(bottom: Space.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (product.category.kind == CategoryKind.phone)
          ProductRail(title: 'Fits this phone', band: 'fits', value: ref.watch(fitsProvider(product.slug))),
        ProductRail(title: 'Similar products', band: 'similar', value: ref.watch(similarProvider(product.slug))),
      ],
    ),
  );
}
