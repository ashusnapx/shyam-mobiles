import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../wishlist/data/wishlist.dart';

/// "Samsung Galaxy S25" → "Galaxy S25". Names start with the brand (schema convention) and the brand shows above.
String shortName(String name, String brand) =>
    name.length > brand.length + 1 && name.toLowerCase().startsWith('${brand.toLowerCase()} ')
        ? name.substring(brand.length + 1)
        : name;

/// Placeholder cards for skeletons.
List<ProductCard> fakeCards(int n) => [
      for (var i = 0; i < n; i++)
        ProductCard(
          id: 'skeleton-$i',
          slug: '',
          name: 'Brand Phone name 5G',
          brandName: 'Brand',
          categorySlug: '',
          minPricePaise: 2499900,
          mrpPaise: 2799900,
          inStock: true,
        ),
    ];

class ProductTile extends StatelessWidget {
  const ProductTile(this.card, {super.key});

  final ProductCard card;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final nameStyle = t.bodyMedium!.copyWith(fontWeight: FontWeight.w600, height: 1.3);
    return InkWell(
      onTap: () => context.push('/product/${card.slug}'),
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              card.inStock ? ProductImage(card.coverPath) : Opacity(opacity: 0.45, child: ProductImage(card.coverPath)),
              if (!card.inStock)
                const Positioned(left: Space.sm, top: Space.sm, child: Tag('Out of stock', tone: TagTone.bad)),
              Positioned(top: 0, right: 0, child: HeartButton(card.id)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, Space.sm, 2, Space.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.brandName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(color: c.onSurfaceVariant, letterSpacing: 0.7),
                ),
                const SizedBox(height: 2),
                // always two lines tall so prices line up across a row
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(nameStyle.fontSize!) * nameStyle.height! * 2,
                  child: Text(shortName(card.name, card.brandName), maxLines: 2, overflow: TextOverflow.ellipsis, style: nameStyle),
                ),
                const SizedBox(height: Space.xs),
                PriceTag(pricePaise: card.minPricePaise, mrpPaise: card.mrpPaise),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-column grid built as rows, so tiles take their natural height at any text scale.
class SliverProductGrid extends StatelessWidget {
  const SliverProductGrid(this.cards, {super.key});

  final List<ProductCard> cards;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        sliver: SliverList.builder(
          itemCount: (cards.length + 1) ~/ 2,
          itemBuilder: (_, i) => Padding(
            key: ValueKey(cards[i * 2].id),
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: ProductTile(cards[i * 2])),
                const SizedBox(width: Space.md),
                Expanded(child: i * 2 + 1 < cards.length ? ProductTile(cards[i * 2 + 1]) : const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      );
}

class HeartButton extends ConsumerWidget {
  const HeartButton(this.productId, {super.key});

  final String productId;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    if (ref.read(currentUserIdProvider) == null) {
      context.push('/sign-in?from=${Uri.encodeComponent(GoRouterState.of(context).uri.toString())}');
      return;
    }
    HapticFeedback.selectionClick();
    try {
      await ref.read(wishlistProvider.notifier).toggle(productId);
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    final saved = ref.watch(wishlistProvider.select((s) => s.value?.contains(productId) ?? false));
    return IconButton(
      tooltip: saved ? 'Remove from wishlist' : 'Save to wishlist',
      onPressed: () => _toggle(context, ref),
      icon: DecoratedBox(
        decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
        child: Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: Icon(
            saved ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
            size: 18,
            color: saved ? c.error : c.onSurface,
          ),
        ),
      ),
    );
  }
}
