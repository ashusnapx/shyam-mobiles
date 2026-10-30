import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../feedback/data/feedback.dart' show FeedbackKind;
import '../../repairs/widgets/repair_widgets.dart';
import '../data/admin.dart';
import '../data/rules.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/feedback_card.dart';

class AdminOrderScreen extends ConsumerStatefulWidget {
  const AdminOrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<AdminOrderScreen> createState() => _AdminOrderScreenState();
}

class _AdminOrderScreenState extends ConsumerState<AdminOrderScreen> {
  bool _busy = false;

  /// One action at a time, its dialog or sheet included: a double tap would otherwise open two ship sheets or
  /// cancel twice (the second cancel adds a second "Cancelled by the store" note to the timeline).
  Future<void> _once(Future<void> Function() flow) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await flow();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write(String done, Future<void> Function() write) async {
    try {
      await write();
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    }
  }

  Future<void> _advance(Order o, OrderStatus to) async {
    switch (to) {
      case OrderStatus.shipped:
        final r = await showShipSheet(context, title: 'Ship ${o.number}', action: 'Mark shipped', courier: o.courier);
        if (r == null) return;
        return _write('Marked shipped',
            () => updateOrder(ref, o.id, to, courier: r.courier, tracking: r.tracking));
      case OrderStatus.delivered:
        final ok = await confirmAction(
          context,
          title: 'Mark delivered?',
          message: o.paymentMethod == PaymentMethod.cod
              ? 'This also records the ${formatInr(o.totalPaise)} cash as paid.'
              : 'The customer will see the order as delivered.',
          action: 'Mark delivered',
        );
        if (!ok) return;
      case OrderStatus.refunded:
        final ok = await confirmAction(
          context,
          title: 'Mark refunded?',
          message: o.paymentMethod == PaymentMethod.cod
              ? 'Only once the customer has their ${formatInr(o.totalPaise)} back in cash.'
              : 'Refund ${formatInr(o.totalPaise)} in the Razorpay dashboard first. Then mark it here.',
          action: 'Mark refunded',
        );
        if (!ok) return;
      default:
    }
    if (!mounted) return;
    await _write('Marked ${to.label.toLowerCase()}', () => updateOrder(ref, o.id, to));
  }

  Future<void> _cancel(Order o) async {
    final reason = await showDialog<String>(context: context, builder: (_) => _CancelDialog(order: o));
    if (reason == null) return;
    await _write('Order cancelled', () => updateOrder(ref, o.id, OrderStatus.cancelled, note: 'Cancelled by the store: $reason'));
  }

  Future<void> _editShipping(Order o) async {
    final r = await showShipSheet(
      context,
      title: 'Courier and tracking',
      action: 'Save',
      courier: o.courier,
      tracking: o.trackingNumber,
    );
    if (r == null) return;
    await _write('Saved', () => updateOrder(ref, o.id, o.status, courier: r.courier, tracking: r.tracking));
  }

  @override
  Widget build(BuildContext context) {
    final provider = adminOrderProvider(widget.orderId);
    final value = ref.watch(provider);
    final order = value.value;
    final forward = order == null
        ? const <OrderStatus>[]
        : [
            ...nextOrderStatuses(order.status).where((s) => s != OrderStatus.cancelled),
            // refunded outside the webhook (a partial or missed refund event): admin_update_order clears it
            if (order.needsRefund) OrderStatus.refunded,
          ];
    return AdminGate(
      child: Scaffold(
        appBar: AppBar(title: Text(order == null ? 'Order' : 'Order ${order.number}')),
        bottomNavigationBar: forward.isEmpty
            ? null
            : StickyBar(
                child: Row(
                  children: [
                    for (final s in forward)
                      Expanded(
                        // refunds are rare and follow money moving elsewhere, so they don't get the primary style
                        child: s == OrderStatus.refunded
                            ? OutlinedButton(
                                onPressed: _busy ? null : () => _once(() => _advance(order!, s)),
                                child: Text(_actionLabel(s)),
                              )
                            : FilledButton(
                                onPressed: _busy ? null : () => _once(() => _advance(order!, s)),
                                child: Text(_actionLabel(s)),
                              ),
                      ),
                  ],
                ),
              ),
        body: AsyncBody<Order>(
          value: value,
          onRetry: () => ref.invalidate(provider),
          loading: const Center(child: CircularProgressIndicator()),
          data: (o) => RefreshIndicator(
            onRefresh: () => ref.refresh(provider.future),
            child: _Body(
              order: o,
              busy: _busy,
              onCancel: () => _once(() => _cancel(o)),
              onEditShipping: () => _once(() => _editShipping(o)),
            ),
          ),
        ),
      ),
    );
  }
}

String _actionLabel(OrderStatus to) => switch (to) {
      OrderStatus.packed => 'Mark packed',
      OrderStatus.shipped => 'Ship',
      OrderStatus.delivered => 'Mark delivered',
      OrderStatus.refunded => 'Mark refunded',
      _ => to.label,
    };

class _Body extends StatelessWidget {
  const _Body({required this.order, required this.busy, required this.onCancel, required this.onEditShipping});

  final Order order;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onEditShipping;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final o = order;
    final a = o.address;
    final canCancel = nextOrderStatuses(o.status).contains(OrderStatus.cancelled);
    final shipped = const [OrderStatus.packed, OrderStatus.shipped, OrderStatus.delivered].contains(o.status);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.xl + MediaQuery.paddingOf(context).bottom),
      children: [
        if (o.needsRefund)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: NoteBox(
              'Refund due: ${formatInr(o.totalPaise)} was paid online and this order is cancelled. '
              'Refund it in the Razorpay dashboard${o.razorpayOrderId == null ? '' : ' (order ${o.razorpayOrderId})'}. '
              'The payment shows Refunded here once Razorpay confirms it, or tap Mark refunded.',
              tone: TagTone.bad,
              icon: PhosphorIconsBold.arrowCounterClockwise,
            ),
          ),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
                child: Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.xs,
                  children: [
                    Tag(o.status.label, tone: orderTone(o.status)),
                    Tag('${o.paymentMethod.label} · ${o.paymentStatus.label}'),
                  ],
                ),
              ),
              InfoRow('Placed', formatDateTime(o.createdAt)),
              InfoRow('Subtotal', formatInr(o.subtotalPaise)),
              if (o.discountPaise > 0)
                InfoRow(o.couponCode == null ? 'Discount' : 'Discount · ${o.couponCode}', '−${formatInr(o.discountPaise)}'),
              InfoRow('Delivery', o.deliveryFeePaise == 0 ? 'Free' : formatInr(o.deliveryFeePaise)),
              InfoRow('Total', formatInr(o.totalPaise), strong: true),
            ],
          ),
        ),
        const ListSection('Customer'),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                title: Text(a.name),
                subtitle: Text(displayPhone(a.phone)),
                trailing: IconButton(
                  tooltip: 'Call ${a.name}',
                  icon: const Icon(PhosphorIconsRegular.phone),
                  onPressed: () => openUri(context, telUri(a.phone)),
                ),
                onTap: () => openUri(context, telUri(a.phone)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
                child: SelectableText(a.oneLine, style: t.bodyMedium),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.sm),
                child: TextButton.icon(
                  onPressed: () => openUri(context, whatsAppUri(a.phone, text: orderUpdateText(o))),
                  icon: const WhatsAppIcon(),
                  label: const Text('Send update on WhatsApp'),
                ),
              ),
            ],
          ),
        ),
        CustomerFeedbackCard(kind: FeedbackKind.order, id: o.id),
        ListSection('Items (${o.items.fold(0, (n, i) => n + i.qty)})'),
        for (final item in o.items)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: _ItemCard(orderId: o.id, item: item),
          ),
        const ListSection('Shipping'),
        Text(
          o.courier == null
              ? (shipped ? 'No courier yet.' : 'Add the courier when you ship.')
              : '${o.courier}${o.trackingNumber == null ? '' : ' · ${o.trackingNumber}'}',
          style: t.bodyMedium?.copyWith(color: o.courier == null ? c.onSurfaceVariant : null),
        ),
        if (shipped)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: busy ? null : onEditShipping,
              icon: const Icon(PhosphorIconsRegular.pencilSimple),
              label: const Text('Edit courier & tracking'),
            ),
          ),
        const ListSection('Timeline'),
        for (final e in o.events.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Icon(PhosphorIconsFill.circle, size: 8, color: c.secondary),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.status.label, style: t.titleSmall),
                      if (e.note != null) Text(e.note!, style: t.bodySmall),
                      Text(formatDateTime(e.createdAt), style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (canCancel) ...[
          const SizedBox(height: Space.lg),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: c.error, side: BorderSide(color: c.error)),
            onPressed: busy ? null : onCancel,
            icon: const Icon(PhosphorIconsRegular.xCircle),
            label: const Text('Cancel order'),
          ),
        ],
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.orderId, required this.item});

  final String orderId;
  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 56, child: ProductImage(item.imagePath, radius: Radii.md, padding: Space.xs)),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.productName, style: t.titleSmall),
                      Text(
                        '${item.variantName} · Qty ${item.qty}',
                        style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Text(formatInr(item.lineTotalPaise), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: Space.sm),
            if (item.imeis.isNotEmpty)
              for (final imei in item.imeis)
                Text('IMEI $imei', style: t.bodySmall?.copyWith(fontFamily: 'monospace', color: c.onSurfaceVariant)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _ImeiSheet(orderId: orderId, item: item),
                ),
                icon: const Icon(PhosphorIconsRegular.barcode),
                label: Text(item.imeis.isEmpty ? 'Add IMEI${item.qty == 1 ? '' : 's'}' : 'Edit IMEI${item.qty == 1 ? '' : 's'}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImeiSheet extends ConsumerStatefulWidget {
  const _ImeiSheet({required this.orderId, required this.item});

  final String orderId;
  final OrderItem item;

  @override
  ConsumerState<_ImeiSheet> createState() => _ImeiSheetState();
}

class _ImeiSheetState extends ConsumerState<_ImeiSheet> {
  final _form = GlobalKey<FormState>();
  late final _fields = [
    for (var i = 0; i < widget.item.qty; i++)
      TextEditingController(text: i < widget.item.imeis.length ? widget.item.imeis[i] : ''),
  ];
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final imeis = [for (final f in _fields) f.text];
    setState(() => _error = imeisError(imeis, widget.item.qty));
    if (_error != null) return;
    setState(() => _busy = true);
    try {
      await setImeis(ref, widget.orderId, widget.item.id, imeis);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, 'IMEIs saved');
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetForm(
        formKey: _form,
        title: 'IMEI for ${widget.item.productName}',
        children: [
          Text(
            'One 15-digit IMEI per unit. Find it on the box or dial *#06#.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          for (final (i, f) in _fields.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: TextFormField(
                controller: f,
                decoration: InputDecoration(
                  labelText: _fields.length == 1 ? 'IMEI' : 'IMEI, unit ${i + 1}',
                  counter: LengthCounter(f, 15),
                ),
                keyboardType: TextInputType.number,
                autocorrect: false,
                enableSuggestions: false,
                // a pasted box label ("IMEI1: 35-209900-176148-1") keeps the 15 digits
                inputFormatters: const [DigitsFormatter(15)],
                textInputAction: i == _fields.length - 1 ? TextInputAction.done : TextInputAction.next,
                onFieldSubmitted: i == _fields.length - 1 ? (_) => _save() : null,
                style: const TextStyle(fontFamily: 'monospace', fontFeatures: [FontFeature.tabularFigures()]),
                validator: (v) => imeiFieldError(v ?? ''),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Save IMEIs')),
        ],
      );
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.order});

  final Order order;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final missing = tidy(_reason.text).isEmpty;
    return AlertDialog(
      scrollable: true, // the keyboard and large text can leave little room
      title: Text('Cancel ${o.number}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items go back into stock. The customer sees your reason.'
            '${o.paymentStatus == PaymentStatus.paid ? ' They paid ${formatInr(o.totalPaise)} online, so refund it in the Razorpay dashboard afterwards.' : ''}',
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _reason,
            autofocus: true,
            // order_events.note is ≤500 and the note is "Cancelled by the store: <reason>"
            inputFormatters: textInput(200),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Reason',
              errorText: _tried && missing ? 'Add a short reason' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      // Same rule as confirmChoice: destructive is quiet red text on the left, the safe choice is filled on the right.
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => missing ? setState(() => _tried = true) : Navigator.pop(context, tidy(_reason.text)),
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error, minimumSize: const Size(64, 44)),
          child: const Text('Cancel order'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          child: const Text('Keep order'),
        ),
      ],
    );
  }
}
