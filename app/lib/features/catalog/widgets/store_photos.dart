import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';

/// Swipeable 16:9 shop photos with page dots; a tap opens them full screen. Never auto-advances.
class StorePhotoCarousel extends StatefulWidget {
  const StorePhotoCarousel(this.paths, {super.key});

  final List<String> paths; // product-images object keys

  @override
  State<StorePhotoCarousel> createState() => _StorePhotoCarouselState();
}

class _StorePhotoCarouselState extends State<StorePhotoCarousel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final n = widget.paths.length;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: n,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => Semantics(
              button: true,
              label: 'Photo of the shop, ${i + 1} of $n',
              child: GestureDetector(
                onTap: () => _openViewer(context, widget.paths, i),
                child: ProductImage(widget.paths[i], aspectRatio: 16 / 9, radius: 0, padding: 0, fit: BoxFit.cover),
              ),
            ),
          ),
          if (n > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: Space.sm,
              child: ExcludeSemantics(child: Center(child: _Dots(count: n, index: _index))),
            ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.inverseSurface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
          children: [
            for (var i = 0; i < count; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.onInverseSurface.withValues(alpha: i == index ? 1 : 0.45),
                ),
                child: const SizedBox.square(dimension: 6),
              ),
          ],
        ),
      ),
    );
  }
}

void _openViewer(BuildContext context, List<String> paths, int start) {
  final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.normal;
  Navigator.of(context).push(PageRouteBuilder<void>(
    fullscreenDialog: true,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (_, _, _) => _Viewer(paths: paths, start: start),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
  ));
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.paths, required this.start});

  final List<String> paths;
  final int start;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late final _page = PageController(initialPage: widget.start);
  late int _index = widget.start;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final n = widget.paths.length;
    final still = MediaQuery.disableAnimationsOf(context);
    final fallback = Center(child: Icon(PhosphorIconsLight.storefront, size: 48, color: c.surface.withValues(alpha: 0.5)));
    return Scaffold(
      backgroundColor: c.onSurface,
      appBar: AppBar(
        backgroundColor: c.onSurface,
        foregroundColor: c.surface,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(PhosphorIconsBold.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('${_index + 1} of $n'),
      ),
      body: PageView.builder(
        controller: _page,
        itemCount: n,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => Semantics(
          image: true,
          label: 'Photo of the shop, ${i + 1} of $n',
          child: LayoutBuilder(
            builder: (context, box) => CachedNetworkImage(
              imageUrl: publicImageUrl(widget.paths[i]),
              fit: BoxFit.contain,
              memCacheWidth: (box.maxWidth * MediaQuery.devicePixelRatioOf(context)).round(),
              fadeInDuration: still ? Duration.zero : Motion.normal,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
          ),
        ),
      ),
    );
  }
}
