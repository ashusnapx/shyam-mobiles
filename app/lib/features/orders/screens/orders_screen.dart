import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../checkout/screens/widgets.dart';
import '../data/orders.dart';

/// Status label for lists and the detail hero. A paid-then-cancelled order reads "Refund due".
class OrderStatusTag extends StatelessWidget {
  const OrderStatusTag(this.order, {super.key});

  final Order order;

  @override
  Widget build(BuildContext context) {
    if (order.needsRefund) return const Tag('Refund due', tone: TagTone.deal);
    return Tag(order.status.label, tone: switch (order.status) {
      OrderStatus.pendingPayment => TagTone.deal,
      OrderStatus.delivered => TagTone.ok,
      OrderStatus.cancelled || OrderStatus.refunded => TagTone.bad,
      _ => TagTone.info,
    });
  }
}

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider);
    // Reached with go() from the checkout result there's nothing below; back goes to Account instead of leaving the app.
    final canPop = context.canPop();
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/account');
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Orders'),
          leading: canPop ? null : BackButton(onPressed: () => context.go('/account')),
        ),
        body: AsyncBody(
          value: orders,
          onRetry: () => ref.invalidate(ordersProvider),
          loading: Skeletonizer(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Space.lg),
              children: [
                for (var i = 0; i < 4; i++)
                  Padding(padding: const EdgeInsets.only(bottom: Space.md), child: _OrderTile(placeholderOrder)),
              ],
            ),
          ),
          data: (page) {
            if (page.orders.isEmpty) {
              return EmptyState(
                icon: PhosphorIconsRegular.package,
                title: 'No orders yet',
                message: 'Orders you place show up here.',
                action: FilledButton(onPressed: () => context.go('/'), child: const Text('Start shopping')),
              );
            }
            final n = page.orders.length;
            return RefreshIndicator(
              onRefresh: () => ref.refresh(ordersProvider.future),
              child: NotificationListener<ScrollNotification>(
                onNotification: (s) {
                  if (page.hasMore && s.metrics.extentAfter < 400) unawaited(ref.read(ordersProvider.notifier).loadMore());
                  return false;
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // edge-to-edge: keep the last order clear of the system nav bar
                  padding: const EdgeInsets.all(Space.lg) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                  itemCount: n + (page.hasMore ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                  itemBuilder: (_, i) => i < n
                      ? _OrderTile(page.orders[i])
                      : page.moreFailed
                          ? Center(
                              child: TextButton.icon(
                                onPressed: () => ref.read(ordersProvider.notifier).loadMore(retry: true),
                                icon: const Icon(PhosphorIconsRegular.arrowClockwise),
                                label: const Text('Couldn’t load more. Try again'),
                              ),
                            )
                          : const Padding(
                              padding: EdgeInsets.all(Space.lg),
                              child: Center(child: CircularProgressIndicator(semanticsLabel: 'Loading more orders')),
                            ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile(this.order);

  final Order order;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final count = order.items.fold<int>(0, (sum, i) => sum + i.qty);
    return Card(
      child: InkWell(
        onTap: () => context.push('/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: ProductImage(order.items.firstOrNull?.imagePath, radius: Radii.md, padding: 6),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      children: [
                        Text(order.number, style: t.titleSmall?.copyWith(fontFeatures: tabularFigures)),
                        OrderStatusTag(order),
                      ],
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      '${formatDate(order.createdAt)} · $count ${count == 1 ? 'item' : 'items'}',
                      style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      formatInr(order.totalPaise),
                      style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures),
                    ),
                  ],
                ),
              ),
              Icon(PhosphorIconsRegular.caretRight, size: 18, color: c.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
