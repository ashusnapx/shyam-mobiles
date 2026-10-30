import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/network.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/generative.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/widgets.dart';
import '../../offers/data/offers.dart';
import '../../notifications/widgets/notification_widgets.dart';
import '../../offers/widgets/offer_widgets.dart';
import '../data/catalog.dart';
import '../data/rails.dart';
import '../widgets/product_rail.dart';
import '../widgets/product_tile.dart';
import '../widgets/store_links.dart';
import '../widgets/store_photos.dart';

/// Products first: a pinned bar (brand, call, search), one carousel of offers and featured products, a row of
/// categories, a one-line repair strip, then rails of products and a grid; the shop's card last.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _slides = 6; // banners first, then featured products

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    ref.invalidate(categoriesProvider);
    ref.invalidate(storeSettingsProvider);
    ref.invalidate(bannersProvider);
    ref.invalidate(availableOffersProvider); // which offer banners still apply
    ref.invalidate(latestProvider);
    try {
      ref.invalidate(homeProvider);
      await ref.read(homeProvider.future);
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final settings = ref.watch(storeSettingsProvider).value;
    final saver = ref.watch(dataSaverProvider) == DataMode.saver;
    final offline = ref.watch(offlineProvider);
    ref.listen(offlineProvider, (was, now) {
      if (was != true || now) return;
      // back online: replace what was saved on the phone
      ref.invalidate(homeProvider);
      ref.invalidate(storeSettingsProvider);
    });
    return Scaffold(
      // the carousel grows a touch while the page is pulled down
      body: OverscrollScope(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            edgeOffset: _TopBar.height, // the spinner comes out under the pinned bar
            onRefresh: () => _refresh(context, ref),
            child: CustomScrollView(
              slivers: [
                SliverPersistentHeader(key: const ValueKey('top'), pinned: true, delegate: _TopBar(settings)),
                if (offline && home.hasValue) const SliverToBoxAdapter(key: ValueKey('offline'), child: _OfflineBanner()),
                ...switch (home) {
                  AsyncValue(value: final d?) => _sections(context, ref, d, settings, saver: saver),
                  AsyncValue(:final error?) => [
                      SliverFillRemaining(
                        key: const ValueKey('error'),
                        hasScrollBody: false,
                        child: ErrorView(error: error, onRetry: () => ref.invalidate(homeProvider)),
                      ),
                    ],
                  _ => [SliverToBoxAdapter(key: const ValueKey('skeleton'), child: _skeleton)],
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, WidgetRef ref, HomeData d, StoreSettings? settings,
      {required bool saver}) {
    if (d.categories.isEmpty && d.featured.isEmpty && d.accessories.isEmpty) {
      return const [
        SliverFillRemaining(
          key: ValueKey('empty'),
          hasScrollBody: false,
          child: EmptyState(
            icon: PhosphorIconsRegular.storefront,
            title: 'The shelves are empty',
            message: 'New stock is on its way. Pull down to check again.',
          ),
        ),
      ];
    }
    final banners = ref.watch(homeBannersProvider).take(_slides).toList();
    final slides = <_Slide>[
      for (final b in banners)
        (key: 'banner ${b.id}', build: (_) => PromoBannerCard(b, onTap: () => openAppLink(context, b.link))),
      for (final card in d.featured.take(_slides - banners.length))
        (key: 'product ${card.id}', build: (photo) => _ProductSlide(card, photo: photo)),
    ];
    final phoneSlugs = {for (final c in d.categories) if (c.kind == CategoryKind.phone) c.slug};
    final phones = [for (final c in d.featured) if (phoneSlugs.contains(c.categorySlug)) c];
    return [
      if (slides.isNotEmpty)
        SliverToBoxAdapter(
          key: const ValueKey('hero'),
          child: PullScale(child: _HeroCarousel(slides, saver: saver)).enter(context),
        ),
      SliverToBoxAdapter(key: const ValueKey('categories'), child: _CategoryRow(d.categories).enter(context, index: 1)),
      SliverToBoxAdapter(key: const ValueKey('repair'), child: const _RepairStrip().enter(context, index: 2)),
      if (d.accessories.isNotEmpty)
        SliverToBoxAdapter(
          key: const ValueKey('deals'),
          child: ProductRail(
            title: 'Deals under ₹1,500',
            band: 'deals',
            value: AsyncData(d.accessories),
            onSeeAll: () => context.go('/search?sort=price_asc'),
          ).enter(context, index: 3),
        ),
      if (phones.isNotEmpty)
        SliverToBoxAdapter(
          key: const ValueKey('phones'),
          child: RevealOnScroll(
            child: ProductRail(
              title: 'Featured phones',
              band: 'phones',
              value: AsyncData(phones),
              onSeeAll: () => context.go('/search?category=${phones.first.categorySlug}'),
            ),
          ),
        ),
      const SliverToBoxAdapter(key: ValueKey('recent'), child: RevealOnScroll(child: RecentlyViewedRail())),
      ..._moreGrid(context, ref),
      if (settings != null) SliverToBoxAdapter(key: const ValueKey('store'), child: _StoreCard(settings)),
      const SliverPadding(key: ValueKey('end'), padding: EdgeInsets.only(bottom: Space.xl)),
    ];
  }

  /// "More to explore": the newest products, two to a row on their own band. Hidden while loading, empty or failing.
  List<Widget> _moreGrid(BuildContext context, WidgetRef ref) {
    final more = ref.watch(latestProvider).value ?? const <ProductCard>[];
    if (more.isEmpty) return const [];
    final c = Theme.of(context).colorScheme;
    Widget tile(ProductCard card) => DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: c.outlineVariant),
          ),
          child: Padding(padding: const EdgeInsets.all(6), child: ProductTile(card)),
        );
    return [
      SliverToBoxAdapter(
        key: const ValueKey('more'),
        child: RevealOnScroll(
            child: SectionBand(
              seed: 'explore',
              child: Column(
                children: [
                  RailHeader('More to explore', accent: softPalette('explore').accent,
                      onSeeAll: () => context.go('/search?sort=newest')),
                  for (var i = 0; i < more.length; i += 2)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.md,
                        children: [
                          Expanded(child: tile(more[i])),
                          Expanded(child: i + 1 < more.length ? tile(more[i + 1]) : const SizedBox()),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ),
    ];
  }

  static final _skeleton = Skeletonizer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: _ProductSlide(fakeCards(1).first),
        ),
        const SizedBox(height: 48), // the carousel's controls
        _CategoryRow([
          for (var i = 0; i < 6; i++)
            Category(id: '$i', slug: 'skeleton-$i', name: 'Category', kind: CategoryKind.accessory),
        ]),
        const _RepairStrip(),
        ProductRail(title: 'Deals under ₹1,500', value: AsyncData(fakeCards(3))),
      ],
    ),
  );
}

/// The pinned top: brand, the bell's slot and Call (56 dp), then the search field that opens Search (56 dp).
class _TopBar extends SliverPersistentHeaderDelegate {
  const _TopBar(this.settings);

  static const height = 112.0;

  final StoreSettings? settings;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  bool shouldRebuild(_TopBar old) => old.settings != settings;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final s = settings;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        // a hairline once products scroll under it
        border: Border(bottom: BorderSide(color: shrinkOffset > 0 ? c.outlineVariant : c.surface)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.xs, 0),
              child: Row(
                children: [
                  const BrandMark(size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Shyam Mobiles',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.displaySmall?.copyWith(fontSize: 22, height: 1),
                    ),
                  ),
                  const NotificationBell(), // left of Call; nothing when signed out
                  IconButton(
                    tooltip: 'Call the store',
                    icon: const Icon(PhosphorIconsRegular.phone),
                    onPressed: s == null
                        ? null
                        : () => openExternal(context, Uri(scheme: 'tel', path: s.storePhone), 'Couldn’t open the dialer.'),
                  ),
                ],
              ),
            ),
          ),
          const _SearchField(),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.surfaceContainer, borderRadius: BorderRadius.circular(Radii.md)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.wifiSlash, size: 18, color: c.onSurfaceVariant),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text('You’re offline · showing saved items', style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final hint = Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
      child: Material(
        color: c.surfaceContainer,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          onTap: () => context.go('/search'),
          borderRadius: BorderRadius.circular(Radii.md),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Row(
                children: [
                  Icon(PhosphorIconsRegular.magnifyingGlass, size: 20, color: c.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Search phones, cases, chargers…', maxLines: 1, overflow: TextOverflow.ellipsis, style: hint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One carousel slide: an offer banner or a featured product; [build] gets whether to load its photo.
typedef _Slide = ({String key, Widget Function(bool photo) build});

/// Offers and featured products in one carousel that moves on every few seconds. Previous / Next and the dots as
/// well as the swipe (nothing is swipe-only); touching it pauses it. Stays still with reduce-motion or TalkBack on,
/// in data-saver mode, and while another tab is showing.
class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel(this.slides, {required this.saver});

  final List<_Slide> slides;
  final bool saver; // no auto-advance, and only the shown slide loads its photo

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  static const _interval = Duration(milliseconds: 4500);
  // a short row under the slide: full width for a thumb, less height than a toolbar
  static final _controlStyle = IconButton.styleFrom(
    minimumSize: const Size(48, 32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: EdgeInsets.zero,
  );
  int _index = 0;
  int _direction = 1;
  Timer? _timer;

  int get _count => widget.slides.length;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(_HeroCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= _count) _index = 0;
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (_count < 2 || widget.saver) return;
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted) return;
      final still = MediaQuery.disableAnimationsOf(context) || MediaQuery.accessibleNavigationOf(context);
      if (!still && TickerMode.valuesOf(context).enabled) _step(1);
    });
  }

  void _step(int by) => _go((_index + by + _count) % _count, by);

  void _go(int i, [int? direction]) {
    setState(() {
      _direction = direction ?? (i >= _index ? 1 : -1);
      _index = i;
    });
    _restart();
  }

  Widget _slide(int i, {bool photo = true}) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: Space.lg), child: widget.slides[i].build(photo));

  @override
  Widget build(BuildContext context) {
    if (_count == 1) return Padding(padding: const EdgeInsets.only(top: Space.xs), child: _slide(0));
    final c = Theme.of(context).colorScheme;
    final key = widget.slides[_index].key;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 500);
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Column(
        children: [
          GestureDetector(
            onHorizontalDragStart: (_) => _timer?.cancel(),
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() > 150) {
                _step(v < 0 ? 1 : -1);
              } else {
                _restart();
              }
            },
            onHorizontalDragCancel: _restart,
            // Every slide is laid out invisibly so the carousel takes the tallest one's height and each slide fills
            // it: all slides are the same size and nothing below jumps when it moves on.
            child: Stack(
              children: [
                for (var i = 0; i < _count; i++)
                  Visibility(
                    visible: false,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: _slide(i, photo: !widget.saver),
                  ),
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
                    transitionBuilder: (child, animation) {
                      final incoming = child.key == ValueKey(key);
                      final from = Offset((incoming ? 0.14 : -0.14) * _direction, 0);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(begin: from, end: Offset.zero).animate(animation),
                          child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(animation), child: child),
                        ),
                      );
                    },
                    child: KeyedSubtree(key: ValueKey(key), child: _slide(_index)),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous slide',
                style: _controlStyle,
                icon: const Icon(PhosphorIconsBold.caretLeft, size: 18),
                onPressed: () => _step(-1),
              ),
              // the dots jump straight to a slide; Previous / Next carry the screen-reader label
              Semantics(
                label: 'Slide ${_index + 1} of $_count',
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _count; i++)
                      InkResponse(
                        onTap: () => _go(i),
                        radius: 16,
                        child: SizedBox(
                          width: 26,
                          height: 32,
                          child: Center(
                            child: AnimatedContainer(
                              duration: duration,
                              curve: Curves.easeOutCubic,
                              width: i == _index ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == _index ? c.primary : c.outline,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Next slide',
                style: _controlStyle,
                icon: const Icon(PhosphorIconsBold.caretRight, size: 18),
                onPressed: () => _step(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A featured product on its own deep colours ([deepPalette] of its id), like the offer banners beside it; the whole
/// card opens it.
class _ProductSlide extends StatelessWidget {
  const _ProductSlide(this.card, {this.photo = true});

  final ProductCard card;
  final bool photo; // false for the invisible sizing copies in data-saver mode: same size, nothing downloaded

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final palette = deepPalette(card.id); // white text passes 4.5:1 on every stop
    final off = discountPercent(card.minPricePaise, card.mrpPaise);
    return Pressable(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        // still: the carousel already moves, and a drifting hero would repaint the top of Home all day
        child: AuroraBackground(
          palette: palette,
          seed: card.id,
          still: true,
          child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => context.push('/product/${card.slug}'),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center, // shorter slides sit centred at the carousel's height
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('FEATURED', style: t.labelSmall?.copyWith(color: Colors.white70, letterSpacing: 1.3)),
                            const SizedBox(height: 2),
                            Semantics(
                              header: true,
                              child: Text(
                                shortName(card.name, card.brandName),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ['From ${formatInr(card.minPricePaise)}', if (off > 0) '$off% off MRP'].join('  ·  '),
                              style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                            ),
                            const SizedBox(height: 10),
                            // looks like the banners' white button; the whole card is the tap target
                            DecoratedBox(
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 5),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: Space.xs,
                                  children: [
                                    Text(card.categorySlug == 'smartphones' ? 'View phone' : 'View',
                                        style: t.labelMedium?.copyWith(color: palette.stops.first)),
                                    Icon(PhosphorIconsBold.arrowRight, size: 14, color: palette.stops.first),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      SizedBox(
                        width: 84,
                        // drifts a little slower than the page; the card clips it
                        child: Parallax(
                          rate: 0.12,
                          child: ProductImage(photo ? card.coverPath : null, radius: Radii.md, padding: Space.xs,
                              color: Theme.of(context).colorScheme.surface),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ),
    );
  }
}

/// Short one-line label and icon per category. Its colours come from its slug ([softPalette]); saffron is kept for
/// Repairs.
(Color, Color) _tint(String slug) {
  final p = softPalette(slug);
  return (p.band, p.accent);
}

const _categoryLooks = {
  'smartphones': ('Phones', PhosphorIconsRegular.deviceMobile),
  'keypad-phones': ('Keypad', PhosphorIconsRegular.deviceMobileSpeaker),
  'cases-covers': ('Cases', PhosphorIconsRegular.deviceMobileCamera),
  'screen-guards': ('Guards', PhosphorIconsRegular.shieldCheck),
  'chargers-cables': ('Chargers', PhosphorIconsRegular.plugCharging),
  'earbuds-headphones': ('Earbuds', PhosphorIconsRegular.headphones),
  'power-banks': ('Power bank', PhosphorIconsRegular.batteryCharging),
};

/// One row of round category tiles that scrolls sideways (the next tile peeks out), with All first and See all last,
/// so every category is a tap away without a swipe.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow(this.categories);

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _CategoryTile(label: 'All', icon: PhosphorIconsRegular.squaresFour, onTap: () => context.go('/search')),
      for (final cat in categories)
        _CategoryTile(
          label: _categoryLooks[cat.slug]?.$1 ?? cat.name,
          icon: _categoryLooks[cat.slug]?.$2 ?? PhosphorIconsRegular.tag,
          tint: _tint(cat.slug),
          onTap: () => context.go('/search?category=${cat.slug}'),
        ),
      _CategoryTile(
        label: 'Repairs',
        icon: PhosphorIconsRegular.wrench,
        tint: (BrandColors.cream, BrandColors.saffron),
        onTap: () => context.go('/repairs'),
      ),
      _CategoryTile(label: 'See all', icon: PhosphorIconsRegular.arrowRight, onTap: () => context.go('/search')),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final t in tiles) SizedBox(width: 72, child: t)],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label, required this.icon, required this.onTap, this.tint});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final (Color, Color)? tint; // background and icon; null is the neutral All / See all tile

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Pressable(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: tint?.$1 ?? c.surfaceContainer, shape: BoxShape.circle),
                child: SizedBox.square(dimension: 44, child: Icon(icon, size: 20, color: tint?.$2 ?? c.primary)),
              ),
              const SizedBox(height: Space.xs),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One slim line (48 dp) to book a repair: saffron on cream, like the Repairs tile.
class _RepairStrip extends StatelessWidget {
  const _RepairStrip();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 10, Space.lg, 0),
      child: Material(
        color: BrandColors.cream,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => context.push('/repairs/new'),
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Space.xs),
              child: Row(
                children: [
                  const Icon(PhosphorIconsFill.wrench, size: 20, color: BrandColors.saffron),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      const TextSpan(children: [
                        TextSpan(text: 'Screen or battery trouble? '),
                        TextSpan(
                          text: 'Book a repair',
                          style: TextStyle(color: BrandColors.saffron, fontWeight: FontWeight.w800),
                        ),
                      ]),
                      style: t.bodySmall?.copyWith(color: BrandColors.creamInk, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(PhosphorIconsBold.arrowRight, size: 16, color: BrandColors.saffron),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard(this.settings);

  final StoreSettings settings;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final details = [
      settings.storeAddress,
      if (settings.storeHours.isNotEmpty) 'Open ${settings.storeHours}',
    ].where((s) => s.isNotEmpty).join(' · ');
    final listing = settings.mapsListingUri;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 22, Space.lg, 0),
      child: Card(
        clipBehavior: Clip.antiAlias, // rounds the photos' top corners
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (settings.storePhotos.isNotEmpty) StorePhotoCarousel(settings.storePhotos),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.xs, Space.md),
              child: Row(
                children: [
                  Icon(PhosphorIconsRegular.storefront, size: 24, color: c.primary),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Visit the store', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text(details, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (settings.mapsDestination.isNotEmpty)
                    IconButton(
                      tooltip: 'Directions to the store',
                      icon: const Icon(PhosphorIconsRegular.navigationArrow),
                      onPressed: () =>
                          openExternal(context, directionsUri(settings.mapsDestination), 'Couldn’t open Google Maps.'),
                    ),
                  IconButton(
                    tooltip: 'WhatsApp the store',
                    color: c.secondary,
                    icon: const WhatsAppIcon(),
                    onPressed: () => openExternal(context, whatsappUri(settings.storePhone), 'Couldn’t open WhatsApp.'),
                  ),
                ],
              ),
            ),
            if (listing != null)
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xs),
                minLeadingWidth: 24,
                horizontalTitleGap: Space.md,
                leading: const Icon(PhosphorIconsRegular.mapTrifold),
                title: const Text('Photos, reviews & hours on Google Maps'),
                trailing: const Icon(PhosphorIconsRegular.arrowSquareOut, size: 18),
                onTap: () => openExternal(context, listing, 'Couldn’t open Google Maps.'),
              ),
          ],
        ),
      ),
    );
  }
}
