import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/paging.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../cart/widgets/cart_button.dart';
import '../../catalog/widgets/product_tile.dart';
import '../data/wishlist.dart';

class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // hearts update the id set at once; the card list catches up after its refetch
    final ids = ref.watch(wishlistProvider).value ?? const <String>{};
    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist'), actions: const [CartButton()]),
      body: AsyncBody(
        value: ref.watch(wishlistCardsProvider),
        onRetry: () => ref.invalidate(wishlistProvider),
        loading: Skeletonizer(
          child: CustomScrollView(
            physics: const NeverScrollableScrollPhysics(),
            slivers: [
              const SliverPadding(padding: EdgeInsets.only(top: Space.sm)),
              SliverProductGrid(fakeCards(4)),
            ],
          ),
        ),
        data: (page) {
          final saved = page.items.where((c) => ids.contains(c.id)).toList();
          final dropped = ref.read(wishlistCardsProvider.notifier).dropped;
          if (saved.isEmpty && dropped > 0) {
            return EmptyState(
              icon: PhosphorIconsRegular.heartBreak,
              title: 'Your saved items are no longer sold',
              message: 'The shop stopped selling what you saved. Have a look at what’s in stock.',
              action: FilledButton(
                onPressed: () => context.go('/search?category=smartphones'),
                child: const Text('Browse phones'),
              ),
            );
          }
          if (saved.isEmpty) {
            return EmptyState(
              icon: PhosphorIconsRegular.heart,
              title: 'Nothing saved yet',
              message: 'Tap the heart on any phone to keep it here.',
              action: FilledButton(
                onPressed: () => context.go('/search?category=smartphones'),
                child: const Text('Browse phones'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(wishlistProvider);
              try {
                await ref.read(wishlistCardsProvider.future);
              } catch (_) {} // the error view shows it
            },
            child: LoadMoreListener(
              hasMore: page.hasMore,
              onMore: ref.read(wishlistCardsProvider.notifier).loadMore,
              child: CustomScrollView(
                slivers: [
                  const SliverPadding(key: ValueKey('top'), padding: EdgeInsets.only(top: Space.sm)),
                  if (dropped > 0)
                    SliverToBoxAdapter(
                      key: const ValueKey('dropped'),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
                        child: Text(
                          'Some saved items are no longer sold, so they’re not shown.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  SliverProductGrid(saved, key: const ValueKey('grid')),
                  if (page.hasMore)
                    SliverToBoxAdapter(
                      key: const ValueKey('more'),
                      child: PagedFooter(
                        failed: page.moreFailed,
                        onRetry: () => ref.read(wishlistCardsProvider.notifier).loadMore(retry: true),
                        what: 'more saved items',
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
