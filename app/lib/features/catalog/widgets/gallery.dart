import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';

/// The photos for [color]: that colour's own first, then the untagged ones (box, back, any colour). A colour with
/// none of its own shows every photo.
List<ProductPhoto> photosFor(List<ProductPhoto> photos, String color) {
  final own = [for (final p in photos) if (p.color == color) p];
  return own.isEmpty ? photos : [...own, for (final p in photos) if (p.color == null) p];
}

/// The product page's photos: square on white so every product lines up, pinch or double-tap to zoom, tap for full
/// screen, and a thumbnail strip between Previous / Next. A new set of photos (another colour) fades in from the first.
class ProductGallery extends StatelessWidget {
  const ProductGallery({super.key, required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.fast,
        child: _Gallery(key: ValueKey(paths.join('\n')), paths: paths),
      );
}

class _Gallery extends StatefulWidget {
  const _Gallery({super.key, required this.paths});

  final List<String> paths;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final _pages = PageController();
  int _page = 0;
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _show(int i) => MediaQuery.disableAnimationsOf(context)
      ? _pages.jumpToPage(i)
      : _pages.animateToPage(i, duration: Motion.normal, curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final paths = widget.paths;
    final n = paths.length;
    return ColoredBox(
      color: c.surface,
      child: Column(
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top), // the back / heart buttons float over the photo
          AspectRatio(
            aspectRatio: 1,
            child: n == 0
                ? ProductImage(null, radius: 0, color: c.surface)
                : PageView.builder(
                    controller: _pages,
                    itemCount: n,
                    physics: _zoomed ? const NeverScrollableScrollPhysics() : null, // a zoomed photo pans instead
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => Semantics(
                      button: true,
                      label: n > 1 ? 'Photo ${i + 1} of $n, opens full screen' : 'Product photo, opens full screen',
                      child: _Zoomable(
                        active: i == _page,
                        onZoom: (z) => setState(() => _zoomed = z),
                        onTap: () => openPhotoViewer(context, paths, i, owner: this, onPage: _pages.jumpToPage),
                        child: Hero(
                          tag: (this, i),
                          child: ProductImage(paths[i], radius: 0, color: c.surface),
                        ),
                      ),
                    ),
                  ),
          ),
          // buttons as well as the swipe and the thumbnails: no action is gesture-only
          if (n > 1)
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous photo',
                  onPressed: _page == 0 ? null : () => _show(_page - 1),
                  icon: const Icon(PhosphorIconsBold.caretLeft, size: 18),
                ),
                Expanded(
                  child: SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      itemCount: n,
                      separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
                      itemBuilder: (context, i) => Semantics(
                        button: true,
                        selected: i == _page,
                        label: 'Photo ${i + 1} of $n',
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: () => _show(i),
                          borderRadius: BorderRadius.circular(Radii.sm),
                          child: AnimatedContainer(
                            duration: Motion.fast,
                            width: 48,
                            decoration: BoxDecoration(
                              border: Border.all(color: i == _page ? c.primary : c.outlineVariant, width: i == _page ? 2 : 1),
                              borderRadius: BorderRadius.circular(Radii.sm),
                            ),
                            child: ProductImage(paths[i], radius: Radii.sm, padding: 2, color: c.surface),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next photo',
                  onPressed: _page == n - 1 ? null : () => _show(_page + 1),
                  icon: const Icon(PhosphorIconsBold.caretRight, size: 18),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Pinch or double-tap to zoom (double-tap again to fit). While it fits, one-finger drags belong to the page
/// around it (the gallery pages, the viewer's swipe down via [onPull]).
class _Zoomable extends StatefulWidget {
  const _Zoomable({
    super.key,
    required this.active,
    required this.onZoom,
    required this.child,
    this.onTap,
    this.onPull,
    this.onPullEnd,
  });

  final bool active; // the page on screen; a page swiped away snaps back to fit
  final ValueChanged<bool> onZoom;
  final VoidCallback? onTap;
  final ValueChanged<double>? onPull; // vertical drag while it fits, in dp
  final ValueChanged<double>? onPullEnd; // with the vertical velocity
  final Widget child;

  @override
  State<_Zoomable> createState() => _ZoomableState();
}

class _ZoomableState extends State<_Zoomable> with SingleTickerProviderStateMixin {
  final _t = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: Motion.normal)
    ..addListener(() => _t.value = _tween.transform(Curves.easeOutCubic.transform(_anim.value)));
  Matrix4Tween _tween = Matrix4Tween();
  Offset _tapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _t.addListener(() {
      final zoomed = _t.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed == _zoomed) return;
      setState(() => _zoomed = zoomed);
      widget.onZoom(zoomed);
    });
  }

  @override
  void didUpdateWidget(_Zoomable old) {
    super.didUpdateWidget(old);
    if (!widget.active && _zoomed) {
      _anim.stop();
      // after this frame: the reset tells the page around it, which may be mid-layout now
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _t.value = Matrix4.identity();
      });
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _t.dispose();
    super.dispose();
  }

  /// The viewer's zoom button: in around the middle, or back to fit.
  void toggle() {
    _tapAt = context.size!.center(Offset.zero);
    _doubleTap();
  }

  void _doubleTap() {
    const s = 2.5; // zoom in around the tapped point
    final to = _zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translateByDouble(-_tapAt.dx * (s - 1), -_tapAt.dy * (s - 1), 0, 1)
          ..scaleByDouble(s, s, 1, 1));
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.value = to;
      return;
    }
    _tween = Matrix4Tween(begin: _t.value, end: to);
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.onTap,
        onDoubleTapDown: (d) => _tapAt = d.localPosition,
        onDoubleTap: _doubleTap,
        child: InteractiveViewer(
          transformationController: _t,
          maxScale: 4,
          panEnabled: _zoomed,
          onInteractionUpdate: (d) {
            if (!_zoomed && d.pointerCount == 1) widget.onPull?.call(d.focalPointDelta.dy);
          },
          onInteractionEnd: (d) {
            if (!_zoomed) widget.onPullEnd?.call(d.velocity.pixelsPerSecond.dy);
          },
          child: widget.child,
        ),
      );
}

/// Full screen on black: swipe or Previous / Next between photos, pinch, double-tap or the zoom button to zoom, swipe
/// down, Close or back to close. Always the full photo, also in data-saver mode (the thumb shows while it loads).
/// [onPage] keeps the gallery behind in step, so the photo flies back to where it came from.
void openPhotoViewer(
  BuildContext context,
  List<String> paths,
  int start, {
  required Object owner, // hero tags are (owner, index), as in the gallery
  required ValueChanged<int> onPage,
}) {
  final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.normal;
  Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false, // swiping down shows the product page behind
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (_, _, _) => _Viewer(paths: paths, start: start, owner: owner, onPage: onPage),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
  ));
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.paths, required this.start, required this.owner, required this.onPage});

  final List<String> paths;
  final int start;
  final Object owner;
  final ValueChanged<int> onPage;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late final _pages = PageController(initialPage: widget.start);
  late int _index = widget.start;
  bool _zoomed = false;
  double _pull = 0; // how far it's been dragged down (or up)
  final _zoom = <int, GlobalKey<_ZoomableState>>{};

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int i) => MediaQuery.disableAnimationsOf(context)
      ? _pages.jumpToPage(i)
      : _pages.animateToPage(i, duration: Motion.normal, curve: Curves.easeOutCubic);

  void _pullEnd(double velocity) {
    if (_pull == 0) return; // a pinch, not a pull
    if (_pull.abs() > 120 || velocity.abs() > 800) {
      Navigator.of(context).pop();
    } else {
      setState(() => _pull = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final n = widget.paths.length;
    final still = MediaQuery.disableAnimationsOf(context);
    final fallback = Center(child: Icon(PhosphorIconsLight.deviceMobile, size: 48, color: c.surface.withValues(alpha: 0.5)));
    Widget photo(String path) {
      final thumb = thumbPathFor(path);
      return CachedNetworkImage(
        imageUrl: publicImageUrl(path),
        fit: BoxFit.contain,
        fadeInDuration: still ? Duration.zero : Motion.normal,
        placeholder: (_, _) => thumb == null
            ? fallback
            : CachedNetworkImage(imageUrl: publicImageUrl(thumb), fit: BoxFit.contain, errorWidget: (_, _, _) => fallback),
        errorWidget: (_, _, _) => fallback,
      );
    }

    return Scaffold(
      backgroundColor: c.onSurface.withValues(alpha: 1 - (_pull.abs() / 400).clamp(0, 0.7)),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: c.surface,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(PhosphorIconsBold.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: n > 1 ? Text('${_index + 1} of $n') : null,
        actions: [
          IconButton(
            tooltip: _zoomed ? 'Fit to screen' : 'Zoom in',
            onPressed: () => _zoom[_index]?.currentState?.toggle(),
            icon: Icon(_zoomed ? PhosphorIconsBold.magnifyingGlassMinus : PhosphorIconsBold.magnifyingGlassPlus),
          ),
        ],
      ),
      // buttons as well as the gestures: nothing here is swipe-only
      bottomNavigationBar: n < 2
          ? null
          : SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Previous photo',
                    color: c.surface,
                    onPressed: _index == 0 ? null : () => _go(_index - 1),
                    icon: const Icon(PhosphorIconsBold.caretLeft),
                  ),
                  IconButton(
                    tooltip: 'Next photo',
                    color: c.surface,
                    onPressed: _index == n - 1 ? null : () => _go(_index + 1),
                    icon: const Icon(PhosphorIconsBold.caretRight),
                  ),
                ],
              ),
            ),
      body: AnimatedSlide(
        offset: Offset(0, _pull / MediaQuery.sizeOf(context).height),
        duration: _pull == 0 && !still ? Motion.fast : Duration.zero, // follows the finger, springs back on release
        child: PageView.builder(
          controller: _pages,
          itemCount: n,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
          onPageChanged: (i) {
            setState(() => _index = i);
            widget.onPage(i);
          },
          itemBuilder: (context, i) => Semantics(
            image: true,
            label: 'Photo ${i + 1} of $n',
            child: _Zoomable(
              key: _zoom.putIfAbsent(i, GlobalKey.new),
              active: i == _index,
              onZoom: (z) => setState(() => _zoomed = z),
              onPull: (dy) => setState(() => _pull += dy),
              onPullEnd: _pullEnd,
              child: Hero(tag: (widget.owner, i), child: photo(widget.paths[i])),
            ),
          ),
        ),
      ),
    );
  }
}
