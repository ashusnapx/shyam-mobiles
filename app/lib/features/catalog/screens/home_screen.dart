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
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/widgets.dart';
import '../../cart/data/cart.dart';
import '../../exchange/widgets/exchange_widgets.dart' show showExchangeSheet;
import '../../offers/data/offers.dart';
import '../../offers/widgets/occasion_chip.dart';
import '../../notifications/widgets/notification_widgets.dart';
import '../../offers/widgets/hero_card.dart';
import '../../offers/widgets/offer_widgets.dart';
import '../data/catalog.dart';
import '../data/hero.dart';
import '../data/rails.dart';
import '../data/social_repository.dart';
import '../data/variant_options.dart' show initialVariant;
import '../widgets/product_rail.dart';
import '../widgets/instagram_row.dart';
import '../widgets/product_tile.dart';
import '../widgets/store_photos.dart';

/// Products first: a pinned bar (brand, WhatsApp, call, search), one carousel of offers and featured products, why
/// to buy here, the categories, then what this customer viewed, the phones, one repair strip, budgets, deals, brands
/// and the newest products; the shop's card last.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _slides = 6; // banners first, then featured products

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    ref.invalidate(categoriesProvider);
    ref.invalidate(storeSettingsProvider);
    ref.invalidate(bannersProvider);
    ref.invalidate(availableOffersProvider); // which offer banners still apply
    ref.invalidate(latestProvider);
    ref.invalidate(instagramPostsProvider);
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
    // the owner's banners first, then the automatic ones that are on, then featured products, six at most
    final latest = ref.watch(latestProvider).value ?? const <ProductCard>[];
    final auto = autoSlides(settings?.autoBanners ?? StoreSettings.defaultAutoBanners,
        cards: [...d.featured, ...d.accessories, ...latest], newest: latest, now: DateTime.now());
    final shown = {for (final a in auto) ?a.card?.id};
    final offers = ref.watch(availableOffersProvider).value ?? const <Offer>[];
    final pool = [...latest, ...d.featured, ...d.accessories]; // newest first: the cut-outs fanned on slides with no photo
    final slides = <_Slide>[
      for (final b in ref.watch(homeBannersProvider))
        (
          key: 'banner ${b.id}',
          build: (photo) => PromoBannerCard(b,
              photo: photo,
              pool: pool,
              offer: offers.where((o) => o.id == b.promotionId).firstOrNull,
              onTap: () => openAppLink(context, b.link)),
        ),
      for (final a in auto)
        if (a.card case final c?)
          (
            key: '${a.kind.name} ${c.id}',
            build: (photo) => _ProductSlide(c,
                photo: photo, kicker: a.kind == AutoBanner.deal ? 'DEAL OF THE DAY' : 'NEW', endsAt: a.endsAt),
          )
        else
          (key: a.kind.name, build: (photo) => _autoPromo(context, a.kind, pool, photo)),
      for (final card in d.featured)
        if (!shown.contains(card.id)) (key: 'product ${card.id}', build: (photo) => _ProductSlide(card, photo: photo)),
    ].take(_slides).toList();
    final phoneSlugs = {for (final c in d.categories) if (c.kind == CategoryKind.phone) c.slug};
    final phones = [for (final c in d.featured) if (phoneSlugs.contains(c.categorySlug)) c];
    final phoneCategory = phones.firstOrNull?.categorySlug ?? 'smartphones';
    return [
      if (slides.isNotEmpty)
        SliverToBoxAdapter(
          key: const ValueKey('hero'),
          child: PullScale(child: _HeroCarousel(slides, saver: saver)).enter(context),
        ),
      const SliverToBoxAdapter(key: ValueKey('occasion'), child: OccasionChip()), // Campaign calendar's auto-apply offer
      if (settings != null)
        SliverToBoxAdapter(key: const ValueKey('trust'), child: _TrustStrip(settings).enter(context, index: 1)),
      SliverToBoxAdapter(key: const ValueKey('categories'), child: _CategoryRow(d.categories).enter(context, index: 2)),
      const SliverToBoxAdapter(key: ValueKey('recent'), child: RecentlyViewedRail()),
      if (phones.isNotEmpty)
        SliverToBoxAdapter(
          key: const ValueKey('phones'),
          child: ProductRail(
            title: 'Featured phones',
            band: sectionTints.explore, // neutral: the one tinted panel on Home is the deals'
            value: AsyncData(phones),
            onSeeAll: () => context.go('/search?category=$phoneCategory'),
          ).enter(context, index: 3),
        ),
      SliverToBoxAdapter(key: const ValueKey('repair'), child: const _RepairStrip().enter(context, index: 4)),
      // below the fold, sections are simply there: no reveal that could leave one invisible
      SliverToBoxAdapter(key: const ValueKey('budget'), child: _BudgetRow(phoneCategory)),
      if (d.accessories.isNotEmpty)
        SliverToBoxAdapter(
          key: const ValueKey('deals'),
          child: ProductRail(
            title: 'Deals under ₹1,500',
            band: sectionTints.deals,
            value: AsyncData(d.accessories),
            onSeeAll: () => context.go('/search?max=150000'),
          ),
        ),
      SliverToBoxAdapter(key: const ValueKey('brands'), child: _BrandRow(phones)),
      ..._moreGrid(context, ref),
      const SliverToBoxAdapter(key: ValueKey('instagram'), child: InstagramRow()),
      if (settings != null) SliverToBoxAdapter(key: const ValueKey('store'), child: _StoreCard(settings)),
      // the page ends a section gap below the last card, clear of the (see-through) nav bar
      SliverPadding(
        key: const ValueKey('end'),
        padding: EdgeInsets.only(bottom: Space.section + MediaQuery.paddingOf(context).bottom),
      ),
    ];
  }

  /// "New in the shop": the newest products, two to a row on the plain canvas. Nothing at all while loading, empty or
  /// failing.
  List<Widget> _moreGrid(BuildContext context, WidgetRef ref) {
    final more = ref.watch(latestProvider).value ?? const <ProductCard>[];
    if (more.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        key: const ValueKey('more'),
        child: Column(
          children: [
            SectionHeader('New in the shop', gutter: Space.gutter, onSeeAll: () => context.go('/search?sort=newest')),
            for (var i = 0; i < more.length; i += 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.md,
                  children: [
                    Expanded(child: ProductTile(more[i])),
                    Expanded(child: i + 1 < more.length ? ProductTile(more[i + 1]) : const SizedBox()),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  static final _skeleton = Skeletonizer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: _ProductSlide(fakeCards(1).first),
        ),
        const SizedBox(height: Space.md),
        _CategoryRow([
          for (var i = 0; i < 6; i++)
            Category(id: '$i', slug: 'skeleton-$i', name: 'Category', kind: CategoryKind.accessory),
        ]),
        ProductRail(title: 'Featured phones', value: AsyncData(fakeCards(3))),
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
    final s = settings;
    // frosted: products blur as they scroll under it, with a hairline once they do
    return GlassSurface(
      border: Border(bottom: BorderSide(color: shrinkOffset > 0 ? Glass.hairline : Colors.transparent)),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.sm, 0),
              child: Row(
                children: [
                  const BrandMark(size: 32),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      'Shyam Mobiles',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // the wordmark is a logo: it keeps its size when the phone's text is larger
                      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1),
                      style: t.displaySmall?.copyWith(fontSize: 22, height: 1),
                    ),
                  ),
                  const NotificationBell(), // left of Call; nothing when signed out
                  IconButton(
                    tooltip: 'WhatsApp the shop',
                    icon: const WhatsAppIcon(),
                    onPressed: s == null
                        ? null
                        : () => openUri(context, whatsAppUri(s.storePhone, text: 'Hi, I have a question.')),
                  ),
                  IconButton(
                    tooltip: 'Call the shop',
                    icon: const Icon(PhosphorIconsRegular.phone),
                    onPressed: s == null ? null : () => openUri(context, telUri(s.storePhone)),
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
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
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
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
      child: Material(
        color: c.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: c.outlineVariant),
        ),
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
                  const SizedBox(width: Space.md),
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

/// Exchange and Repairs as banners: no product to buy, a form to open. Exchange fans the newest phone and an older one.
Widget _autoPromo(BuildContext context, AutoBanner kind, List<ProductCard> pool, bool photo) => kind == AutoBanner.exchange
    ? PromoBannerCard(
        PromoBanner(
          id: 'auto-exchange',
          title: 'Exchange your old phone',
          subtitle: 'Trade in for a better one',
          ctaLabel: 'Get an estimate',
          link: '/',
          startsAt: DateTime(2026),
        ),
        kicker: 'EXCHANGE',
        fan: HeroFan.exchange,
        icon: PhosphorIconsFill.arrowsClockwise,
        pool: pool,
        photo: photo,
        onTap: () => showExchangeSheet(context),
      )
    : PromoBannerCard(
        PromoBanner(
          id: 'auto-repairs',
          title: 'Repairs · same day',
          subtitle: 'Screens, batteries, charging ports',
          ctaLabel: 'Book a repair',
          link: '/repairs/new',
          startsAt: DateTime(2026),
        ),
        kicker: 'REPAIRS',
        icon: PhosphorIconsFill.wrench,
        fan: HeroFan.none,
        photo: photo,
        onTap: () => openAppLink(context, '/repairs/new'),
      );

/// One carousel slide: an offer banner or a featured product; [build] gets whether to load its photo.
typedef _Slide = ({String key, Widget Function(bool photo) build});

/// Offers and featured products in one carousel: the next card peeks, it moves on every 5 s (a thin story-style bar in the
/// card's corner fills over it), a finger on it holds it, and a bar jumps to a slide; a screen reader swipes up / down to
/// step it (nothing is swipe-only). Still with reduce-motion or TalkBack on, in data-saver mode, and while another tab is
/// showing: then small dots stand in for the bars. The one slide motion ([HeroMotion.slowZoom]) stops while it is
/// scrolled off screen.
class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel(this.slides, {required this.saver});

  final List<_Slide> slides;
  final bool saver; // no auto-advance, and only the shown slide loads its photo

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> with SingleTickerProviderStateMixin {
  static const _fraction = 0.92; // the next card peeks
  static const _gap = 4.0; // each side of a card
  static const _barRow = 24.0; // the progress row under the card
  late final _fill = AnimationController(vsync: this, duration: Motion.hero)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _step(1);
    });
  final _pages = PageController(viewportFraction: _fraction);
  int _index = 0;
  int? _target; // where a step in flight is heading, so two quick steps add up
  ScrollPosition? _position;
  bool _onScreen = true;
  bool _touching = false;
  bool _queued = false;

  int get _count => widget.slides.length;

  bool get _still => MediaQuery.disableAnimationsOf(context) || MediaQuery.accessibleNavigationOf(context);

  /// Whether the bar fills and the carousel moves on by itself.
  bool get _auto => _count > 1 && !widget.saver && !_still;

  /// Runs the fill while nothing holds it: not touched, on screen, its tab showing.
  void _sync() {
    if (_auto && _onScreen && !_touching && TickerMode.valuesOf(context).enabled) {
      if (!_fill.isAnimating) unawaited(_fill.forward());
    } else {
      _fill.stop();
    }
  }

  @override
  void didUpdateWidget(_HeroCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= _count) _index = 0;
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _position) {
      _position?.removeListener(_track);
      _position = p?..addListener(_track);
    }
    _sync();
  }

  /// On screen or not, measured after the frame the scroll lays out (as RevealOnScroll does).
  void _track() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      final box = mounted ? context.findRenderObject() as RenderBox? : null;
      if (box == null || !box.hasSize) return;
      final top = box.localToGlobal(Offset.zero).dy;
      final on = top + box.size.height > 0 && top < MediaQuery.sizeOf(context).height;
      if (on != _onScreen) {
        _onScreen = on;
        _sync();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _position?.removeListener(_track);
    _fill.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _step(int by) {
    if (mounted) _goTo((((_target ?? _index) + by) % _count + _count) % _count);
  }

  void _goTo(int i) {
    if (!_pages.hasClients) return;
    _target = i;
    final done = MediaQuery.disableAnimationsOf(context)
        ? Future.sync(() => _pages.jumpToPage(i))
        : _pages.animateToPage(i, duration: Motion.slide, curve: Curves.easeOutCubic);
    unawaited(done.whenComplete(() {
      if (_target == i) _target = null;
    }));
  }

  void _arrived(int i) {
    setState(() => _index = i);
    _fill.value = 0;
    _sync();
  }

  void _touch(bool down) {
    _touching = down;
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 1) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, 0),
        child: TickerMode(enabled: _onScreen, child: RepaintBoundary(child: widget.slides[0].build(true))),
      );
    }
    final dots = !_auto; // nothing fills: small static dots, the current one lit
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: SizedBox(
        height: HeroCard.height + _barRow,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              // a finger on it holds the slide
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: HeroCard.height,
                child: Listener(
                onPointerDown: (_) => _touch(true),
                onPointerUp: (_) => _touch(false),
                onPointerCancel: (_) => _touch(false),
                child: TickerMode(
                  enabled: _onScreen,
                  child: RepaintBoundary(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: _count,
                      onPageChanged: _arrived,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: _gap),
                        child: KeyedSubtree(
                          key: ValueKey(widget.slides[i].key),
                          child: widget.slides[i].build(!widget.saver || i == _index),
                        ),
                      ),
                    ),
                  ),
                ),
                ),
              ),
              // in its own row under the shown card, left-aligned with its text: never on the image or the CTA; a
              // screen reader swipes up / down to step through
              Positioned(
                left: box.maxWidth * (1 - _fraction) / 2 + _gap + Space.gutter,
                bottom: 0,
                child: Semantics(
                  label: 'Slide ${_index + 1} of $_count',
                  onIncrease: () => _step(1),
                  onDecrease: () => _step(-1),
                  excludeSemantics: true,
                  child: AnimatedBuilder(
                    animation: _fill,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _count; i++)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _goTo(i),
                            child: SizedBox(
                              width: dots ? 24 : 28,
                              height: _barRow, // the touch target; the bar itself is 3 dp
                              child: Center(
                                child: dots
                                    ? DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: i == _index ? 1 : 0.4),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const SizedBox.square(dimension: 6),
                                      )
                                    : DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                        child: SizedBox(
                                          width: 22,
                                          height: 3,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: FractionallySizedBox(
                                              widthFactor: i < _index ? 1 : (i == _index ? _fill.value : 0),
                                              child: const DecoratedBox(
                                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(2))),
                                                child: SizedBox(height: 3),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A product as a sales banner: [kicker] (or the time left), its name, price against the MRP with the saving, and Buy
/// now; the product cut out, big and tilted, on the right. The whole card opens it.
class _ProductSlide extends ConsumerWidget {
  const _ProductSlide(this.card, {this.photo = true, this.kicker = 'FEATURED', this.endsAt});

  final ProductCard card;
  final bool photo; // false for the invisible sizing copies in data-saver mode: same size, nothing downloaded
  final String kicker;
  final DateTime? endsAt; // a countdown replaces the kicker

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final save = slideFacts(card).savePaise;
    return HeroCard(
      tone: heroTone(seedHash(card.id)),
      kicker: kicker,
      endsAt: endsAt,
      title: card.name,
      cta: 'Buy now',
      onCta: () => _buyNow(context, ref, card),
      onTap: () => context.push('/product/${card.slug}'),
      price: (
        price: formatInr(card.minPricePaise),
        mrp: card.mrpPaise > card.minPricePaise ? formatInr(card.mrpPaise) : null,
        save: save > 0 ? 'Save ${formatInr(save)}' : null,
      ),
      visual: HeroVisual(items: [(path: card.coverPath, opacity: 1.0)], photo: photo, icon: PhosphorIconsFill.deviceMobile),
      semanticsLabel: heroLabel(kicker.toUpperCase() == 'FEATURED' ? 'Product' : kicker[0] + kicker.substring(1).toLowerCase(), card.name, 'Buy now',
          endsAt: endsAt, detail: formatInr(card.minPricePaise)),
    );
  }
}

bool _buying = false; // a second tap while the first is still adding does nothing

/// Buy now from a banner: the default in-stock option into the cart, then checkout. Signed out, sign-in first and
/// back to the product page, which finishes the buy ("?buy="). Anything to pick (sold out, made to order) opens the
/// product instead.
Future<void> _buyNow(BuildContext context, WidgetRef ref, ProductCard card) async {
  if (_buying) return;
  _buying = true;
  try {
    final product = await ref.read(productProvider(card.slug).future);
    final v = initialVariant(product?.activeVariants ?? const []);
    if (!context.mounted) return;
    if (v == null || !v.inStock || v.madeToOrder) {
      unawaited(context.push('/product/${card.slug}'));
    } else if (ref.read(currentUserIdProvider) == null) {
      unawaited(context.push('/sign-in?from=${Uri.encodeComponent('/product/${card.slug}?buy=${v.id}')}'));
    } else {
      if (!(await ref.read(cartProvider.future)).any((l) => l.variant.id == v.id)) {
        await ref.read(cartProvider.notifier).add(v);
      }
      if (context.mounted) unawaited(context.push('/checkout'));
    }
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e));
  } finally {
    _buying = false;
  }
}

/// Short label and icon per category; its colours are fixed ([categoryTint]).
const _categoryLooks = {
  'smartphones': ('Phones', PhosphorIconsRegular.deviceMobile),
  'keypad-phones': ('Keypad', PhosphorIconsRegular.deviceMobileSpeaker),
  'cases-covers': ('Cases', PhosphorIconsRegular.deviceMobileCamera),
  'screen-guards': ('Guards', PhosphorIconsRegular.shieldCheck),
  'chargers-cables': ('Chargers', PhosphorIconsRegular.plugCharging),
  'earbuds-headphones': ('Earbuds', PhosphorIconsRegular.headphones),
  'power-banks': ('Power bank', PhosphorIconsRegular.batteryCharging),
};

/// The categories as even tiles, four to a row, All first, so none is cut off at the screen's edge. Repairs has its
/// own tab and strip.
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
          tint: categoryTint(cat.slug),
          onTap: () => context.go('/search?category=${cat.slug}'),
        ),
    ];
    const perRow = 4;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter - Space.xs, Space.lg, Space.gutter - Space.xs, 0),
      child: Column(
        spacing: Space.sm,
        children: [
          for (var i = 0; i < tiles.length; i += perRow)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = i; j < i + perRow; j++) Expanded(child: j < tiles.length ? tiles[j] : const SizedBox()),
              ],
            ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label, required this.icon, required this.onTap, this.tint});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Tint? tint; // background and icon; null is the neutral All tile

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
                child: SizedBox.square(dimension: 52, child: Icon(icon, size: IconSizes.lg, color: tint?.$2 ?? c.primary)),
              ),
              const SizedBox(height: Space.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2, // "Power bank" wraps at large text instead of ending in "Power ba…"
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one repair entry on Home's first screens: two lines on cream, "Book free" in saffron.
class _RepairStrip extends StatelessWidget {
  const _RepairStrip();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
      child: Material(
        color: BrandColors.cream,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: InkWell(
          onTap: () => context.push('/repairs/new'),
          borderRadius: BorderRadius.circular(Radii.lg),
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Row(
              children: [
                const IconWell(PhosphorIconsFill.wrench, tint: (Colors.white, BrandColors.saffron), size: 40),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Phone repair at our shop', style: t.titleSmall?.copyWith(color: BrandColors.creamInk)),
                      Text('Screen, battery, charging port · You approve the price first',
                          style: t.bodySmall?.copyWith(color: BrandColors.creamInk)),
                      const SizedBox(height: Space.sm),
                      Row(
                        spacing: Space.xs,
                        children: [
                          Text('Book free', style: t.labelLarge?.copyWith(color: BrandColors.saffron)),
                          const Icon(PhosphorIconsBold.arrowRight, size: IconSizes.sm, color: BrandColors.saffron),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Why buy here, in one row under the carousel: what the shop promises, from its settings. Tap for the details.
class _TrustStrip extends StatelessWidget {
  const _TrustStrip(this.settings);

  final StoreSettings settings;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final free = s.freeDeliveryMinPaise == 0 || s.deliveryFeePaise == 0
        ? 'Free delivery'
        : 'Free delivery over ${formatInr(s.freeDeliveryMinPaise)}';
    final items = [
      (PhosphorIconsRegular.sealCheck, 'Genuine products'),
      if (s.codEnabled) (PhosphorIconsRegular.money, 'Cash on delivery'),
      (PhosphorIconsRegular.truck, free),
    ];
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter - Space.sm, Space.md, Space.gutter - Space.sm, 0),
      child: Semantics(
        button: true,
        label: '${items.map((i) => i.$2).join(', ')}. Why buy from us',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => showWhyBuySheet(context, s),
          borderRadius: BorderRadius.circular(Radii.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                for (final (icon, label) in items)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                      child: Row(
                        children: [
                          Icon(icon, size: IconSizes.md, color: BrandColors.peacock),
                          const SizedBox(width: Space.xs),
                          Expanded(
                            child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: t.labelSmall?.copyWith(height: 1.2)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Why buy from us": the promises behind the trust strip, each from the shop's real settings.
Future<void> showWhyBuySheet(BuildContext context, StoreSettings s) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final t = Theme.of(context).textTheme;
        Widget row(IconData icon, String text, {Widget? trailing}) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: IconWell(icon, tint: Worlds.shop),
              title: Text(text, style: t.bodyMedium),
              trailing: trailing,
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Why buy from us', style: t.displaySmall?.copyWith(fontSize: 22)),
                const SizedBox(height: Space.sm),
                row(PhosphorIconsRegular.sealCheck, 'Genuine, sealed-box products'),
                row(PhosphorIconsRegular.deviceMobile, 'IMEI shown on your order: check it with *#06#'),
                if (s.codEnabled) row(PhosphorIconsRegular.money, 'Cash on delivery up to ${formatInr(s.codMaxPaise)}'),
                row(PhosphorIconsRegular.receipt, 'No platform, COD or packing fees'),
                row(PhosphorIconsRegular.certificate, 'GST-registered shop'),
                if (s.storeAddress.isNotEmpty)
                  row(
                    PhosphorIconsRegular.storefront,
                    'A real shop: ${s.storeAddress}',
                    trailing: s.mapsDestination.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Directions to the shop',
                            icon: const Icon(PhosphorIconsRegular.navigationArrow),
                            onPressed: () => openUri(context, directionsUri(s.mapsDestination)),
                          ),
                  ),
              ],
            ),
          ),
        );
      },
    );

/// "Shop by budget": phone price bands, each opening the phones in it.
class _BudgetRow extends StatelessWidget {
  const _BudgetRow(this.category);

  final String category;

  static const _bands = [
    ('Under ₹10,000', 'max=1000000'),
    ('Under ₹15,000', 'max=1500000'),
    ('Under ₹25,000', 'max=2500000'),
    ('Above ₹25,000', 'min=2500000'),
  ];

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Shop by budget', gutter: Space.gutter),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Row(
              spacing: Space.sm,
              children: [
                for (final (label, q) in _bands)
                  ActionChip(label: Text(label), onPressed: () => context.go('/search?category=$category&$q')),
              ],
            ),
          ),
        ],
      );
}

/// "Shop by brand": every brand as a chip, phone brands first. Hidden until the brands load.
class _BrandRow extends ConsumerWidget {
  const _BrandRow(this.phones);

  final List<ProductCard> phones; // their brands go first

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brands = ref.watch(brandsProvider).value ?? const <Brand>[];
    if (brands.isEmpty) return const SizedBox.shrink();
    final phoneBrands = {for (final p in phones) p.brandName};
    final sorted = [
      ...brands.where((b) => phoneBrands.contains(b.name)),
      ...brands.where((b) => !phoneBrands.contains(b.name)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Shop by brand', gutter: Space.gutter),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Row(
            spacing: Space.sm,
            children: [
              for (final b in sorted)
                ActionChip(label: Text(b.name), onPressed: () => context.go('/search?brand=${b.slug}')),
            ],
          ),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.section, Space.gutter, 0),
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
                        Text('Visit the shop', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text(details, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (settings.mapsDestination.isNotEmpty)
                    IconButton(
                      tooltip: 'Directions to the shop',
                      icon: const Icon(PhosphorIconsRegular.navigationArrow),
                      onPressed: () => openUri(context, directionsUri(settings.mapsDestination)),
                    ),
                  IconButton(
                    tooltip: 'WhatsApp the shop',
                    icon: const WhatsAppIcon(),
                    onPressed: () => openUri(context, whatsAppUri(settings.storePhone)),
                  ),
                ],
              ),
            ),
            FollowButtons(settings),
            if (listing != null)
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xs),
                minLeadingWidth: 24,
                horizontalTitleGap: Space.md,
                leading: const Icon(PhosphorIconsRegular.mapTrifold),
                title: const Text('Photos, reviews & hours on Google Maps'),
                trailing: const Icon(PhosphorIconsRegular.arrowSquareOut, size: 18),
                onTap: () => openUri(context, listing),
              ),
          ],
        ),
      ),
    );
  }
}
