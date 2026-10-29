import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/catalog.dart';
import '../widgets/product_tile.dart';
import '../widgets/store_links.dart';
import '../widgets/store_photos.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    ref.invalidate(categoriesProvider);
    ref.invalidate(storeSettingsProvider);
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
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(context, ref),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(key: const ValueKey('header'), child: _Header(settings)),
              const SliverToBoxAdapter(key: ValueKey('search'), child: _SearchField()),
              ...switch (home) {
                AsyncValue(value: final d?) => _sections(context, d, settings),
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
    );
  }

  List<Widget> _sections(BuildContext context, HomeData d, StoreSettings? settings) {
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
    return [
      if (d.featured.isNotEmpty)
        SliverToBoxAdapter(key: const ValueKey('hero'), child: _HeroCarousel(d.featured.take(6).toList())),
      SliverToBoxAdapter(key: const ValueKey('categories'), child: _CategoryGrid(d.categories)),
      const SliverToBoxAdapter(key: ValueKey('repair'), child: _RepairCta()),
      if (d.accessories.isNotEmpty) ...[
        const SliverToBoxAdapter(key: ValueKey('acc-header'), child: SectionHeader('Accessories under ₹1,500')),
        SliverProductGrid(d.accessories, key: const ValueKey('accessories')),
      ],
      if (settings != null) SliverToBoxAdapter(key: const ValueKey('store'), child: _StoreCard(settings)),
      const SliverPadding(key: ValueKey('end'), padding: EdgeInsets.only(bottom: Space.xl)),
    ];
  }

  static final _skeleton = Skeletonizer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Hero(fakeCards(1).first),
        _CategoryGrid([
          for (var i = 0; i < 6; i++)
            Category(id: '$i', slug: 'skeleton-$i', name: 'Category', kind: CategoryKind.accessory),
        ]),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.settings);

  final StoreSettings? settings;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final s = settings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, 0),
      child: Row(
        children: [
          const BrandMark(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shyam Mobiles', style: t.displaySmall?.copyWith(fontSize: 22, height: 1)),
                Text('Phones · Accessories · Repairs', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Call the store',
            icon: const Icon(PhosphorIconsRegular.phone),
            onPressed: s == null
                ? null
                : () => openExternal(context, Uri(scheme: 'tel', path: s.storePhone), 'Couldn’t open the dialer.'),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 14),
      child: Material(
        color: c.surfaceContainer,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          onTap: () => context.go('/search'),
          borderRadius: BorderRadius.circular(Radii.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
              child: Row(
                children: [
                  Icon(PhosphorIconsRegular.magnifyingGlass, size: 20, color: c.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Search phones, cases, chargers…', style: hint)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Featured products as a hero that slides to the next one every few seconds. Swipe to move; touching it
/// pauses it. Stays still with reduce-motion or TalkBack on, and while another tab is showing.
class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel(this.cards);

  final List<ProductCard> cards;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  static const _interval = Duration(milliseconds: 4500);
  int _index = 0;
  int _direction = 1;
  Timer? _timer;

  int get _count => widget.cards.length;

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
    if (_count < 2) return;
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted) return;
      final still = MediaQuery.disableAnimationsOf(context) || MediaQuery.accessibleNavigationOf(context);
      if (!still && TickerMode.valuesOf(context).enabled) _step(1);
    });
  }

  void _step(int by) => setState(() {
        _direction = by;
        _index = (_index + by + _count) % _count;
      });

  @override
  Widget build(BuildContext context) {
    if (_count == 1) return _Hero(widget.cards.first);
    final c = Theme.of(context).colorScheme;
    final card = widget.cards[_index];
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 500);
    return Column(
      children: [
        GestureDetector(
          onHorizontalDragStart: (_) => _timer?.cancel(),
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() > 150) _step(v < 0 ? 1 : -1);
            _restart();
          },
          onHorizontalDragCancel: _restart,
          child: AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
              transitionBuilder: (child, animation) {
                final incoming = child.key == ValueKey(card.id);
                final from = Offset((incoming ? 0.14 : -0.14) * _direction, 0);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(begin: from, end: Offset.zero).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _Hero(card, key: ValueKey(card.id)),
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        Semantics(
          label: 'Featured ${_index + 1} of $_count',
          excludeSemantics: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _count; i++)
                AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _index ? c.onSurface : c.outline,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero(this.card, {super.key});

  final ProductCard card;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final off = discountPercent(card.minPricePaise, card.mrpPaise);
    void open() => context.push('/product/${card.slug}');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: DecoratedBox(
          // the hero stays indigo in both themes, so its text is always white
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [BrandColors.graphite, Colors.black],
            ),
          ),
          child: CustomPaint(
            painter: const _FeatherPainter(),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: open,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FEATURED',
                              style: t.labelSmall?.copyWith(color: Colors.white70, letterSpacing: 1.3),
                            ),
                            const SizedBox(height: Space.sm),
                            Semantics(
                              header: true,
                              child: Text(
                                shortName(card.name, card.brandName),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: t.displayMedium?.copyWith(color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: Space.sm),
                            Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(text: 'From '),
                                  TextSpan(
                                    text: formatInr(card.minPricePaise),
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  if (off > 0) TextSpan(text: '  ·  $off% off MRP'),
                                ],
                              ),
                              style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: open,
                              iconAlignment: IconAlignment.end,
                              icon: const Icon(PhosphorIconsBold.arrowRight, size: 16),
                              label: Text(card.categorySlug == 'smartphones' ? 'View phone' : 'View'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: BrandColors.ink,
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                textStyle: t.labelMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      SizedBox(width: 108, child: ProductImage(card.coverPath, aspectRatio: 0.8, padding: Space.sm)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Peacock glow plus feather-eye rings behind the hero, as in the mockup.
class _FeatherPainter extends CustomPainter {
  const _FeatherPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Offset(size.width * 0.9, size.height * 0.3);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: glow, radius: size.width * 0.55)),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.07);
    final eye = Offset(size.width * 0.88, size.height * 0.62);
    for (var r = 16.0; r < size.width; r += 16) {
      canvas.drawOval(Rect.fromCenter(center: eye, width: r * 2.4, height: r * 2), ring);
    }
  }

  @override
  bool shouldRepaint(_FeatherPainter oldDelegate) => false;
}

const _categoryLooks = {
  'smartphones': ('Phones', PhosphorIconsRegular.deviceMobile),
  'keypad-phones': ('Keypad phones', PhosphorIconsRegular.deviceMobileSpeaker),
  'cases-covers': ('Cases', PhosphorIconsRegular.deviceMobileCamera),
  'screen-guards': ('Screen guards', PhosphorIconsRegular.shieldCheck),
  'chargers-cables': ('Chargers', PhosphorIconsRegular.plugCharging),
  'earbuds-headphones': ('Earbuds', PhosphorIconsRegular.headphones),
  'power-banks': ('Power banks', PhosphorIconsRegular.batteryCharging),
};

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid(this.categories);

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final cat in categories.take(6))
        _CategoryTile(
          label: _categoryLooks[cat.slug]?.$1 ?? cat.name,
          icon: _categoryLooks[cat.slug]?.$2 ?? PhosphorIconsRegular.tag,
          onTap: () => context.go('/search?category=${cat.slug}'),
        ),
      _CategoryTile(
        label: 'Repairs',
        icon: PhosphorIconsRegular.wrench,
        onTap: () => context.go('/repairs'),
        accent: true,
      ),
      _CategoryTile(label: 'All', icon: PhosphorIconsRegular.squaresFour, onTap: () => context.go('/search')),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, 18, Space.md, 0),
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i += 4)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (var j = i; j < i + 4; j++) Expanded(child: j < tiles.length ? tiles[j] : const SizedBox())],
            ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label, required this.icon, required this.onTap, this.accent = false});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool accent; // peacock tile for Repairs

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs + 2),
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: accent ? c.secondaryContainer : c.surfaceContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: SizedBox.square(
                dimension: 58,
                child: Icon(icon, size: 26, color: accent ? c.secondary : c.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11.5, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal strip of fixed-width tiles; a Row (not a ListView) so its height follows the text scale.
class _RepairCta extends StatelessWidget {
  const _RepairCta();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 22, Space.lg, 0),
      child: Material(
        color: c.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => context.push('/repairs/new'),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(c.secondary.withValues(alpha: 0.2), c.surface),
                    borderRadius: BorderRadius.circular(Radii.lg),
                  ),
                  child: SizedBox.square(
                    dimension: 52,
                    child: Icon(PhosphorIconsRegular.wrench, size: 26, color: c.secondary),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cracked screen? Weak battery?',
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: c.onSecondaryContainer),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pick a slot and walk in. You pay at the store after the inspection.',
                        style: t.bodySmall?.copyWith(color: c.onSecondaryContainer),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                Icon(PhosphorIconsBold.caretRight, size: 18, color: c.onSecondaryContainer),
              ],
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
