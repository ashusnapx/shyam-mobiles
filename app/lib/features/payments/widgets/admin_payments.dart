import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../admin/widgets/admin_widgets.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../data/payments.dart';

/// Staff, on an order: refunds through Razorpay (everything left, or chosen items), payment links to send on WhatsApp,
/// and any dispute. The manual "Mark refunded" stays in the bottom bar for refunds made outside the app.
class OrderPaymentsSection extends ConsumerStatefulWidget {
  const OrderPaymentsSection({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<OrderPaymentsSection> createState() => _OrderPaymentsSectionState();
}

class _OrderPaymentsSectionState extends ConsumerState<OrderPaymentsSection> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final done = await action();
      if (done != null && mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _refund(OrderPayments p) async {
    final o = widget.order;
    final choice = await showModalBottomSheet<_RefundChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _RefundSheet(order: o, payments: p),
    );
    if (choice == null || !mounted) return null;
    final amount = formatInr(choice.amountPaise);
    final ok = await confirmChoice(
      context,
      title: 'Refund $amount?',
      message: 'Razorpay sends $amount back to how ${o.address.name} paid'
          '${choice.instant ? ', within minutes (Razorpay charges a small fee)' : ''}. This can’t be undone.',
      action: 'Refund $amount',
      keep: 'Don’t refund',
      destructive: true,
    );
    if (!ok || !mounted) return null;
    final status = await startRefund(ref, o.id, itemIds: choice.itemIds, restock: choice.restock, instant: choice.instant);
    return switch (status) {
      RefundStatus.processed => 'Refunded $amount',
      RefundStatus.pending => 'Refund of $amount sent to Razorpay',
      RefundStatus.failed => 'Razorpay couldn’t refund it. See the note on this order.',
    };
  }

  Future<String?> _sendLink(PaymentLink? open) async {
    final o = widget.order;
    final link = open ?? await createPaymentLink(ref, orderId: o.id);
    if (mounted) await openUri(context, whatsAppUri(link.customerPhone, text: paymentLinkText(link)));
    return null;
  }

  Future<String?> _cancelLink(PaymentLink link) async {
    final ok = await confirmChoice(
      context,
      title: 'Cancel this link?',
      message: 'The customer won’t be able to pay ${formatInr(link.amountPaise)} with it any more.',
      action: 'Cancel link',
      keep: 'Keep link',
      destructive: true,
    );
    if (!ok || !mounted) return null;
    await cancelPaymentLink(ref, link);
    return 'Link cancelled';
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final value = ref.watch(orderPaymentsProvider(o.id));
    final p = value.value;
    if (p == null) {
      return value.hasError
          ? InlineError(error: value.error!, onRetry: () => ref.invalidate(orderPaymentsProvider(o.id)))
          : const SizedBox.shrink();
    }
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final choices = refundChoices(o, p.refunds);
    final left = refundablePaise(o, p.refunds);
    final open = p.links.where((l) => l.isOpen).firstOrNull;
    final showLinks = canSendLink(o) || p.links.isNotEmpty;
    if (p.refunds.isEmpty && !choices.full && !choices.items && !showLinks && p.disputes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in p.disputes)
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: NoteBox(
              [
                'Dispute: ${formatInr(d.amountPaise)}, ${d.status.replaceAll('_', ' ')}',
                ?d.reason,
                if (d.open && d.respondBy != null) 'Reply by ${formatDateTime(d.respondBy!)}',
                if (d.open) 'Answer in the Razorpay dashboard with the invoice, IMEI and delivery proof.',
              ].join('. '),
              tone: d.open ? TagTone.bad : TagTone.info,
              icon: PhosphorIconsBold.scales,
            ),
          ),
        const ListSection('Payments'),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final r in p.refunds)
                ListTile(
                  leading: const Icon(PhosphorIconsRegular.arrowCounterClockwise),
                  title: Text('Refund ${formatInr(r.amountPaise)}${r.full ? '' : ' · ${r.items.join(', ')}'}'),
                  subtitle: Text([
                    formatDateTime(r.createdAt),
                    if (r.speedProcessed == 'instant') 'Instant',
                    ?r.failure,
                  ].join(' · ')),
                  trailing: Tag(r.status.label, tone: switch (r.status) {
                    RefundStatus.processed => TagTone.ok,
                    RefundStatus.pending => TagTone.deal,
                    RefundStatus.failed => TagTone.bad,
                  }),
                ),
              if (choices.full || choices.items)
                Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(() => _refund(p)),
                    icon: const Icon(PhosphorIconsRegular.arrowCounterClockwise),
                    label: Text(choices.full ? 'Refund ${formatInr(left)}' : 'Refund items'),
                  ),
                ),
              for (final l in p.links)
                ListTile(
                  leading: const Icon(PhosphorIconsRegular.link),
                  title: Text('Payment link · ${formatInr(l.amountPaise)}'),
                  subtitle: Text(l.statusLabel),
                  trailing: l.isOpen
                      ? IconButton(
                          tooltip: 'Cancel link',
                          onPressed: _busy ? null : () => _run(() => _cancelLink(l)),
                          icon: Icon(PhosphorIconsRegular.xCircle, color: c.error),
                        )
                      : null,
                ),
              if (canSendLink(o))
                Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : () => _run(() => _sendLink(open)),
                    icon: const WhatsAppIcon(),
                    label: Text(open == null ? 'Send payment link' : 'Send the link again'),
                  ),
                ),
              if (canSendLink(o) && open == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
                  child: Text(
                    'A Razorpay link for ${formatInr(o.totalPaise)}, valid 3 days. The order turns paid when the customer pays.',
                    style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RefundChoice {
  const _RefundChoice({required this.amountPaise, this.itemIds, this.restock = false, this.instant = false});

  final int amountPaise; // what the sheet showed; the server works it out again from the order
  final List<String>? itemIds; // null: everything left
  final bool restock;
  final bool instant;
}

class _RefundSheet extends StatefulWidget {
  const _RefundSheet({required this.order, required this.payments});

  final Order order;
  final OrderPayments payments;

  @override
  State<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<_RefundSheet> {
  late final _choices = refundChoices(widget.order, widget.payments.refunds);
  late bool _everything = _choices.full;
  final _picked = <String>{};
  bool _restock = false;
  bool _instant = false;

  int get _amount => _everything
      ? refundablePaise(widget.order, widget.payments.refunds)
      : widget.payments.lines.where((l) => _picked.contains(l.id)).fold(0, (n, l) => n + l.paidPaise);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final cancelled = widget.order.status == OrderStatus.cancelled;
    final amount = _amount;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg + MediaQuery.paddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Refund ${widget.order.number}', style: t.titleLarge)),
          const SizedBox(height: Space.md),
          if (_choices.full && _choices.items)
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Everything left')),
                ButtonSegment(value: false, label: Text('Some items')),
              ],
              selected: {_everything},
              onSelectionChanged: (s) => setState(() => _everything = s.first),
            ),
          if (_everything)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Text(
                '${formatInr(amount)}: what’s left of the ${formatInr(widget.order.totalPaise)} paid, delivery included.',
                style: t.bodyMedium,
              ),
            )
          else
            for (final l in widget.payments.lines)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: l.refundId != null || _picked.contains(l.id),
                onChanged: l.refundId != null || l.paidPaise <= 0
                    ? null
                    : (v) => setState(() => v == true ? _picked.add(l.id) : _picked.remove(l.id)),
                title: Text(l.name),
                subtitle: Text(l.refundId != null ? 'Already refunded' : 'Qty ${l.qty} · ${formatInr(l.paidPaise)} paid'),
              ),
          if (!cancelled)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _restock,
              onChanged: (v) => setState(() => _restock = v ?? false),
              title: const Text('Put the items back in stock'),
              subtitle: const Text('Only if they came back unopened and sellable.'),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _instant,
            onChanged: (v) => setState(() => _instant = v ?? false),
            title: const Text('Instant refund'),
            subtitle: const Text('In the customer’s account within minutes, for a Razorpay fee of ₹7.99–₹14.99 + GST. '
                'Otherwise 5–7 working days, free.'),
          ),
          const SizedBox(height: Space.md),
          FilledButton(
            onPressed: amount < 100
                ? null
                : () => Navigator.pop(
                      context,
                      _RefundChoice(
                        amountPaise: amount,
                        itemIds: _everything ? null : _picked.toList(),
                        restock: _restock && !cancelled,
                        instant: _instant,
                      ),
                    ),
            child: Text(amount < 100 ? 'Pick what to refund' : 'Refund ${formatInr(amount)}'),
          ),
          if (!_choices.full || !_choices.items)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _choices.full ? 'A cancelled order is refunded in full.' : 'To refund all of it, cancel the order first.',
                style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
