import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../data/admin.dart';
import '../widgets/admin_widgets.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key, this.status});

  final String? status; // a key of [orderFilters]

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  late String _filter = orderFilters.containsKey(widget.status) ? widget.status! : 'all';

  @override
  Widget build(BuildContext context) => AdminGate(
        child: Scaffold(
          appBar: AppBar(title: const Text('Orders')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: ChipBar(options: orderFilters, selected: _filter, onSelected: (f) => setState(() => _filter = f)),
              ),
              Expanded(child: _OrderList(filter: _filter)),
            ],
          ),
        ),
      );
}

class _OrderList extends ConsumerWidget {
  const _OrderList({required this.filter});

  final String filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = adminOrdersProvider(filter);
    return AsyncBody<List<Order>>(
      value: ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      loading: Skeletonizer(child: _Rows(orders: _skeleton)),
      data: (orders) => orders.isEmpty
          ? EmptyState(
              icon: PhosphorIconsRegular.receipt,
              title: 'No orders here',
              message: filter == 'all' ? 'Orders show up here as soon as customers place them.' : 'Try another filter.',
            )
          : RefreshIndicator(onRefresh: () => ref.refresh(provider.future), child: _Rows(orders: orders)),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: Space.xl + MediaQuery.paddingOf(context).bottom),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        final o = orders[i];
        return InkWell(
          onTap: () => context.push('/admin/orders/${o.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(o.number, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          Tag(o.status.label, tone: orderTone(o.status)),
                          if (o.needsRefund) const Tag('Needs refund', tone: TagTone.bad),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${o.address.name} · ${itemsSummary(o)}', style: t.bodyMedium),
                      Text(
                        '${formatDateTime(o.createdAt)} · ${paymentShort(o)}',
                        style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                Text(
                  formatInr(o.totalPaise),
                  style: t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

final _skeleton = [
  for (var i = 0; i < 6; i++)
    Order(
      id: '$i',
      number: 'SM100000',
      status: OrderStatus.confirmed,
      paymentMethod: PaymentMethod.cod,
      paymentStatus: PaymentStatus.pending,
      subtotalPaise: 7499900,
      deliveryFeePaise: 0,
      totalPaise: 7499900,
      address: const Address(name: 'Customer name', phone: '', line1: '', city: '', state: '', pincode: ''),
      createdAt: DateTime(2026, 10, 29),
      items: const [
        OrderItem(id: '', productName: 'Samsung Galaxy S25', variantName: '', unitPricePaise: 1, qty: 1),
      ],
    ),
];
