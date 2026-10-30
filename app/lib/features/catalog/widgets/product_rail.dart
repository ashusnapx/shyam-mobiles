import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/rails.dart';
import 'product_tile.dart';

const _tileWidth = 132.0; // two and a half show at 360 dp (the peek says there's more), prices above the fold

/// A titled, sideways-scrolling row of product tiles. Hidden when there's nothing to show or it failed (a rail
/// is a nice-to-have: no error screen for it).
class ProductRail extends StatelessWidget {
  const ProductRail({super.key, required this.title, required this.value, this.onSeeAll});

  final String title;
  final AsyncValue<List<ProductCard>> value;
  final VoidCallback? onSeeAll; // the header's "See all"

  @override
  Widget build(BuildContext context) {
    if (value.hasError || (value.hasValue && value.value!.isEmpty)) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RailHeader(title, onSeeAll: onSeeAll),
        AsyncBody<List<ProductCard>>(
          value: value,
          loading: Skeletonizer(child: _Row(fakeCards(3))),
          data: (cards) => _Row(cards).enter(context),
        ),
      ],
    );
  }
}

/// A compact section title for rails and Home's sections, with an optional small "See all".
class RailHeader extends StatelessWidget {
  const RailHeader(this.title, {super.key, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(Space.lg, Space.md, Space.xs, onSeeAll == null ? Space.sm : 0),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
          children: [for (final c in cards) SizedBox(width: _tileWidth, child: ProductTile(c))],
        ),
      );
}

/// Home's "Recently viewed"; nothing until a product has been opened on this phone.
class RecentlyViewedRail extends ConsumerWidget {
  const RecentlyViewedRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(recentlyViewedProvider).value?.isEmpty ?? true) return const SizedBox.shrink();
    return ProductRail(title: 'Recently viewed', value: ref.watch(recentCardsProvider));
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
              ProductRail(title: 'Fits this phone', value: ref.watch(fitsProvider(product.slug))),
            ProductRail(title: 'Similar products', value: ref.watch(similarProvider(product.slug))),
          ],
        ),
      );
}
