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
import '../../../core/widgets/widgets.dart';
import '../../account/data/addresses.dart';
import '../../cart/data/cart.dart';
import '../../cart/screens/cart_screen.dart' show placeholderCartLine;
import '../data/payment.dart';
import 'widgets.dart';

/// Sticky checkout button: its label and whether it can be tapped.
({String label, bool enabled}) checkoutButton({
  required PaymentMethod method,
  required int totalPaise,
  required bool hasAddress,
  required bool cartOk,
  PayStage stage = PayStage.idle,
}) {
  if (stage != PayStage.idle) return (label: stage.label, enabled: false);
  if (!cartOk) return (label: 'Fix your cart to continue', enabled: false);
  if (!hasAddress) return (label: 'Add an address to continue', enabled: false);
  final amount = formatInr(totalPaise);
  return (label: method == PaymentMethod.cod ? 'Place order · $amount' : 'Pay $amount', enabled: true);
}

/// Why cash on delivery can't be picked, or null if it can. Mirrors the `place_order` COD rule.
String? codUnavailableReason(StoreSettings s, int totalPaise) => !s.codEnabled
    ? 'Not available right now'
    : s.codAllowedFor(totalPaise)
        ? null
        : 'Not available for orders above ${formatInr(s.codMaxPaise)}';

const _addNew = 'new';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  Address? _picked; // null: the default (first) address
  PaymentMethod _method = PaymentMethod.razorpay;
  bool _showItems = false;

  Address? _addressFrom(List<Address> list) => _picked == null
      ? list.firstOrNull
      // the address form returns the saved row before the list has reloaded
      : list.where((a) => a.id == _picked!.id).firstOrNull ?? _picked;

  Future<void> _addAddress() async {
    final a = await context.push<Address>('/account/addresses/new');
    if (mounted && a?.id != null) setState(() => _picked = a);
  }

  Future<void> _changeAddress(List<Address> list, Address current) async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddressSheet(addresses: list, selectedId: current.id),
    );
    if (!mounted) return;
    if (picked is Address) setState(() => _picked = picked);
    if (picked == _addNew) await _addAddress();
  }

  Future<void> _submit(String addressId, PaymentMethod method) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    void say(String m) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));

    final ({String orderId, PayResult? payment})? r;
    try {
      r = await ref.read(paymentFlowProvider.notifier).checkout(addressId, method);
    } catch (e) {
      // place_order failed, so no order exists. The cart has been refetched and shows what changed.
      say(friendlyError(e));
      if (!mounted) return;
      if (e is PostgrestException && e.message == 'COD_UNAVAILABLE') ref.invalidate(storeSettingsProvider);
      if (e is PostgrestException && e.message == 'ADDRESS_NOT_FOUND') {
        ref.invalidate(addressesProvider);
        setState(() => _picked = null);
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

    Widget body;
    Widget? bar;
    if ((cart.value, addresses.value, settings.value) case (final lines?, final list?, final s?)) {
      if (lines.isEmpty && !busy) {
        body = EmptyState(
          icon: PhosphorIconsRegular.shoppingBag,
          title: 'Nothing to check out',
          message: 'Your cart is empty. If you just placed an order, you’ll find it in Orders.',
          action: FilledButton(onPressed: () => context.go('/orders'), child: const Text('View orders')),
        );
      } else {
        final subtotal = lines.fold<int>(0, (sum, l) => sum + l.lineTotalPaise);
        final fee = s.deliveryFeeFor(subtotal);
        final total = subtotal + fee;
        final codReason = codUnavailableReason(s, total);
        final method = codReason == null ? _method : PaymentMethod.razorpay;
        final address = _addressFrom(list);
        final cartOk = lines.every((l) => l.purchasable);
        final button = checkoutButton(
          method: method,
          totalPaise: total,
          hasAddress: address != null,
          cartOk: cartOk,
          stage: stage,
        );
        body = _content(
          lines: lines,
          addresses: list,
          address: address,
          method: method,
          codReason: codReason,
          subtotal: subtotal,
          fee: fee,
          cartOk: cartOk,
          busy: busy,
        );
        bar = _PayBar(
          label: button.label,
          busy: busy,
          onPressed: button.enabled ? () => _submit(address!.id!, method) : null,
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
      body = Skeletonizer(
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
          subtotal: 14999800,
          fee: 0,
          cartOk: true,
          busy: false,
        ),
      );
    }

    return PopScope(
      canPop: !busy, // an order may already exist; let the flow finish and land on its result
      child: Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: body,
        bottomNavigationBar: bar,
      ),
    );
  }

  Widget _content({
    required List<CartLine> lines,
    required List<Address> addresses,
    required Address? address,
    required PaymentMethod method,
    required String? codReason,
    required int subtotal,
    required int fee,
    required bool cartOk,
    required bool busy,
  }) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(0, Space.lg + 2, 0, Space.sm),
          child: Semantics(header: true, child: Text(text, style: t.labelMedium)),
        );
    final count = lines.fold<int>(0, (sum, l) => sum + l.qty);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
      children: [
        if (!cartOk)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Card(
              color: c.errorContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(PhosphorIconsRegular.warning, color: c.onErrorContainer),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(
                            'Some items are no longer available in that quantity.',
                            style: t.bodyMedium?.copyWith(color: c.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                    TextButton(onPressed: () => context.go('/cart'), child: const Text('Review cart')),
                  ],
                ),
              ),
            ),
          ),
        label('Deliver to'),
        if (address == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No delivery address yet', style: t.titleSmall),
                  const SizedBox(height: Space.xs),
                  Text('Add one to place your order.', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                  const SizedBox(height: Space.md),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _addAddress,
                    icon: const Icon(PhosphorIconsRegular.plus),
                    label: const Text('Add address'),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(address.name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            Tag(address.label.displayName),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => _changeAddress(addresses, address),
                        child: Text('Change', semanticsLabel: 'Change delivery address'),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: Space.sm),
                    child: Text(address.oneLine, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(PhosphorIconsRegular.phone, size: 14, color: c.onSurfaceVariant),
                      const SizedBox(width: Space.xs),
                      Text(displayPhone(address.phone), style: t.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
        label('Payment'),
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
                subtitle: 'UPI, cards, netbanking, EMI',
                onTap: () => setState(() => _method = PaymentMethod.razorpay),
                footnote: 'EMI bank charges, if any, are shown by Razorpay before you pay.',
                extra: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (icon, name) in [
                      (PhosphorIconsBold.qrCode, 'UPI'),
                      (PhosphorIconsBold.creditCard, 'Cards'),
                      (PhosphorIconsBold.bank, 'Netbanking'),
                      (null, 'EMI'),
                    ])
                      DecoratedBox(
                        decoration: BoxDecoration(color: c.surfaceContainer, borderRadius: BorderRadius.circular(6)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (icon != null) ...[Icon(icon, size: 13), const SizedBox(width: Space.xs)],
                            Text(name, style: t.labelSmall),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _PayOption(
                value: PaymentMethod.cod,
                selected: method == PaymentMethod.cod,
                enabled: codReason == null && !busy,
                subtitle: codReason ?? 'Pay in cash when it arrives',
                icon: PhosphorIconsRegular.money,
                onTap: () => setState(() => _method = PaymentMethod.cod),
              ),
            ],
          ),
        ),
        label('Order summary'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    for (final (i, l) in lines.take(3).indexed)
                      Align(
                        widthFactor: i == (lines.length < 3 ? lines.length : 3) - 1 ? 1 : 0.8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Radii.sm + 2),
                            border: Border.all(color: c.surface, width: 2),
                          ),
                          child: SizedBox.square(
                            dimension: 40,
                            child: ProductImage(l.coverPath, radius: Radii.sm, padding: Space.xs),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                      onPressed: () => setState(() => _showItems = !_showItems),
                      iconAlignment: IconAlignment.end,
                      icon: Icon(_showItems ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown, size: 16),
                      label: Text(
                        '$count ${count == 1 ? 'item' : 'items'}',
                        semanticsLabel: _showItems ? 'Hide $count items' : 'Show $count items',
                      ),
                    ),
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: Motion.normal,
                  alignment: Alignment.topCenter,
                  child: !_showItems
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          children: [
                            for (final l in lines)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        [l.productName, if (l.variant.name.isNotEmpty) l.variant.name].join(' · '),
                                        style: t.bodySmall,
                                      ),
                                    ),
                                    const SizedBox(width: Space.sm),
                                    Text(
                                      '${l.qty} × ${formatInr(l.variant.pricePaise)}',
                                      style: t.bodySmall?.copyWith(fontFeatures: tabularFigures),
                                    ),
                                  ],
                                ),
                              ),
                            const Divider(),
                          ],
                        ),
                ),
                const SizedBox(height: Space.xs),
                TotalsRows(subtotalPaise: subtotal, deliveryFeePaise: fee, totalPaise: subtotal + fee, totalLabel: 'To pay'),
              ],
            ),
          ),
        ),
        if (method == PaymentMethod.razorpay)
          Padding(
            padding: const EdgeInsets.only(top: Space.lg),
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.surfaceContainerLow, borderRadius: BorderRadius.circular(Radii.md)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Space.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(PhosphorIconsFill.lockKey, size: 18, color: c.secondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Payments go through Razorpay. Shyam Mobiles never sees your card details or UPI PIN.',
                        style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
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
    required this.subtitle,
    required this.onTap,
    this.extra,
    this.footnote,
    this.icon,
  });

  final PaymentMethod value;
  final bool selected;
  final bool enabled;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? extra;
  final String? footnote;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final muted = enabled ? null : c.onSurfaceVariant;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: selected ? c.primary : c.outlineVariant, width: selected ? 2 : 1),
      ),
      child: MergeSemantics(
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.lg, Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Radio<PaymentMethod>(value: value, enabled: enabled),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: Space.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value.label, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: muted)),
                        Text(subtitle, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        if (extra != null) ...[const SizedBox(height: Space.sm), extra!],
                        if (footnote != null) ...[
                          const SizedBox(height: Space.sm),
                          Text(footnote!, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                ),
                if (icon != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.md, left: Space.sm),
                    child: Icon(icon, size: 22, color: c.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressSheet extends StatelessWidget {
  const _AddressSheet({required this.addresses, required this.selectedId});

  final List<Address> addresses;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Semantics(header: true, child: Text('Deliver to', style: t.titleLarge)),
          ),
          Flexible(
            child: RadioGroup<String>(
              groupValue: selectedId,
              onChanged: (id) => Navigator.pop(context, addresses.firstWhere((a) => a.id == id)),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in addresses)
                    RadioListTile<String>(
                      value: a.id!,
                      title: Text(a.name),
                      subtitle: Text('${a.oneLine}\n${displayPhone(a.phone)}'),
                      isThreeLine: true,
                    ),
                ],
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(PhosphorIconsRegular.plus, color: c.primary),
            title: Text('Add new address', style: t.titleSmall?.copyWith(color: c.primary)),
            onTap: () => Navigator.pop(context, _addNew),
          ),
        ],
      ),
    );
  }
}

class _PayBar extends StatelessWidget {
  const _PayBar({required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.outlineVariant))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
          child: FilledButton(
            onPressed: onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy) ...[
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.onSurfaceVariant),
                  ),
                  const SizedBox(width: Space.md),
                ],
                Flexible(child: Text(label, style: const TextStyle(fontFeatures: tabularFigures))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
