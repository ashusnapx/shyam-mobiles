import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/rails.dart';
import 'product_tile.dart';

const _tileWidth = 148.0;

/// A titled, sideways-scrolling row of product tiles. Hidden when there's nothing to show or it failed (a rail
/// is a nice-to-have: no error screen for it).
class ProductRail extends StatelessWidget {
  const ProductRail({super.key, required this.title, required this.value});

  final String title;
  final AsyncValue<List<ProductCard>> value;

  @override
  Widget build(BuildContext context) {
    if (value.hasError || (value.hasValue && value.value!.isEmpty)) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title),
        AsyncBody<List<ProductCard>>(
          value: value,
          loading: Skeletonizer(child: _Row(fakeCards(3))),
          data: (cards) => _Row(cards).enter(context),
        ),
      ],
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
