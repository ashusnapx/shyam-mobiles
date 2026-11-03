import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/widgets.dart';
import '../../cart/data/cart.dart';
import '../../cart/widgets/cart_button.dart';
import '../../feedback/widgets/feedback_widgets.dart';
import '../../offers/data/offers.dart';
import '../../offers/widgets/offer_widgets.dart';
import '../../payments/widgets/emi_line.dart';
import '../data/best_offer.dart';
import '../data/catalog.dart';
import '../data/rails.dart';
import '../data/variant_options.dart';
import '../widgets/gallery.dart';
import '../widgets/product_rail.dart';
import '../widgets/product_tile.dart';

const _specIcons = [
  (['display', 'screen'], PhosphorIconsRegular.deviceMobile),
  (['processor', 'chip', 'cpu'], PhosphorIconsRegular.cpu),
  (['camera'], PhosphorIconsRegular.camera),
  (['battery', 'playback'], PhosphorIconsRegular.batteryHigh),
  (['software', 'os'], PhosphorIconsRegular.gearSix),
  (['capacity'], PhosphorIconsRegular.batteryCharging),
  (['output', 'charging', 'port', 'cable'], PhosphorIconsRegular.plugCharging),
  (['fits', 'compatib'], PhosphorIconsRegular.deviceMobileCamera),
  (['water', 'protection', 'hardness'], PhosphorIconsRegular.shieldCheck),
  (['material'], PhosphorIconsRegular.cube),
  (['in the box'], PhosphorIconsRegular.package),
  (['weight'], PhosphorIconsRegular.scales),
  (['driver', 'audio', 'speaker', 'sound'], PhosphorIconsRegular.speakerHigh),
  (['call', 'mic'], PhosphorIconsRegular.phoneCall),
  (['storage', 'memory', 'ram'], PhosphorIconsRegular.hardDrives),
];

IconData specIcon(String label) {
  final l = label.toLowerCase();
  for (final (words, icon) in _specIcons) {
    if (words.any(l.contains)) return icon;
  }
  return PhosphorIconsRegular.info;
}

Color? _hexColor(String? hex) => hex != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)
    ? Color(0xFF000000 | int.parse(hex.substring(1), radix: 16))
    : null;

final _fakeProduct = Product(
  id: '',
  slug: '',
  name: 'Brand Phone name 5G',
  brand: const Brand(id: '', slug: '', name: 'Brand'),
  category: const Category(id: '', slug: '', name: 'Phones', kind: CategoryKind.phone),
  specs: [for (final l in ['Display', 'Processor', 'Camera', 'Battery']) Spec(l, 'Loading the details')],
  variants: const [
    Variant(id: 'a', productId: '', sku: '', name: '', pricePaise: 2499900, mrpPaise: 2799900, stock: 9,
        attributes: {'ram': '8 GB', 'storage': '128 GB', 'color': 'Black'}),
    Variant(id: 'b', productId: '', sku: '', name: '', pricePaise: 2699900, mrpPaise: 2999900, stock: 9,
        attributes: {'ram': '8 GB', 'storage': '256 GB', 'color': 'White'}),
  ],
);

class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  String? _variantId; // the shopper's pick; until then the cheapest in-stock variant
  bool _zoomed = false; // a gallery photo is zoomed in: one-finger drags pan it instead of scrolling the page
  bool _busy = false;
  bool _scrolled = false; // past the gallery: the top bar turns solid and shows the name
  bool _readRoute = false;
  bool _allSpecs = false; // "Show all N specs" tapped
  ({bool buy, String variantId})? _resume; // add/buy to finish after the sign-in round trip

  @override
  void initState() {
    super.initState();
    // for Home's "Recently viewed"
    ref.listenManual(productProvider(widget.slug), (_, next) {
      if (next.value case final p?) ref.read(recentlyViewedProvider.notifier).add(p.id);
    }, fireImmediately: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_readRoute) return;
    _readRoute = true;
    final qp = GoRouterState.of(context).uri.queryParameters;
    final id = qp['buy'] ?? qp['add'];
    if (id != null) _resume = (buy: qp['buy'] != null, variantId: id);
  }

  /// Runs a pending add/buy exactly once, when signed in and the product is loaded, then drops the query param.
  void _maybeResume(List<Variant> variants) {
    final resume = _resume;
    if (resume == null || variants.isEmpty || ref.read(currentUserIdProvider) == null) return;
    _resume = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.replace('/product/${widget.slug}'); // same page key: this state survives
      final v = variants.where((v) => v.id == resume.variantId).firstOrNull;
      if (v == null) return;
      setState(() => _variantId = v.id);
      _add(v, buy: resume.buy);
    });
  }

  Future<void> _add(Variant v, {required bool buy}) async {
    final router = GoRouter.of(context);
    if (ref.read(currentUserIdProvider) == null) {
      final back = '/product/${widget.slug}?${buy ? 'buy' : 'add'}=${v.id}';
      unawaited(router.push('/sign-in?from=${Uri.encodeComponent(back)}'));
      return;
    }
    if (!v.inStock) {
      showMessage(context, 'This one just sold out. Pick another option.');
      return;
    }
    setState(() => _busy = true);
    try {
      // load the cart first: add() computes the new qty from what's already there
      final lines = await ref.read(cartProvider.future);
      final inCart = lines.where((l) => l.variant.id == v.id).firstOrNull?.qty ?? 0;
      if (inCart >= maxQtyFor(v)) {
        if (buy) {
          unawaited(router.push('/checkout'));
        } else if (mounted) {
          showMessage(context, 'You already have the most you can buy of this.');
        }
        return;
      }
      await ref.read(cartProvider.notifier).add(v);
      unawaited(HapticFeedback.mediumImpact());
      if (buy) {
        unawaited(router.push('/checkout'));
      } else if (mounted) {
        showMessage(context, 'Added to cart', action: SnackBarAction(label: 'View cart', onPressed: () => router.go('/cart')));
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final async = ref.watch(productProvider(widget.slug));
    final product = async.value;
    final variants = product?.activeVariants ?? const <Variant>[];
    final variant = variants.where((v) => v.id == _variantId).firstOrNull ?? initialVariant(variants);
    final canBuy = variant != null && variant.inStock && !_busy;
    final alternative = variant == null ? null : inStockAlternative(variants, variant);
    final settings = ref.watch(storeSettingsProvider).value;
    ref.watch(currentUserIdProvider); // rebuild on sign-in so a pending add/buy can resume
    _maybeResume(variants);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0, // its own solid layer below
        // solid once the photos scroll away, so the page never runs under the buttons
        flexibleSpace: AnimatedOpacity(
          opacity: _scrolled ? 1 : 0,
          duration: Motion.fast,
          // expand: a childless DecoratedBox in the app bar's stack sizes to zero height and paints nothing
          child: SizedBox.expand(
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.outlineVariant))),
            ),
          ),
        ),
        title: _scrolled && product != null
            ? Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))
            : null,
        systemOverlayStyle: Theme.of(context).brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back',
          style: IconButton.styleFrom(backgroundColor: c.surface),
          icon: const Icon(PhosphorIconsRegular.arrowLeft, size: 20),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: [
          if (product != null) ...[
            ShareButton(
              what: '${product.name}${variant == null ? '' : ' · ${formatInr(variant.pricePaise)}'} at Shyam Mobiles',
              product: product.slug,
              style: IconButton.styleFrom(backgroundColor: c.surface),
            ),
            HeartButton(product.id),
          ],
          CartButton(style: IconButton.styleFrom(backgroundColor: c.surface)),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: switch (async) {
        AsyncValue(value: final p?) when variant != null => NotificationListener<ScrollUpdateNotification>(
            onNotification: (n) {
              if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
                // solid before the page reaches the bar's bottom edge (status bar included)
                final bar = kToolbarHeight + MediaQuery.paddingOf(context).top;
                final past = n.metrics.pixels > MediaQuery.sizeOf(context).width - bar;
                if (past != _scrolled) setState(() => _scrolled = past);
              }
              return false;
            },
            child: _details(p, variants, variant),
          ),
        AsyncValue(hasValue: true) => EmptyState(
            icon: PhosphorIconsRegular.smileySad,
            title: 'This product isn’t available',
            message: 'It may have been removed. Have a look at what’s in stock.',
            action: FilledButton.icon(
              onPressed: () => context.go('/search?category=smartphones'),
              icon: const Icon(PhosphorIconsRegular.storefront),
              label: const Text('Shop phones'),
            ),
          ),
        AsyncValue(:final error?) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(productProvider(widget.slug)),
          ),
        _ => Skeletonizer(child: _details(_fakeProduct, _fakeProduct.variants, _fakeProduct.variants.first)),
      },
      bottomNavigationBar: variant == null || product == null
          ? null
          : StickyBar(
              child: variant.inStock
                  ? Row(
                      spacing: Space.sm,
                      children: [
                        if (settings != null)
                          IconButton.outlined(
                            tooltip: 'Ask on WhatsApp',
                            style: IconButton.styleFrom(
                              minimumSize: const Size(48, 52),
                              side: BorderSide(color: c.outline),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button)),
                            ),
                            onPressed: () => openUri(
                              context,
                              whatsAppUri(settings.storePhone, text: 'Hi, I’m interested in ${product.name} (${variant.name})'),
                            ),
                            icon: const WhatsAppIcon(),
                          ),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: canBuy ? () => _add(variant, buy: false) : null,
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.sm)),
                            child: const Text('Add to cart', maxLines: 1),
                          ),
                        ),
                        Expanded(
                          child: FilledButton(
                            onPressed: canBuy ? () => _add(variant, buy: true) : null,
                            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.sm)),
                            child: const Text('Buy now', maxLines: 1),
                          ),
                        ),
                      ],
                    )
                  : _SoldOutBar(
                      item: '${product.name} (${variant.name})',
                      variant: variant,
                      alternative: alternative,
                      onSwitch: alternative == null ? null : () => setState(() => _variantId = alternative.id),
                    ),
            ),
    );
  }

  Widget _details(Product p, List<Variant> variants, Variant v) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final settings = ref.watch(storeSettingsProvider).value;
    final memories = memoryOptions(variants);
    final colors = colorOptions(variants);
    final muted = t.bodySmall?.copyWith(color: c.onSurfaceVariant);
    final phone = p.category.kind == CategoryKind.phone;
    final item = '${p.name} (${v.name})';
    Widget label(String text, [String? value]) => Padding(
          padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm),
          child: Text.rich(
            TextSpan(text: text, children: [
              if (value != null) TextSpan(text: ' · $value', style: TextStyle(color: c.onSurfaceVariant, fontWeight: FontWeight.w500)),
            ]),
            style: t.labelMedium,
          ),
        );
    void pick({String? memory, String? color}) => setState(() {
          _variantId = pickVariant(variants, v, memory: memory, color: color).id;
          _zoomed = false; // the gallery starts over on the new colour's photos
        });
    const side = EdgeInsets.symmetric(horizontal: Space.lg);
    final specs = _allSpecs ? p.specs : p.specs.take(6).toList();

    return ListView(
      padding: EdgeInsets.zero,
      physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
      children: [
        ProductGallery(
          paths: [for (final i in photosFor(p.images, colorOf(v))) i.path],
          onZoom: (zoomed) => setState(() => _zoomed = zoomed),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      // the brand opens everything it makes
                      child: InkWell(
                        onTap: p.brand.slug.isEmpty ? null : () => context.go('/search?brand=${p.brand.slug}'),
                        borderRadius: BorderRadius.circular(Radii.sm),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  p.brand.name.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.labelMedium
                                      ?.copyWith(color: c.onSurfaceVariant, letterSpacing: 0.8, fontWeight: FontWeight.w700),
                                ),
                              ),
                              Icon(PhosphorIconsBold.caretRight, size: IconSizes.xs, color: c.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!v.inStock)
                    const Tag('Out of stock', tone: TagTone.neutral)
                  else if (v.stock <= 3)
                    Tag('Only ${v.stock} left', tone: TagTone.deal)
                  else
                    const Tag('In stock', tone: TagTone.ok, icon: PhosphorIconsBold.check),
                ],
              ),
              Text(p.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: Space.sm),
              PriceTag(pricePaise: v.pricePaise, mrpPaise: v.mrpPaise, large: true, showSaving: true),
              EmiLine(pricePaise: v.pricePaise), // "EMI from ₹X/month"; nothing when EMI doesn't apply
              const SizedBox(height: 2),
              Text('Inclusive of all taxes', style: muted),
              // the pick sets the price above and the offer below
              if (memories.isNotEmpty) ...[
                label('Memory & storage'),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final o in memories)
                      ChoiceChip(
                        showCheckmark: false,
                        // selected = solid ink with white text, as everywhere else (the theme's chip style)
                        selected: memoryOf(v) == o.label,
                        label: Text.rich(TextSpan(text: o.label, children: [
                          if (o.deltaPaise > 0 || !o.available)
                            TextSpan(
                              text: o.available ? '  +${formatInr(o.deltaPaise)}' : '  Sold out',
                              style: TextStyle(
                                color: memoryOf(v) == o.label ? c.onPrimary.withValues(alpha: 0.8) : c.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ])),
                        // sold out is still a tap away: its photos and price show, the bar says it's out of stock
                        onSelected: (_) => pick(memory: o.label),
                      ),
                  ],
                ),
              ],
              if (colors.isNotEmpty) ...[
                label('Colour', colorOf(v).isEmpty ? null : colorOf(v)),
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  children: [
                    for (final o in colors)
                      _Swatch(option: o, selected: colorOf(v) == o.label, onTap: () => pick(color: o.label)),
                  ],
                ),
              ],
              if (p.id.isNotEmpty) _BestOffer(productId: p.id, pricePaise: v.pricePaise),
              if (settings != null) ...[
                const SizedBox(height: Space.md),
                _DeliveryCard(settings),
                const SectionHeader('Why buy from us', inset: false),
                _WhyBuy(settings: settings, product: p),
              ],
            ],
          ),
        ),
        if (p.id.isNotEmpty && phone)
          ProductRail(title: 'Fits this phone', band: sectionTints.fits, value: ref.watch(fitsProvider(p.slug))),
        Padding(
          padding: side,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.description.isNotEmpty) ...[
                SectionHeader(phone ? 'About this phone' : 'About this product', inset: false),
                _Description(p.description),
              ],
              if (p.specs.isNotEmpty) ...[
                const SectionHeader('Specifications', inset: false),
                for (final s in specs)
                  DecoratedBox(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: c.outlineVariant))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(specIcon(s.label), size: IconSizes.md, color: c.onSurfaceVariant),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.label, style: t.titleSmall),
                                Text(s.value, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (p.specs.length > specs.length)
                  TextButton.icon(
                    onPressed: () => setState(() => _allSpecs = true),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(PhosphorIconsBold.caretDown, size: 14),
                    label: Text('Show all ${p.specs.length} specs'),
                  ),
              ],
              if (settings != null) ...[
                const SizedBox(height: Space.lg),
                _StoreRows(settings: settings, item: item),
              ],
            ],
          ),
        ),
        if (p.id.isNotEmpty)
          ProductRail(title: 'Similar products', band: sectionTints.similar, value: ref.watch(similarProvider(p.slug))),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
          child: p.id.isEmpty ? const SizedBox.shrink() : ReportListingLink(productId: p.id),
        ),
      ],
    );
  }
}

/// The description, with lines that start with "• " as a bulleted list.
class _Description extends StatelessWidget {
  const _Description(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.xs,
      children: [
        for (final line in text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty))
          if (line.startsWith('• '))
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: style),
                Expanded(child: Text(line.substring(2), style: style)),
              ],
            )
          else
            Text(line, style: style),
      ],
    );
  }
}

/// One line for the offer that saves the most on this pick, with the price after it, then "+N more offers".
/// Running offers that cover this product come from `offers_for_product`.
class _BestOffer extends ConsumerWidget {
  const _BestOffer({required this.productId, required this.pricePaise});

  final String productId;
  final int pricePaise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(productOffersProvider(productId)).value ?? const <Offer>[];
    if (offers.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final best = bestOffer(offers, pricePaise);
    final o = best?.offer ?? offers.first;
    final (bg, fg) = Worlds.offers;
    final line = [
      if (best == null)
        o.code == null ? '${offerHeadline(o)} · ${o.title}' : '${offerHeadline(o)} with code ${o.code}'
      else if (o.code == null)
        'Pay ${formatInr(pricePaise - best.saving)} at checkout'
      else
        'Pay ${formatInr(pricePaise - best.saving)} with code ${o.code}',
      if (best != null && o.code == null) ...[o.title, 'No code needed'],
      if (o.onlineOnly) 'Pay online',
      if (o.firstOrderOnly) 'First order',
      if (o.endsAt != null) 'Ends ${DateFormat('d MMM').format(o.endsAt!.toLocal())}',
    ];
    final more = offers.length - 1;
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.lg),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => context.push('/offers/${o.id}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.xs, Space.md),
                child: Row(
                  children: [
                    Icon(PhosphorIconsFill.sealPercent, size: IconSizes.lg, color: fg),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: line.first, style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (line.length > 1) TextSpan(text: ' · ${line.skip(1).join(' · ')}'),
                        ]),
                        style: t.bodyMedium?.copyWith(color: BrandColors.ink),
                      ),
                    ),
                    if (o.code != null)
                      TextButton(
                        onPressed: () => copyCode(context, o.code!),
                        style: TextButton.styleFrom(foregroundColor: fg),
                        child: const Text('Copy code'),
                      ),
                  ],
                ),
              ),
            ),
            if (more > 0) ...[
              Divider(height: 1, color: fg.withValues(alpha: 0.15)),
              InkWell(
                onTap: () => context.push('/offers'),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('+$more more offer${more == 1 ? '' : 's'}',
                              style: t.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                        ),
                        Icon(PhosphorIconsBold.caretRight, size: IconSizes.sm, color: fg),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A colour to pick. A sold-out colour keeps its colour, softened and struck through, and can still be picked to
/// see its photos and price.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.option, required this.selected, required this.onTap});

  final ColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final soldOut = !option.available;
    return Semantics(
      label: soldOut ? '${option.label}, sold out' : option.label,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: selected ? Border.all(color: c.primary, width: 2) : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: soldOut ? 0.55 : 1,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _hexColor(option.hex) ?? c.surfaceContainerHighest,
                        border: Border.all(color: c.onSurface.withValues(alpha: 0.12)),
                      ),
                    ),
                  ),
                  if (soldOut)
                    Transform.rotate(angle: -0.785, child: Container(width: 34, height: 2, color: c.onSurface)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sticky bar for a sold-out pick: says so instead of Add to cart / Buy now, and offers the nearest one in stock,
/// or a WhatsApp message asking to hear when it's back.
class _SoldOutBar extends ConsumerWidget {
  const _SoldOutBar({required this.item, required this.variant, required this.alternative, required this.onSwitch});

  final String item; // "Samsung Galaxy S25 (12 GB · 256 GB · Navy)"
  final Variant variant;
  final Variant? alternative;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final alt = alternative;
    final phone = ref.watch(storeSettingsProvider).value?.storePhone;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(PhosphorIconsRegular.prohibit, size: IconSizes.md, color: c.onSurfaceVariant),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text.rich(
                  const TextSpan(children: [
                    TextSpan(text: 'Out of stock', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' · this one is sold out right now.'),
                  ]),
                  style: t.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        if (alt != null)
          FilledButton(onPressed: onSwitch, child: Text('See ${switchLabel(alt, variant)} in stock'))
        else
          FilledButton.icon(
            onPressed: phone == null
                ? null
                : () => openUri(context, whatsAppUri(phone, text: 'Hi, please tell me when $item is back in stock.')),
            style: FilledButton.styleFrom(backgroundColor: BrandColors.whatsapp, foregroundColor: BrandColors.ink),
            icon: const Icon(PhosphorIconsFill.whatsappLogo),
            label: const Text('Ask on WhatsApp when it’s back'),
          ),
      ],
    );
  }
}

/// Follows "Free delivery". Same rules as `place_order`: free at or above the threshold (inclusive), COD up to
/// the limit on the total including delivery.
String deliveryTerms(StoreSettings s) => [
      s.freeDeliveryMinPaise == 0 || s.deliveryFeePaise == 0
          ? ' on every order'
          : ' on orders of ${formatInr(s.freeDeliveryMinPaise)} or more',
      if (s.codEnabled) ' · Cash on delivery up to ${formatInr(s.codMaxPaise)}',
    ].join();

/// Free delivery and cash on delivery, on mint: good news about money.
class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard(this.s);

  final StoreSettings s;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: BrandColors.mint, borderRadius: BorderRadius.circular(Radii.lg)),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              const Icon(PhosphorIconsRegular.truck, size: IconSizes.lg, color: BrandColors.emerald),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(
                      text: 'Free delivery',
                      style: TextStyle(color: BrandColors.mintInk, fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: deliveryTerms(s)),
                  ]),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: BrandColors.ink),
                ),
              ),
            ],
          ),
        ),
      );
}

/// "Why buy from us": genuine (and the IMEI check, for a phone), the warranty from the specs, the policy, the shop.
class _WhyBuy extends StatelessWidget {
  const _WhyBuy({required this.settings, required this.product});

  final StoreSettings settings;
  final Product product;

  @override
  Widget build(BuildContext context) {
    const chevron = Icon(PhosphorIconsBold.caretRight, size: IconSizes.sm);
    final warranty = product.specs.where((s) => s.label.toLowerCase() == 'warranty').firstOrNull?.value;
    final rows = [
      ListTile(
        leading: const IconWell(PhosphorIconsRegular.sealCheck, tint: Worlds.shop),
        title: const Text('Genuine and sealed'),
        subtitle: product.category.kind == CategoryKind.phone
            ? const Text('Check the IMEI with *#06# when it arrives')
            : null,
      ),
      const ListTile(
        leading: IconWell(PhosphorIconsRegular.certificate, tint: Worlds.shop),
        title: Text('GST-registered shop'),
      ),
      if (warranty != null && warranty.isNotEmpty)
        ListTile(
          leading: const IconWell(PhosphorIconsRegular.shieldCheck, tint: Worlds.shop),
          title: Text('Warranty: $warranty'),
        ),
      if (settings.returnsPolicy.isNotEmpty)
        ListTile(
          leading: const IconWell(PhosphorIconsRegular.arrowUUpLeft, tint: Worlds.shop),
          title: const Text('Returns & warranty policy'),
          trailing: chevron,
          onTap: () => showReturnsSheet(context, settings),
        ),
      if (settings.mapsDestination.isNotEmpty)
        ListTile(
          leading: const IconWell(PhosphorIconsRegular.storefront, tint: Worlds.shop),
          title: const Text('See it at our shop'),
          subtitle: settings.storeAddress.isEmpty ? null : Text(settings.storeAddress, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: chevron,
          onTap: () => openUri(context, directionsUri(settings.mapsDestination)),
        ),
    ];
    return Card(
      child: Column(
        children: [
          for (final (i, r) in rows.indexed) ...[if (i > 0) const Divider(), r],
        ],
      ),
    );
  }
}

/// "Ask on WhatsApp" (prefilled with the product and variant) and a wholesale enquiry: the shop sells wholesale too,
/// and dealers ask for bulk prices over WhatsApp.
class _StoreRows extends StatelessWidget {
  const _StoreRows({required this.settings, required this.item});

  final StoreSettings settings;
  final String item; // "Samsung Galaxy S25 (12 GB · 256 GB · Navy)"

  Future<void> _askBulk(BuildContext context) async {
    final qty = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (context) => const _BulkSheet(),
    );
    if (qty == null || !context.mounted) return;
    await openUri(context, whatsAppUri(settings.storePhone, text: 'Hi, I’d like your wholesale price for $qty+ units of $item.'));
  }

  @override
  Widget build(BuildContext context) {
    const chevron = Icon(PhosphorIconsBold.caretRight, size: IconSizes.sm);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const SizedBox.square(dimension: 36, child: Center(child: WhatsAppIcon(size: 24))),
            title: const Text('Ask on WhatsApp'),
            subtitle: const Text('Price, colours, stock: we reply during shop hours'),
            trailing: chevron,
            onTap: () => openUri(context, whatsAppUri(settings.storePhone, text: 'Hi, I’m interested in $item')),
          ),
          const Divider(),
          ListTile(
            leading: const IconWell(PhosphorIconsRegular.package, tint: Worlds.admin),
            title: const Text('Buying 10 or more?'),
            subtitle: const Text('Ask for our wholesale price'),
            trailing: chevron,
            onTap: () => _askBulk(context),
          ),
        ],
      ),
    );
  }
}

/// Picks a quantity for a wholesale enquiry; pops with it.
class _BulkSheet extends StatefulWidget {
  const _BulkSheet();

  @override
  State<_BulkSheet> createState() => _BulkSheetState();
}

class _BulkSheetState extends State<_BulkSheet> {
  static const _options = [10, 25, 50, 100, 200];
  int _qty = 10;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Wholesale enquiry', style: t.titleLarge),
          const SizedBox(height: Space.xs),
          Text('How many units? We’ll reply on WhatsApp with our best price.',
              style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final q in _options)
                ChoiceChip(label: Text('$q+'), selected: _qty == q, onSelected: (_) => setState(() => _qty = q)),
            ],
          ),
          const SizedBox(height: Space.xl),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _qty),
            icon: const WhatsAppIcon(size: 20),
            label: const Text('Send on WhatsApp'),
          ),
        ],
      ),
    );
  }
}
