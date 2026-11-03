import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/widgets.dart';
import '../../account/data/profile.dart';
import '../../account/widgets/delivery_address.dart';
import '../../catalog/data/catalog.dart';
import '../../catalog/data/rails.dart';
import '../../catalog/widgets/product_rail.dart';
import '../../checkout/screens/widgets.dart';
import '../../offers/data/offers.dart';
import '../../offers/widgets/offer_widgets.dart';
import '../data/cart.dart';

/// Tag under a cart line. `blocking` matches `!CartLine.purchasable`: checkout waits until it's fixed.
({String text, bool blocking})? lineWarning(CartLine l) {
  final stock = l.variant.stock;
  if (!l.productActive || !l.variant.isActive) return (text: 'No longer available', blocking: true);
  if (stock <= 0) return (text: 'Out of stock', blocking: true);
  if (stock < l.qty) return (text: 'Only $stock left', blocking: true); // the minus button fixes it
  if (stock <= 3) return (text: 'Only $stock left', blocking: false);
  return null;
}

/// Shows errors from background cart writes without needing the widget to still be mounted.
void _report(ScaffoldMessengerState messenger, Future<void> write) =>
    write.catchError((Object e) => showMessageOn(messenger, friendlyError(e)));

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentUserIdProvider) == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cart')),
        body: const SignInPrompt(
          icon: PhosphorIconsRegular.shoppingBag,
          tone: Worlds.cart,
          title: 'Sign in to see your cart',
          message: 'Your cart is saved to your account.',
          from: '/cart',
        ),
      );
    }
    final cart = ref.watch(cartProvider);
    // the cart drops lines the shop hid: say so once (takeRemoved empties), after this frame
    if (cart.hasValue) {
      final names = ref.read(cartProvider.notifier).takeRemoved();
      if (names.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) showMessage(context, removedNotice(names));
        });
      }
    }
    final count = ref.watch(cartCountProvider);
    final lines = cart.value ?? const <CartLine>[];
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text.rich(TextSpan(text: 'Cart', children: [
          if (count > 0)
            TextSpan(
              text: ' · $count ${count == 1 ? 'item' : 'items'}',
              style: t.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ])),
      ),
      body: AsyncBody(
        value: cart,
        onRetry: () => ref.invalidate(cartProvider),
        loading: Skeletonizer(
          child: ListView(physics: const NeverScrollableScrollPhysics(), children: [
            for (var i = 0; i < 3; i++) _LineTile(line: placeholderCartLine, onQty: (_) {}),
          ]),
        ),
        data: (lines) => lines.isEmpty ? const _EmptyCart() : _CartList(lines: lines),
      ),
      bottomNavigationBar: lines.isEmpty ? null : _CheckoutBar(lines: lines),
    );
  }
}

class _CartList extends ConsumerWidget {
  const _CartList({required this.lines});

  final List<CartLine> lines;

  Future<void> _remove(BuildContext context, CartLine line) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container.read(cartProvider.notifier).remove(line.variant.id);
    } catch (e) {
      showMessageOn(messenger, friendlyError(e));
      return;
    }
    showMessageOn(
      messenger,
      'Removed ${line.productName}',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => _report(messenger, container.read(cartProvider.notifier).add(line.variant, qty: line.qty)),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final settings = ref.watch(storeSettingsProvider).value;
    final quote = ref.watch(quoteProvider(null));
    final q = quote.value;
    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(storeSettingsProvider);
        ref.invalidate(availableOffersProvider);
        return ref.refresh(cartProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          const DeliverToRow(),
          if (q != null && settings != null) _FreeDelivery(quote: q, settings: settings),
          for (final line in lines)
            Dismissible(
              key: ValueKey(line.variant.id),
              direction: DismissDirection.endToStart,
              background: ColoredBox(
                color: c.errorContainer,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: Space.xl),
                    child: Icon(PhosphorIconsRegular.trash, color: c.onErrorContainer),
                  ),
                ),
              ),
              onDismissed: (_) => _remove(context, line),
              child: Semantics(
                customSemanticsActions: {
                  const CustomSemanticsAction(label: 'Remove from cart'): () => _remove(context, line),
                },
                child: _LineTile(
                  line: line,
                  onRemove: () => _remove(context, line),
                  onQty: (q) => _report(
                    ScaffoldMessenger.of(context),
                    ref.read(cartProvider.notifier).setQty(line.variant.id, q),
                  ),
                ),
              ),
            ),
          _CrossSell(lines: lines),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 0),
            child: CouponRow(quote: q),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                // the server's numbers; dimmed while it re-prices a change
                child: switch (quote) {
                  AsyncValue(value: final q?) => AnimatedOpacity(
                      opacity: quote.isLoading ? 0.5 : 1,
                      duration: Motion.fast,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TotalsRows(
                            subtotalPaise: q.subtotalPaise,
                            deliveryFeePaise: q.deliveryFeePaise,
                            discountPaise: q.discountPaise,
                            discountLabel: q.discountLabel,
                            totalPaise: q.totalPaise,
                          ),
                          YouSave(cartSavingPaise(lines, q.discountPaise)),
                        ],
                      ),
                    ),
                  AsyncValue(:final error?) => Row(children: [
                      Expanded(child: Text(friendlyError(error), style: t.bodyMedium)),
                      TextButton(onPressed: () => ref.invalidate(quoteProvider), child: const Text('Retry')),
                    ]),
                  _ => const Skeletonizer(
                      child: TotalsRows(subtotalPaise: 7739700, deliveryFeePaise: 0, totalPaise: 7739700),
                    ),
                },
              ),
            ),
          ),
          for (final (icon, text) in [
            (PhosphorIconsRegular.sealCheck, 'No platform, COD or packing fees'),
            if (q != null && (settings?.codAllowedFor(q.totalPaise) ?? false))
              (PhosphorIconsRegular.money, 'Cash on delivery available'),
          ])
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: c.onSurfaceVariant),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(text, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant))),
                ],
              ),
            ),
          if (settings != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: ListTile(
                leading: const WhatsAppIcon(),
                title: const Text('Need help? Send this cart on WhatsApp'),
                subtitle: const Text('We can answer questions or send you a payment link'),
                trailing: Icon(PhosphorIconsRegular.caretRight, size: IconSizes.sm, color: c.onSurfaceVariant),
                onTap: () => openUri(
                  context,
                  whatsAppUri(
                    settings.storePhone,
                    text: cartWhatsAppText(lines, q?.totalPaise ?? cartSubtotalPaise(lines),
                        name: firstName(ref.read(profileProvider).value?.fullName)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Add ₹300 more for free delivery" with a bar, at the top of the cart; "You get free delivery" once reached.
/// Hidden when every order ships free. The server's numbers, as in the totals.
class _FreeDelivery extends StatelessWidget {
  const _FreeDelivery({required this.quote, required this.settings});

  final Quote quote;
  final StoreSettings settings;

  @override
  Widget build(BuildContext context) {
    if (settings.deliveryFeePaise == 0 || settings.freeDeliveryMinPaise <= 0) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final base = quote.subtotalPaise - quote.discountPaise;
    final gap = quote.deliveryFeePaise > 0 ? settings.freeDeliveryGapFor(base) : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsRegular.truck, size: IconSizes.sm, color: BrandColors.emerald),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  gap > 0 ? 'Add ${formatInr(gap)} more for free delivery' : 'You get free delivery',
                  style: t.bodyMedium?.copyWith(color: BrandColors.mintInk, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          ExcludeSemantics(
            child: LinearProgressIndicator(
              value: gap > 0 ? (base / settings.freeDeliveryMinPaise).clamp(0, 1) : 1,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: BrandColors.emerald,
              backgroundColor: BrandColors.mint,
            ),
          ),
        ],
      ),
    );
  }
}

/// "You save ₹13,400 on this order" under a total: MRP savings plus the discount. Nothing when there's none.
class YouSave extends StatelessWidget {
  const YouSave(this.paise, {super.key});

  final int paise;

  @override
  Widget build(BuildContext context) => paise <= 0
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Text(
            'You save ${formatInr(paise)} on this order',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: BrandColors.emerald, fontWeight: FontWeight.w700),
          ),
        );
}

/// A case or guard for the dearest item when it's a phone with accessories made for it; else cheap add-ons.
/// Items already in the cart are left out.
class _CrossSell extends ConsumerWidget {
  const _CrossSell({required this.lines});

  final List<CartLine> lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart = {for (final l in lines) l.productId};
    List<ProductCard> fresh(List<ProductCard> cards) => [for (final c in cards) if (c.inStock && !inCart.contains(c.id)) c];
    final top = lines.reduce((a, b) => b.variant.pricePaise > a.variant.pricePaise ? b : a);
    final fits = ref.watch(fitsProvider(top.productSlug)).whenData(fresh);
    if (fits.isLoading && !fits.hasValue) return const SizedBox.shrink(); // decides which rail, so no flicker
    // the cart's one tinted band
    if (fits.value?.isNotEmpty ?? false) {
      return ProductRail(title: 'Add a case or guard for ${top.productName}', band: sectionTints.fits, value: fits);
    }
    return ProductRail(
      title: 'Add-ons under ₹1,500',
      band: sectionTints.deals,
      value: ref.watch(homeProvider).whenData((h) => fresh(h.accessories)),
    );
  }
}

/// Branded empty cart with a way back into the shop, then what they looked at and cheap add-ons.
class _EmptyCart extends ConsumerWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
        children: [
          EmptyState(
            icon: PhosphorIconsRegular.shoppingBag,
            tone: Worlds.cart,
            title: 'Your cart is empty',
            message: 'Add a phone or accessory and it will wait here for you.',
            action: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/search?category=smartphones'),
                  icon: const Icon(PhosphorIconsRegular.storefront),
                  label: const Text('Shop phones'),
                ),
                const SizedBox(height: Space.sm),
                OutlinedButton(onPressed: () => context.push('/offers'), child: const Text('See offers')),
              ],
            ),
          ),
          ProductRail(title: 'Recently viewed', value: ref.watch(recentCardsProvider)),
          ProductRail(title: 'Deals under ₹1,500', value: ref.watch(homeProvider).whenData((h) => h.accessories)),
          const SizedBox(height: Space.xl),
        ],
      );
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.onQty, this.onRemove});

  final CartLine line;
  final ValueChanged<int> onQty;
  final VoidCallback? onRemove; // the Remove button

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final warning = lineWarning(line);
    final unavailable = !line.productActive || !line.variant.isActive || line.variant.stock <= 0;
    return InkWell(
      onTap: () => context.push('/product/${line.productSlug}'),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.outlineVariant))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 84, child: ProductImage(line.coverPath, radius: Radii.button, padding: Space.sm)),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.productName, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (line.variant.name.isNotEmpty)
                      Text(line.variant.name, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                    if (warning != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Tag(
                          warning.text,
                          tone: warning.blocking ? TagTone.bad : TagTone.deal,
                          icon: PhosphorIconsBold.warning,
                        ),
                      ),
                    const SizedBox(height: Space.sm),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      children: [
                        PriceTag(pricePaise: line.lineTotalPaise, mrpPaise: line.variant.mrpPaise * line.qty),
                        // the Remove button below is the one way to remove: the minus stops at 1
                        QtyStepper(
                          value: line.qty,
                          // Unavailable lines can only be removed; over-stock lines can only go down.
                          min: unavailable ? line.qty : 1,
                          max: unavailable ? line.qty : maxQtyFor(line.variant),
                          onChanged: onQty,
                        ),
                      ],
                    ),
                    // always on screen: swipe-to-remove alone is easy to miss
                    if (onRemove != null)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Tooltip(
                          message: 'Remove ${line.productName} from the cart',
                          child: TextButton.icon(
                            onPressed: onRemove,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              foregroundColor: c.onSurfaceVariant,
                            ),
                            icon: const Icon(PhosphorIconsRegular.trash, size: 18),
                            label: const Text('Remove'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutBar extends ConsumerWidget {
  const _CheckoutBar({required this.lines});

  final List<CartLine> lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    final blocked = lines.any((l) => !l.purchasable);
    final total = ref.watch(quoteProvider(null)).value?.totalPaise;
    return StickyBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (blocked)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Text(
                    'Remove or update the marked items to check out.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              FilledButton(
                onPressed: blocked ? null : () => context.push('/checkout'),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: total == null
                          ? const Text('Checkout')
                          : CountTo(total, format: (p) => 'Checkout · ${formatInr(p)}'), // rolls with the total
                    ),
                    const SizedBox(width: Space.sm),
                    const Icon(PhosphorIconsBold.arrowRight, size: 18),
                  ],
                ),
              ),
            ],
          ),
    );
  }
}

/// Stand-in data for skeletons.
const placeholderCartLine = CartLine(
  variant: Variant(
    id: '',
    productId: '',
    sku: '',
    name: '12 GB · 256 GB · Navy',
    pricePaise: 7499900,
    mrpPaise: 7499900,
    stock: 10,
  ),
  qty: 1,
  productId: '',
  productSlug: '',
  productName: 'Samsung Galaxy S25 5G',
);
