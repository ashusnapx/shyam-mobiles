import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/payments.dart';

/// The customer's view of refunds on their order: how much, for what, and where it is. Nothing when there are none.
class OrderRefunds extends ConsumerWidget {
  const OrderRefunds({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (orderId.isEmpty) return const SizedBox.shrink(); // the loading skeleton's placeholder order
    final refunds = ref.watch(orderRefundsProvider(orderId)).value ?? const [];
    if (refunds.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
      child: Card(
        child: Column(
          children: [
            for (final r in refunds.reversed)
              ListTile(
                leading: Icon(PhosphorIconsRegular.arrowCounterClockwise, color: c.secondary),
                title: Text('Refund of ${formatInr(r.amountPaise)}${r.full || r.items.isEmpty ? '' : ' for ${r.items.join(', ')}'}'),
                subtitle: Text(
                  switch (r.status) {
                    RefundStatus.processed when r.speedProcessed == 'instant' => 'Sent instantly on ${formatDate(r.createdAt)}.',
                    RefundStatus.processed => 'Sent to your original payment method. Banks usually take 5–7 working days.',
                    RefundStatus.pending => 'On its way to your original payment method.',
                    RefundStatus.failed => 'This refund didn’t go through. The shop will sort it out with you.',
                  },
                  style: t.bodySmall,
                ),
                trailing: Tag(r.status.label, tone: switch (r.status) {
                  RefundStatus.processed => TagTone.ok,
                  RefundStatus.pending => TagTone.deal,
                  RefundStatus.failed => TagTone.bad,
                }),
              ),
          ],
        ),
      ),
    );
  }
}
