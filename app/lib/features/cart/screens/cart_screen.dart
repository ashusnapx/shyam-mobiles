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
import '../../../core/widgets/widgets.dart';
import '../../checkout/screens/widgets.dart';
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
void _report(ScaffoldMessengerState messenger, Future<void> write) => write.catchError((Object e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
    });

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentUserIdProvider) == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cart')),
        body: const SignInPrompt(
          icon: PhosphorIconsRegular.shoppingBag,
          title: 'Sign in to see your cart',
          message: 'Your cart is saved to your account.',
          from: '/cart',
        ),
      );
    }
    final cart = ref.watch(cartProvider);
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
        data: (lines) => lines.isEmpty
            ? EmptyState(
                icon: PhosphorIconsRegular.shoppingBag,
                title: 'Your cart is empty',
                message: 'Phones and accessories you add show up here.',
                action: FilledButton(onPressed: () => context.go('/'), child: const Text('Start shopping')),
              )
            : _CartList(lines: lines),
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
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Removed ${line.productName}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _report(messenger, container.read(cartProvider.notifier).add(line.variant, qty: line.qty)),
        ),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final settings = ref.watch(storeSettingsProvider);
    final subtotal = lines.fold<int>(0, (sum, l) => sum + l.lineTotalPaise);
    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(storeSettingsProvider);
        return ref.refresh(cartProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
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
                  onQty: (q) => _report(
                    ScaffoldMessenger.of(context),
                    ref.read(cartProvider.notifier).setQty(line.variant.id, q),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg + 2, Space.lg, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                child: settings.when(
                  skipLoadingOnRefresh: true,
                  loading: () => const Skeletonizer(
                    child: TotalsRows(subtotalPaise: 7739700, deliveryFeePaise: 0, totalPaise: 7739700),
                  ),
                  error: (e, _) => Row(children: [
                    Expanded(child: Text('Couldn’t load delivery fee.', style: t.bodyMedium)),
                    TextButton(onPressed: () => ref.invalidate(storeSettingsProvider), child: const Text('Retry')),
                  ]),
                  data: (s) {
                    final fee = s.deliveryFeeFor(subtotal);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TotalsRows(subtotalPaise: subtotal, deliveryFeePaise: fee, totalPaise: subtotal + fee),
                        if (fee > 0 && s.freeDeliveryMinPaise > subtotal)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.sm),
                            child: Row(
                              children: [
                                Icon(PhosphorIconsRegular.truck, size: 16, color: c.secondary),
                                const SizedBox(width: Space.sm),
                                Expanded(
                                  child: Text(
                                    'Add ${formatInr(s.freeDeliveryMinPaise - subtotal)} more for free delivery',
                                    style: t.bodySmall?.copyWith(color: c.secondary, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          for (final (icon, text) in [
            (PhosphorIconsRegular.sealCheck, 'No platform, COD or packing fees'),
            (PhosphorIconsRegular.info, 'The final amount is confirmed when you place the order.'),
            (PhosphorIconsRegular.arrowUUpLeft, 'Swipe an item left to remove it. You can undo.'),
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
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.onQty});

  final CartLine line;
  final ValueChanged<int> onQty;

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
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 84, child: ProductImage(line.coverPath, radius: 14, padding: Space.sm)),
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
                        padding: const EdgeInsets.only(top: 6),
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
                        PriceTag(pricePaise: line.lineTotalPaise),
                        QtyStepper(
                          value: line.qty,
                          // Unavailable lines can only be removed; over-stock lines can only go down.
                          min: unavailable ? line.qty : 1,
                          max: unavailable ? line.qty : maxQtyFor(line.variant),
                          onChanged: onQty,
                        ),
                      ],
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
    final settings = ref.watch(storeSettingsProvider).value;
    final blocked = lines.any((l) => !l.purchasable);
    final subtotal = lines.fold<int>(0, (sum, l) => sum + l.lineTotalPaise);
    final total = settings == null ? null : subtotal + settings.deliveryFeeFor(subtotal);
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.outlineVariant))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
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
                      child: Text(
                        total == null ? 'Checkout' : 'Checkout · ${formatInr(total)}',
                        style: const TextStyle(fontFeatures: tabularFigures),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    const Icon(PhosphorIconsBold.arrowRight, size: 18),
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
