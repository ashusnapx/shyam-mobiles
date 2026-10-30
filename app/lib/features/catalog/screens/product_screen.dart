import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../cart/data/cart.dart';
import '../../cart/widgets/cart_button.dart';
import '../../feedback/widgets/feedback_widgets.dart';
import '../../offers/data/offers.dart';
import '../../offers/widgets/offer_widgets.dart';
import '../../payments/widgets/emi_line.dart';
import '../data/catalog.dart';
import '../data/rails.dart';
import '../data/variant_options.dart';
import '../widgets/gallery.dart';
import '../widgets/product_rail.dart';
import '../widgets/product_tile.dart';
import '../widgets/store_links.dart';

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
  bool _readRoute = false;
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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: const Text('Added to cart'),
            action: SnackBarAction(label: 'View cart', onPressed: () => router.go('/cart')),
          ));
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
    ref.watch(currentUserIdProvider); // rebuild on sign-in so a pending add/buy can resume
    _maybeResume(variants);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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
        AsyncValue(value: final p?) when variant != null => _details(p, variants, variant),
        AsyncValue(hasValue: true) => EmptyState(
            icon: PhosphorIconsRegular.smileySad,
            title: 'This product isn’t available',
            message: 'It may have been removed. Have a look at what’s in stock.',
            action: FilledButton(
              onPressed: () => context.go('/search?category=smartphones'),
              child: const Text('Browse phones'),
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
          : DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(top: BorderSide(color: c.outlineVariant)),
              ),
              // edge-to-edge: keeps the buttons above the gesture / nav bar
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
                  child: variant.inStock
                      ? Row(
                          spacing: 10,
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: canBuy ? () => _add(variant, buy: false) : null,
                                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.md)),
                                icon: const Icon(PhosphorIconsRegular.shoppingBag, size: 20),
                                label: const Text('Add to cart'),
                              ),
                            ),
                            Expanded(
                              child: FilledButton(
                                onPressed: canBuy ? () => _add(variant, buy: true) : null,
                                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.md)),
                                child: const Text('Buy now'),
                              ),
                            ),
                          ],
                        )
                      : _SoldOutBar(
                          variant: variant,
                          alternative: alternative,
                          onSwitch: alternative == null ? null : () => setState(() => _variantId = alternative.id),
                        ),
                ),
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
    Widget label(String text, [String? value]) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: Space.sm),
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

    return ListView(
      padding: EdgeInsets.zero,
      physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
      children: [
        ProductGallery(
          paths: [for (final i in photosFor(p.images, colorOf(v))) i.path],
          onZoom: (zoomed) => setState(() => _zoomed = zoomed),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.brand.name.toUpperCase(),
                      style: t.labelMedium?.copyWith(color: c.onSurfaceVariant, letterSpacing: 0.8, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (!v.inStock)
                    const Tag('Out of stock', tone: TagTone.bad)
                  else if (v.stock <= 3)
                    Tag('Only ${v.stock} left', tone: TagTone.deal)
                  else
                    const Tag('In stock', tone: TagTone.ok, icon: PhosphorIconsBold.check),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(shortName(p.name, p.brand.name), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: Space.sm),
              PriceTag(pricePaise: v.pricePaise, mrpPaise: v.mrpPaise, large: true),
              EmiLine(pricePaise: v.pricePaise), // "EMI from ₹X/month"; nothing when EMI doesn't apply
              const SizedBox(height: 2),
              Text('Inclusive of all taxes · EMI options at checkout', style: muted),
              if (p.id.isNotEmpty) _OfferChips(productId: p.id),
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
              if (settings != null) ...[
                const SizedBox(height: 18),
                _DeliveryCard(settings),
                const SizedBox(height: Space.md),
                _StoreRows(settings: settings, item: '${p.name} (${v.name})'),
              ],
              if (p.description.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(p.description, style: t.bodyMedium),
              ],
              if (p.specs.isNotEmpty) ...[
                const SizedBox(height: 22),
                Semantics(
                  header: true,
                  child: Text('Specifications', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: Space.sm),
                for (final s in p.specs)
                  DecoratedBox(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: c.outlineVariant))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(specIcon(s.label), size: 20, color: c.onSurfaceVariant),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.label, style: t.titleSmall?.copyWith(fontSize: 13)),
                                Text(s.value, style: t.bodyMedium?.copyWith(fontSize: 13, color: c.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (p.id.isNotEmpty) ReportListingLink(productId: p.id),
            ],
          ),
        ),
        if (p.id.isNotEmpty) ProductRails(product: p),
      ],
    );
  }
}

/// One gold chip per running offer that covers this product (`offers_for_product`); tap for its terms.
class _OfferChips extends ConsumerWidget {
  const _OfferChips({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    final offers = ref.watch(productOffersProvider(productId)).value ?? const <Offer>[];
    if (offers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.xs,
        children: [
          for (final o in offers)
            ActionChip(
              // a coupon in rose (roseInk on roseMist ≈ 7:1), a sale in gold
              avatar: Icon(PhosphorIconsFill.sealPercent, size: 16,
                  color: o.code == null ? c.onTertiaryContainer : BrandColors.roseInk),
              label: Text(
                o.code == null ? '${offerHeadline(o)} · ${o.title}' : '${offerHeadline(o)} with ${o.code}',
                overflow: TextOverflow.ellipsis,
              ),
              labelStyle: TextStyle(
                color: o.code == null ? c.onTertiaryContainer : BrandColors.roseInk,
                fontWeight: FontWeight.w700,
              ),
              backgroundColor: o.code == null ? c.tertiaryContainer : BrandColors.roseMist,
              side: BorderSide.none,
              onPressed: () => context.push('/offers/${o.id}'),
            ),
        ],
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

/// The sticky bar for a sold-out pick: says so instead of Add to cart / Buy now, and offers the nearest one in stock.
class _SoldOutBar extends StatelessWidget {
  const _SoldOutBar({required this.variant, required this.alternative, required this.onSwitch});

  final Variant variant;
  final Variant? alternative;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final alt = alternative;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(PhosphorIconsRegular.prohibit, size: 20, color: c.error),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Out of stock', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(
                      text: alt == null
                          ? ' · this one is sold out for now. Ask us on WhatsApp when it’s back.'
                          : ' · this one is sold out right now.',
                    ),
                  ]),
                  style: t.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        if (alt != null) ...[
          const SizedBox(height: Space.sm),
          FilledButton(onPressed: onSwitch, child: Text('See ${switchLabel(alt, variant)} in stock')),
        ],
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

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard(this.s);

  final StoreSettings s;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Space.md),
        child: Row(
          children: [
            Icon(PhosphorIconsRegular.truck, size: 22, color: c.secondary),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Free delivery', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: deliveryTerms(s)),
                ]),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Returns & warranty", "WhatsApp" (prefilled with the product and variant) and a wholesale enquiry:
/// the shop sells wholesale too, and dealers ask for bulk prices over WhatsApp.
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
    await openExternal(context, whatsappUri(settings.storePhone, 'Hi, I’d like your wholesale price for $qty+ units of $item.'),
        'Couldn’t open WhatsApp.');
  }

  void _showReturns(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Returns & warranty', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: Space.md),
                Text(settings.returnsPolicy, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const chevron = Icon(PhosphorIconsBold.caretRight, size: 16);
    return Card(
      child: Column(
        children: [
          if (settings.returnsPolicy.isNotEmpty) ...[
            ListTile(
              leading: const Icon(PhosphorIconsRegular.shieldCheck),
              title: const Text('Returns & warranty'),
              trailing: chevron,
              onTap: () => _showReturns(context),
            ),
            const Divider(),
          ],
          ListTile(
            leading: const WhatsAppIcon(),
            title: const Text('WhatsApp'),
            subtitle: const Text('Ask us about this product'),
            trailing: chevron,
            onTap: () => openExternal(
                context, whatsappUri(settings.storePhone, 'Hi, I’m interested in $item'), 'Couldn’t open WhatsApp.'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.package),
            title: const Text('Buying in bulk?'),
            subtitle: const Text('Get our wholesale price on WhatsApp'),
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
          Text('How many units? We\'ll reply on WhatsApp with our best price.',
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
