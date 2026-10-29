import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../catalog/widgets/product_tile.dart';
import '../data/wishlist.dart';

class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // hearts update the id set at once; the card list catches up after its refetch
    final ids = ref.watch(wishlistProvider).value ?? const <String>{};
    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
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
        data: (cards) {
          final saved = cards.where((c) => ids.contains(c.id)).toList();
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
            child: CustomScrollView(
              slivers: [
                const SliverPadding(key: ValueKey('top'), padding: EdgeInsets.only(top: Space.sm)),
                SliverProductGrid(saved, key: const ValueKey('grid')),
              ],
            ),
          );
        },
      ),
    );
  }
}
