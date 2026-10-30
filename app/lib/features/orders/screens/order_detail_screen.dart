import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../cart/data/cart.dart';
import '../../checkout/data/payment.dart';
import '../../checkout/screens/widgets.dart';
import '../../feedback/widgets/feedback_widgets.dart';
import '../data/orders.dart';

String _paymentLine(Order o) => switch ((o.paymentMethod, o.paymentStatus)) {
      (_, PaymentStatus.refunded) => 'Refunded',
      (PaymentMethod.razorpay, PaymentStatus.paid) => 'Paid online',
      (PaymentMethod.razorpay, _) => 'Not paid yet',
      (PaymentMethod.cod, PaymentStatus.paid) => 'Paid on delivery',
      (PaymentMethod.cod, _) => 'Cash on delivery',
    };

String _kicker(Order o) => o.needsRefund
    ? 'Refund due'
    : switch (o.status) {
        OrderStatus.pendingPayment => 'Payment pending',
        OrderStatus.confirmed => 'Order received',
        OrderStatus.packed => 'Getting ready',
        OrderStatus.shipped => 'On its way',
        OrderStatus.delivered => 'All done',
        OrderStatus.cancelled => 'Order closed',
        OrderStatus.refunded => 'Money returned',
      };

IconData _stepIcon(OrderStatus s) => switch (s) {
      OrderStatus.pendingPayment => PhosphorIconsBold.receipt,
      OrderStatus.confirmed => PhosphorIconsBold.check,
      OrderStatus.packed => PhosphorIconsBold.package,
      OrderStatus.shipped => PhosphorIconsBold.truck,
      OrderStatus.delivered => PhosphorIconsBold.houseLine,
      OrderStatus.cancelled => PhosphorIconsBold.x,
      OrderStatus.refunded => PhosphorIconsBold.arrowCounterClockwise,
    };

void _say(ScaffoldMessengerState m, String text) => m
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));
    return Scaffold(
      appBar: AppBar(title: Text(order.value == null ? 'Order' : 'Order ${order.value!.number}')),
      body: AsyncBody(
        value: order,
        onRetry: () => ref.invalidate(orderProvider(orderId)),
        loading: Skeletonizer(child: _OrderBody(order: placeholderOrder)),
        data: (o) => RefreshIndicator(
          onRefresh: () => ref.refresh(orderProvider(orderId).future),
          child: _OrderBody(order: o),
        ),
      ),
    );
  }
}

class _OrderBody extends StatelessWidget {
  const _OrderBody({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final o = order;
    final hasImeis = o.items.any((i) => i.imeis.isNotEmpty);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: Space.xxl + MediaQuery.paddingOf(context).bottom),
      children: [
        _StatusHero(order: o),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 0),
          child: _Timeline(steps: buildTimeline(o)),
        ),
        if (o.status == OrderStatus.delivered)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 0),
            child: RateCard(title: 'How was your order?', orderId: o.id),
          ),
        const SectionHeader('Items'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: Column(
            children: [
              for (final item in o.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 64, child: ProductImage(item.imagePath, radius: Radii.md, padding: 6)),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName, style: t.titleSmall),
                                Text(
                                  [if (item.variantName.isNotEmpty) item.variantName, 'Qty ${item.qty}'].join(' · '),
                                  style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                                ),
                                for (final imei in item.imeis)
                                  Padding(
                                    padding: const EdgeInsets.only(top: Space.xs),
                                    child: SelectableText(
                                      'IMEI $imei',
                                      style: t.bodySmall?.copyWith(
                                        fontFamily: 'monospace',
                                        color: c.onSurfaceVariant,
                                        fontFeatures: tabularFigures,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: Space.sm),
                          Text(
                            formatInr(item.lineTotalPaise),
                            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (hasImeis)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(PhosphorIconsRegular.sealCheck, size: 16, color: c.secondary),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        'Check it: dial *#06# on the phone and match the box label.',
                        style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SectionHeader('Delivery address'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.address.name, style: t.titleSmall),
                  const SizedBox(height: Space.xs),
                  Text(o.address.oneLine, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                  const SizedBox(height: Space.xs),
                  Text(displayPhone(o.address.phone), style: t.bodySmall),
                ],
              ),
            ),
          ),
        ),
        const SectionHeader('Payment'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${o.paymentMethod.label} · ${_paymentLine(o)}', style: t.bodyMedium),
                  const SizedBox(height: Space.xs),
                  TotalsRows(
                    subtotalPaise: o.subtotalPaise,
                    deliveryFeePaise: o.deliveryFeePaise,
                    discountPaise: o.discountPaise,
                    discountLabel: o.couponCode,
                    totalPaise: o.totalPaise,
                  ),
                ],
              ),
            ),
          ),
        ),
        _Actions(order: o),
      ],
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final o = order;
    final fg = c.onPrimaryContainer;
    final tracking = o.trackingNumber;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_kicker(o).toUpperCase(), style: t.labelSmall?.copyWith(color: fg, letterSpacing: 1)),
          const SizedBox(height: 6),
          Semantics(
            header: true,
            child: Text(o.status.label, style: t.displaySmall?.copyWith(color: fg)),
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Placed ${formatDate(o.createdAt)} · ${_paymentLine(o)}',
            style: t.bodySmall?.copyWith(color: fg.withValues(alpha: 0.85)),
          ),
          if (o.canRetryPayment)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'Pay by ${DateFormat('h:mm a').format(o.reservedUntil!.toLocal())} to keep this order.',
                style: t.bodySmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ),
          if ((tracking == null || tracking.isEmpty) && o.courier != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text('Delivery by ${o.courier}', style: t.bodySmall?.copyWith(color: fg)),
            ),
          if (tracking != null && tracking.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: Space.md),
              padding: const EdgeInsets.only(left: Space.md),
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        if (o.courier != null) TextSpan(text: '${o.courier} · '),
                        TextSpan(
                          text: tracking,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
                        ),
                      ]),
                      style: t.bodySmall?.copyWith(color: c.onSurface),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: tracking));
                      _say(messenger, 'Tracking number copied');
                    },
                    icon: const Icon(PhosphorIconsRegular.copy, size: 18),
                    label: const Text('Copy', semanticsLabel: 'Copy tracking number'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps});

  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        for (final (i, s) in steps.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: !s.done
                              ? c.surfaceContainer
                              : s.status == OrderStatus.cancelled
                                  ? c.error
                                  : c.secondary,
                          border: s.done ? null : Border.all(color: c.outlineVariant, width: 2),
                        ),
                        child: SizedBox.square(
                          dimension: 28,
                          child: Icon(
                            _stepIcon(s.status),
                            size: 15,
                            color: !s.done
                                ? c.onSurfaceVariant
                                : s.status == OrderStatus.cancelled
                                    ? c.onError
                                    : c.onSecondary,
                          ),
                        ),
                      ),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: s.done && steps[i + 1].done ? c.secondary : c.outlineVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    container: true,
                    label: s.done ? null : 'Upcoming',
                    child: Padding(
                      padding: const EdgeInsets.only(top: Space.xs, bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.title, style: t.titleSmall?.copyWith(color: s.done ? null : c.onSurfaceVariant)),
                          if (s.at != null || s.note != null)
                            Text(
                              [if (s.at != null) formatDateTime(s.at!), ?s.note].join(' · '),
                              style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.order});

  final Order order;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _busy = false;
  bool _asking = false; // the confirm dialog is up

  Order get o => widget.order;

  Future<void> _retry() async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final r = await container.read(paymentFlowProvider.notifier).pay(o.id);
    if (r == null) return;
    if (r.outcome == PayOutcome.paid) unawaited(HapticFeedback.mediumImpact());
    if (r.message ?? (r.outcome == PayOutcome.paid ? 'Payment received. Your order is confirmed.' : null) case final m?) {
      _say(messenger, m);
    }
    container.invalidate(orderProvider(o.id));
  }

  Future<void> _cancel() async {
    if (_busy || _asking) return; // a double tap would open two dialogs and cancel twice
    _asking = true;
    final paid = o.paymentStatus == PaymentStatus.paid;
    final ok = await confirmChoice(
      context,
      title: 'Cancel this order?',
      message: paid
          ? 'We’ll refund ${formatInr(o.totalPaise)} to your original payment method. Banks usually take 5–7 working days.'
          : o.status == OrderStatus.pendingPayment
              ? 'If you already paid, we’ll refund it in full.'
              : 'This can’t be undone.',
      action: 'Cancel order',
      keep: 'Keep order',
      destructive: true,
    ).whenComplete(() => _asking = false);
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      await container.read(supabaseProvider).rpc<void>('cancel_order', params: {'p_order_id': o.id});
      _say(messenger, 'Order cancelled');
    } catch (e) {
      _say(messenger, friendlyError(e));
    } finally {
      container.invalidate(orderProvider(o.id));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reorder() async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      final added = await reorder(container.read(supabaseProvider), container.read(cartProvider.notifier), o);
      if (added == 0) {
        _say(messenger, 'These items are out of stock now.');
        return;
      }
      if (added < o.items.length) _say(messenger, 'Some items are out of stock now.');
      router.go('/cart');
    } catch (e) {
      _say(messenger, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Uri uri, String fallback) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await launchExternal(uri)) _say(messenger, fallback);
  }

  @override
  Widget build(BuildContext context) {
    final stage = ref.watch(paymentFlowProvider);
    final store = ref.watch(storeSettingsProvider).value;
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (o.canRetryPayment) ...[
            FilledButton(
              onPressed: stage == PayStage.idle && !_busy ? _retry : null,
              child: Text(
                stage == PayStage.idle ? 'Pay ${formatInr(o.totalPaise)}' : stage.label,
                style: const TextStyle(fontFeatures: tabularFigures),
              ),
            ),
            const SizedBox(height: Space.md),
          ],
          if (o.canCancel) ...[
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: c.error),
              onPressed: _busy || stage != PayStage.idle ? null : _cancel,
              child: Text(_busy ? 'Cancelling…' : 'Cancel order'),
            ),
            const SizedBox(height: Space.md),
          ],
          if (o.status == OrderStatus.cancelled) ...[
            OutlinedButton.icon(
              onPressed: _busy ? null : _reorder,
              icon: const Icon(PhosphorIconsRegular.arrowClockwise),
              label: const Text('Reorder'),
            ),
            const SizedBox(height: Space.md),
          ],
          if (store != null)
            Row(
              children: [
                for (final (i, (icon, label, uri, fallback)) in [
                  (
                    const Icon(PhosphorIconsRegular.phone, size: 20) as Widget,
                    'Call store',
                    Uri(scheme: 'tel', path: store.storePhone),
                    'Couldn’t open the phone app. Call ${displayPhone(store.storePhone)}.',
                  ),
                  (
                    const WhatsAppIcon(size: 20),
                    'WhatsApp',
                    Uri.https('wa.me', '/${store.storePhone.replaceAll(RegExp(r'\D'), '')}', {
                      'text': 'Hi, about order ${o.number}',
                    }),
                    'Couldn’t open WhatsApp. Message ${displayPhone(store.storePhone)}.',
                  ),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _open(uri, fallback),
                      icon: icon,
                      label: Text(label, textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
