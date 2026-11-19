import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/widgets.dart';
import '../data/social_repository.dart';

/// "From our Instagram": the shop's latest posts in a row; a tap opens the post in Instagram, or the browser.
/// Nothing at all while loading, empty or failing.
class InstagramRow extends ConsumerWidget {
  const InstagramRow({super.key});

  static const _size = 120.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(instagramPostsProvider).value ?? const <InstagramPost>[];
    if (posts.isEmpty) return const SizedBox.shrink();
    final px = (_size * MediaQuery.devicePixelRatioOf(context)).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('From our Instagram', gutter: Space.gutter),
        SizedBox(
          height: _size,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            itemCount: posts.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
            itemBuilder: (context, i) {
              final p = posts[i];
              return Semantics(
                button: true,
                label: 'Instagram post${p.caption.isEmpty ? ' ${i + 1}' : ': ${p.caption}'}',
                excludeSemantics: true,
                child: Pressable(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.lg),
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: () => openUri(context, Uri.parse(p.permalink)),
                        child: SizedBox.square(
                          dimension: _size,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(
                                imageUrl: p.thumbUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: px,
                                errorWidget: (_, _, _) => ColoredBox(color: Theme.of(context).colorScheme.surfaceContainer),
                              ),
                              if (p.mediaType == 'VIDEO')
                                const Positioned(
                                  top: Space.xs,
                                  right: Space.xs,
                                  child: Icon(PhosphorIconsFill.play, size: IconSizes.sm, color: Colors.white, shadows: [Shadow(blurRadius: 4)]),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
