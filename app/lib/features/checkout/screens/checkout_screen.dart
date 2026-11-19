import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/made_to_order_art.dart';
import '../../../core/widgets/widgets.dart';
import '../../account/data/addresses.dart';
import '../../account/data/profile.dart';
import '../../account/widgets/delivery_address.dart';
import '../../cart/data/cart.dart';
import '../../cart/screens/cart_screen.dart' show lineWarning, placeholderCartLine;
import '../../offers/data/offers.dart';
import '../../offers/widgets/offer_widgets.dart';
import '../data/payment.dart';
import 'widgets.dart';

/// Sticky checkout button: its label and whether it can be tapped. [totalPaise] is the server's quote, null
/// until it arrives.
({String label, bool enabled}) checkoutButton({
  required PaymentMethod method,
  required int? totalPaise,
  required bool hasAddress,
  required bool cartOk,
  PayStage stage = PayStage.idle,
}) {
  if (stage != PayStage.idle) return (label: stage.label, enabled: false);
  if (!cartOk) return (label: 'Fix your cart to continue', enabled: false);
  if (!hasAddress) return (label: 'Add an address to continue', enabled: false);
  if (totalPaise == null) return (label: 'Getting your total…', enabled: false);
  final amount = formatInr(totalPaise);
  return (label: method == PaymentMethod.cod ? 'Place order' : 'Pay $amount', enabled: true);
}

/// Why cash on delivery can't be picked, or null if it can. Mirrors the `place_order` COD rule.
String? codUnavailableReason(StoreSettings s, int totalPaise) => !s.codEnabled
    ? 'Not available right now'
    : s.codAllowedFor(totalPaise)
        ? null
        : 'Not available for orders above ${formatInr(s.codMaxPaise)}';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  PaymentMethod _method = PaymentMethod.razorpay;
  final _billKey = GlobalKey();
  Quote? _lastQuote; // shown dimmed while a change of payment method re-prices

  Future<void> _addAddress() => addDeliveryAddress(context, ref);

  Future<void> _changeAddress(List<Address> list, Address current) =>
      changeDeliveryAddress(context, ref, list, current);

  Future<void> _submit(String addressId, PaymentMethod method, String? couponCode) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    void say(String m) => showMessageOn(messenger, m);

    final ({String orderId, PayResult? payment})? r;
    try {
      r = await ref.read(paymentFlowProvider.notifier).checkout(addressId, method, couponCode: couponCode);
    } catch (e) {
      // place_order failed, so no order exists. The cart has been refetched and shows what changed.
      say(friendlyError(e));
      if (!mounted) return;
      if (e is PostgrestException && e.message.startsWith('COUPON_')) {
        ref.invalidate(quoteProvider);
        ref.invalidate(availableOffersProvider);
      }
      if (e is PostgrestException && e.message == 'COD_UNAVAILABLE') ref.invalidate(storeSettingsProvider);
      if (e is PostgrestException && e.message == 'ADDRESS_NOT_FOUND') {
        ref.invalidate(addressesProvider);
        ref.read(selectedAddressProvider.notifier).set(null);
      }
      return;
    }
    if (r == null) return; // already running
    if (r.payment?.message case final m?) say(m);
    // An order exists now: always show its live state, even if this screen was torn down.
    router.go('/checkout/result/${r.orderId}');
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final addresses = ref.watch(addressesProvider);
    final settings = ref.watch(storeSettingsProvider);
    final stage = ref.watch(paymentFlowProvider);
    final busy = stage != PayStage.idle;
    final quote = ref.watch(quoteProvider(_method));
    if (quote.value != null) _lastQuote = quote.value;

    Widget body;
    Widget? bar;
    if ((cart.value, addresses.value, settings.value) case (final lines?, final list?, final s?)) {
      if (lines.isEmpty && !busy) {
        body = EmptyState(
          icon: PhosphorIconsRegular.shoppingBag,
          tone: Worlds.cart,
          title: 'Nothing to check out',
          message: 'Your cart is empty. If you just placed an order, you’ll find it in Orders.',
          action: FilledButton(onPressed: () => context.go('/orders'), child: const Text('View orders')),
        );
      } else {
        final q = quote.value; // priced for the method picked, so an online-only code shows only with online pay
        final codReason = q == null ? null : codUnavailableReason(s, q.totalPaise);
        if (codReason != null && _method == PaymentMethod.cod) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _method = PaymentMethod.razorpay); // re-price for online payment
          });
        }
        final method = codReason == null ? _method : PaymentMethod.razorpay;
        final address = deliveryAddressFrom(list, ref.watch(selectedAddressProvider));
        final cartOk = lines.every((l) => l.purchasable);
        final button = checkoutButton(
          method: method,
          totalPaise: method == _method ? q?.totalPaise : null,
          hasAddress: address != null,
          cartOk: cartOk,
          stage: stage,
        );
        final code = q?.couponError == null ? ref.watch(couponCodeProvider) : null;
        body = _content(
          lines: lines,
          addresses: list,
          address: address,
          method: method,
          codReason: codReason,
          quote: _lastQuote,
          quoteState: quote,
          busy: busy,
        );
        bar = _PayBar(
          label: button.label,
          busy: busy,
          onPressed: button.enabled && !quote.isLoading ? () => _submit(address!.id!, method, code) : null,
          totalPaise: _lastQuote?.totalPaise,
          requoting: quote.isLoading,
          onDetails: _viewDetails,
        );
      }
    } else if ([cart, addresses, settings].where((v) => v.hasError).firstOrNull case final failed?) {
      body = ErrorView(
        error: failed.error!,
        onRetry: () => ref
          ..invalidate(cartProvider)
          ..invalidate(addressesProvider)
          ..invalidate(storeSettingsProvider),
      );
    } else {
      body = IgnorePointer(
        child: Skeletonizer(
          child: _content(
            lines: const [placeholderCartLine, placeholderCartLine],
            addresses: const [],
            address: const Address(
              name: 'Customer name',
              phone: '+919999999999',
              line1: 'House and street, landmark',
              city: 'City',
              state: 'State',
              pincode: '000000',
            ),
            method: PaymentMethod.razorpay,
            codReason: null,
            quote: const Quote(subtotalPaise: 14999800, deliveryFeePaise: 0, discountPaise: 0, totalPaise: 14999800),
            quoteState: const AsyncLoading(),
            busy: false,
          ),
        ),
      );
    }

    // opened with go() after signing in: nothing below, so Back goes to the cart instead of closing the app
    final alone = !(ModalRoute.of(context)?.canPop ?? true);
    return PopScope(
      canPop: !busy && !alone, // busy: an order may already exist; let the flow finish and land on its result
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy && alone) context.go('/cart');
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Checkout'),
          leading: alone ? BackButton(onPressed: busy ? null : () => context.go('/cart')) : null,
        ),
        body: body,
        bottomNavigationBar: bar,
      ),
    );
  }

  Future<void> _setQty(CartLine line, int qty) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(cartProvider.notifier).setQty(line.variant.id, qty); // the quote re-prices on its own
    } catch (e) {
      showMessageOn(messenger, friendlyError(e));
    }
  }

  Future<void> _remove(CartLine line, {required bool last}) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final cart = ref.read(cartProvider.notifier);
    try {
      await cart.remove(line.variant.id);
    } catch (e) {
      showMessageOn(messenger, friendlyError(e));
      return;
    }
    showMessageOn(
      messenger,
      'Removed ${line.productName}',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          try {
            await cart.add(line.variant, qty: line.qty, forModel: line.forModel);
          } catch (e) {
            showMessageOn(messenger, friendlyError(e));
          }
        },
      ),
    );
    if (last && mounted) router.go('/cart'); // nothing left to check out
  }

  void _viewDetails() {
    final ctx = _billKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: Motion.normal, curve: Curves.easeOut);
  }

  Widget _content({
    required List<CartLine> lines,
    required List<Address> addresses,
    required Address? address,
    required PaymentMethod method,
    required String? codReason,
    required Quote? quote,
    required AsyncValue<Quote> quoteState,
    required bool busy,
  }) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final t = theme.textTheme;
    Widget head(String text) => Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Semantics(
        header: true,
        child: Text(text, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      ),
    );
    const gap = SizedBox(height: Space.xl);
    final count = lines.fold<int>(0, (sum, l) => sum + l.qty);
    final leadDays = lines.where((l) => l.variant.madeToOrder).fold<int>(0, (m, l) => math.max(m, l.variant.leadDays));
    final phone = ref.watch(storeSettingsProvider).value?.storePhone;
    final error = quote == null ? quoteState.error : null;
    final Widget bill = quote != null
        ? AnimatedOpacity(
            opacity: quoteState.isLoading ? 0.5 : 1,
            duration: Motion.fast,
            child: _Bill(lines: lines, quote: quote, count: count),
          )
        : error != null
        ? Row(
            children: [
              Expanded(child: Text(friendlyError(error), style: t.bodyMedium)),
              TextButton(onPressed: () => ref.invalidate(quoteProvider), child: const Text('Retry')),
            ],
          )
        : Skeletonizer(
            child: _Bill(
              lines: lines,
              quote: const Quote(subtotalPaise: 7739700, deliveryFeePaise: 0, discountPaise: 0, totalPaise: 7739700),
              count: count,
            ),
          );

    return Theme(
      // one white card style for every section, CouponRow's included: radius 20, one soft shadow, no border
      data: theme.copyWith(
        cardTheme: CardThemeData(
          elevation: 2,
          shadowColor: c.shadow.withValues(alpha: 0.12),
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
          color: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.hero)),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head('Deliver to'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (address == null)
                      Row(
                        children: [
                          Expanded(child: Text('No delivery address yet', style: t.titleSmall)),
                          TextButton(onPressed: busy ? null : _addAddress, child: const Text('Add address')),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: Space.sm),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${address.name} · ${displayPhone(address.phone)}',
                                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: Space.xs),
                                  Text(
                                    address.oneLine,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                            onPressed: busy ? null : () => _changeAddress(addresses, address),
                            child: const Text('Change', semanticsLabel: 'Change delivery address'),
                          ),
                        ],
                      ),
                    // shortcut: no delivery-days setting exists yet, so only made-to-order lead time shows; add "Arrives by" when it does
                    if (leadDays > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.sm, right: Space.md),
                        child: Row(
                          children: [
                            Icon(PhosphorIconsRegular.truck, size: IconSizes.sm, color: c.secondary),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: Text(
                                'Arranged items ship in $leadDays ${leadDays == 1 ? 'day' : 'days'}',
                                style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            gap,
            head('Items ($count)'),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: Column(
                  children: [
                    for (final (i, l) in lines.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      _ItemRow(
                        line: l,
                        enabled: !busy,
                        onQty: (n) => _setQty(l, n),
                        onRemove: () => _remove(l, last: lines.length == 1),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            gap,
            head('Offers'),
            CouponRow(quote: quote, method: method, enabled: !busy),
            gap,
            head('Payment'),
            RadioGroup<PaymentMethod>(
              groupValue: method,
              onChanged: (m) {
                if (m != null && !busy) setState(() => _method = m);
              },
              child: Column(
                children: [
                  _PayOption(
                    value: PaymentMethod.razorpay,
                    selected: method == PaymentMethod.razorpay,
                    enabled: !busy,
                    title: 'Pay online (UPI, cards, netbanking)',
                    subtitle: null,
                    onTap: () => setState(() => _method = PaymentMethod.razorpay),
                  ),
                  const SizedBox(height: Space.sm),
                  _PayOption(
                    value: PaymentMethod.cod,
                    selected: method == PaymentMethod.cod,
                    enabled: codReason == null && !busy,
                    title: 'Cash on delivery',
                    subtitle: codReason ?? 'Pay in cash when it arrives',
                    onTap: () => setState(() => _method = PaymentMethod.cod),
                  ),
                ],
              ),
            ),
            gap,
            head('Price details'),
            KeyedSubtree(
              key: _billKey,
              child: Card(
                child: Padding(padding: const EdgeInsets.all(Space.lg), child: bill),
              ),
            ),
            if (phone != null) ...[
              gap,
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const WhatsAppIcon(),
                  title: const Text('Questions? WhatsApp us'),
                  trailing: Icon(PhosphorIconsRegular.caretRight, size: IconSizes.sm, color: c.onSurfaceVariant),
                  onTap: () => openUri(
                    context,
                    whatsAppUri(
                      phone,
                      text: cartWhatsAppText(
                        lines,
                        quote?.totalPaise ?? cartSubtotalPaise(lines),
                        name: firstName(ref.read(profileProvider).value?.fullName),
                      ),
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

/// One cart line, editable in place: stepper (min 1, max the stock cap) and Remove.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.line, required this.enabled, required this.onQty, required this.onRemove});

  final CartLine line;
  final bool enabled;
  final ValueChanged<int> onQty;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final warning = lineWarning(line);
    final v = line.variant;
    final unavailable = !line.productActive || !v.isActive || (!v.madeToOrder && v.stock <= 0);
    final sub = [if (v.name.isNotEmpty) v.name, if (line.forModel != null) 'For: ${line.forModel}'].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 56,
            child: ProductArt(line.coverPath, name: line.productName, madeToOrder: line.variant.madeToOrder, radius: Radii.sm, padding: Space.xs),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.productName, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (warning != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Tag(
                      warning.text,
                      tone: warning.blocking ? TagTone.bad : TagTone.deal,
                      icon: PhosphorIconsBold.warning,
                    ),
                  ),
                const SizedBox(height: Space.xs),
                PriceTag(pricePaise: line.lineTotalPaise, mrpPaise: v.mrpPaise * line.qty),
                const SizedBox(height: Space.xs),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Space.sm,
                  children: [
                    IgnorePointer(
                      ignoring: !enabled,
                      child: QtyStepper(
                        value: line.qty,
                        // an unavailable line can only be removed
                        min: unavailable ? line.qty : 1,
                        max: unavailable ? line.qty : maxQtyFor(v),
                        onChanged: onQty,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove ${line.productName}',
                      onPressed: enabled ? onRemove : null,
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: Icon(PhosphorIconsRegular.trash, size: 20, color: c.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The bill: every amount from the server quote; "Price" is MRP, so MRP − quote.subtotal is the MRP discount.
class _Bill extends StatelessWidget {
  const _Bill({required this.lines, required this.quote, required this.count});

  final List<CartLine> lines;
  final Quote quote;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final mrpOff = lines.fold<int>(0, (s, l) => s + math.max(0, l.variant.mrpPaise - l.variant.pricePaise) * l.qty);
    final green = t.bodyMedium?.copyWith(color: c.secondary, fontWeight: FontWeight.w700, fontFeatures: tabularFigures);
    Widget row(String label, String value, {TextStyle? style, String? semantics}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
          ),
          const SizedBox(width: Space.sm),
          Text(
            value,
            semanticsLabel: semantics,
            style: style ?? t.bodyMedium?.copyWith(fontFeatures: tabularFigures),
          ),
        ],
      ),
    );
    final label = quote.discountLabel;
    final saving = cartSavingPaise(lines, quote.discountPaise);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('Price ($count ${count == 1 ? 'item' : 'items'})', formatInr(quote.subtotalPaise + mrpOff)),
        if (mrpOff > 0)
          row('Discount on MRP', '−${formatInr(mrpOff)}', style: green, semantics: 'minus ${formatInr(mrpOff)}'),
        if (quote.discountPaise > 0)
          row(
            label == null
                ? 'Offer'
                : label.startsWith('Pack saving')
                ? label
                : 'Offer · $label',
            '−${formatInr(quote.discountPaise)}',
            style: green,
            semantics: 'minus ${formatInr(quote.discountPaise)}',
          )
        else if (label != null)
          row('Offer · $label', 'Free delivery', style: green),
        row(
          'Delivery',
          quote.deliveryFeePaise == 0 ? 'Free' : formatInr(quote.deliveryFeePaise),
          style: quote.deliveryFeePaise == 0 ? green : null,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Space.xs),
          child: Divider(height: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text('Total', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              Text(
                formatInr(quote.totalPaise),
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures),
              ),
            ],
          ),
        ),
        if (saving > 0)
          Container(
            margin: const EdgeInsets.only(top: Space.sm),
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            decoration: BoxDecoration(color: c.secondaryContainer, borderRadius: BorderRadius.circular(Radii.md)),
            child: Text(
              'You save ${formatInr(saving)} on this order',
              style: t.labelLarge?.copyWith(color: c.onSecondaryContainer, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class _PayOption extends StatelessWidget {
  const _PayOption({
    required this.value,
    required this.selected,
    required this.enabled,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final PaymentMethod value;
  final bool selected;
  final bool enabled;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.hero),
        side: selected ? BorderSide(color: c.primary, width: 2) : BorderSide.none,
      ),
      child: MergeSemantics(
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.lg, Space.xs),
              child: Row(
                children: [
                  Radio<PaymentMethod>(value: value, enabled: enabled),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: enabled ? null : c.onSurfaceVariant,
                            ),
                          ),
                          if (subtitle != null)
                            Text(subtitle!, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        ],
                      ),
                    ),
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

class _PayBar extends StatelessWidget {
  const _PayBar({
    required this.label,
    required this.busy,
    required this.onPressed,
    required this.totalPaise,
    required this.requoting,
    required this.onDetails,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final int? totalPaise;
  final bool requoting;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StickyBar(
      child: Row(
        children: [
          // two equal halves: a Flexible here keeps its unused share as a gap, leaving the button mid-bar
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedOpacity(
                  opacity: requoting ? 0.5 : 1,
                  duration: Motion.fast,
                  child: Text(
                    totalPaise == null ? 'Total —' : 'Total ${formatInr(totalPaise!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures),
                  ),
                ),
                TextButton(
                  onPressed: onDetails,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                    alignment: AlignmentDirectional.centerStart,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('View details'),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: FilledButton(
              onPressed: onPressed,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy) ...[const ButtonSpinner(), const SizedBox(width: Space.md)],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFeatures: tabularFigures),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
