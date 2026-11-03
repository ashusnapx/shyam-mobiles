import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/widgets.dart';
import '../../repairs/data/booking_days.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../../feedback/data/feedback.dart';
import '../../notifications/widgets/notification_widgets.dart';
import '../data/admin.dart';
import '../data/catalogue.dart';
import '../data/rules.dart';
import '../widgets/admin_widgets.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AdminGate(
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () => Future.wait([
                ref.refresh(adminDashboardProvider.future),
                ref.refresh(needsActionProvider.future),
                ref.refresh(feedbackNewCountProvider.future),
                ref.refresh(catalogueSummaryProvider(shownStock).future),
              ]),
              child: ListView(
                padding: const EdgeInsets.only(bottom: Space.xl),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('EEEE, d MMMM').format(istNow()),
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              Semantics(
                                header: true,
                                child: Text('Today at the shop', style: Theme.of(context).textTheme.displaySmall),
                              ),
                            ],
                          ),
                        ),
                        const NotificationBell(), // new orders, bookings, quote answers, feedback, low stock
                      ],
                    ),
                  ),
                  const _Today(),
                  // what to do next sits above the numbers that only need a glance
                  SectionHeader(
                    'Needs action',
                    actionLabel: 'All orders',
                    onAction: () => context.push('/admin/orders?status=open'),
                  ),
                  const _NeedsAction(),
                  const _Alerts(),
                  const SectionHeader('Manage'),
                  const _QuickActions(),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Customers can see these variants: the stock alerts count only them, per variant (low = 1–3 left, out = 0).
const shownStock = (
  query: '',
  categoryId: null,
  brandId: null,
  stock: StockFilter.all,
  visibility: VisibilityFilter.shown,
  sort: CatalogueSort.name,
);

/// Four numbers in one block: today's orders and revenue, and what is still open.
class _Today extends ConsumerWidget {
  const _Today();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminDashboardProvider);
    if (value.hasError && !value.hasValue) {
      return InlineError(error: value.error!, onRetry: () => ref.invalidate(adminDashboardProvider));
    }
    final d = value.value;
    int n(String k) => d?[k] ?? 0;
    final c = Theme.of(context).colorScheme;
    const cells = [
      (PhosphorIconsRegular.receipt, 'Orders today', 'orders_today', '/admin/orders?status=today'),
      (PhosphorIconsRegular.currencyInr, 'Revenue today', 'revenue_today_paise', '/admin/orders?status=today'),
      (PhosphorIconsRegular.package, 'Open orders', 'open_orders', '/admin/orders?status=open'),
      (PhosphorIconsRegular.wrench, 'Open repairs', 'open_repairs', '/admin/repairs'),
    ];
    Widget cell(int i) {
      final (icon, label, key, route) = cells[i];
      return Expanded(
        child: _Stat(icon, label, n(key), route, format: key == 'revenue_today_paise' ? shortInr : _Stat._plain),
      );
    }

    return Skeletonizer(
      enabled: d == null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [cell(0), const VerticalDivider(width: 1), cell(1)])),
              Divider(height: 1, color: c.outlineVariant),
              IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [cell(2), const VerticalDivider(width: 1), cell(3)])),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.label, this.count, this.route, {this.format = _plain});

  final IconData icon;
  final String label;
  final int count;
  final String route;
  final String Function(int) format;

  static String _plain(int n) => '$n';

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$label, ${format(count)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: c.onSurfaceVariant),
                  const SizedBox(width: Space.xs),
                  Expanded(child: Text(label, style: t.labelMedium?.copyWith(color: c.onSurfaceVariant))),
                ],
              ),
              const SizedBox(height: Space.xs),
              // counts up when the numbers arrive, and rolls when they change
              CountTo(count, format: format, fromZero: true, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Only what needs a look, each opening its list; "All clear" when nothing does.
class _Alerts extends ConsumerWidget {
  const _Alerts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(adminDashboardProvider).value;
    final stock = ref.watch(catalogueSummaryProvider(shownStock)).value; // absent if it fails: the rest still shows
    final fresh = ref.watch(feedbackNewCountProvider).value ?? 0; // feedback with status new
    if (d == null) return const SizedBox.shrink();
    int n(String k) => d[k] ?? 0;
    final alerts = [
      (PhosphorIconsBold.arrowCounterClockwise, 'Needs refund', n('needs_refund'), '/admin/orders?status=needs_refund'),
      (PhosphorIconsRegular.hourglassMedium, 'Awaiting approval', n('repairs_awaiting_approval'),
          '/admin/repairs?status=awaiting_approval'),
      (PhosphorIconsRegular.trendDown, 'Low stock', stock?.low ?? 0, '/admin/catalogue?stock=low&visibility=shown'),
      (PhosphorIconsBold.warning, 'Out of stock', stock?.out ?? 0, '/admin/catalogue?stock=out&visibility=shown'),
      (PhosphorIconsRegular.chatCircleText, 'New feedback', fresh, '/admin/feedback'),
    ].where((a) => a.$3 > 0).toList();
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final (bg, fg) = toneColors(TagTone.deal);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
      child: alerts.isEmpty
          ? Row(
              children: [
                Icon(PhosphorIconsRegular.checkCircle, color: c.secondary),
                const SizedBox(width: Space.sm),
                Text('All clear', style: t.titleSmall),
              ],
            )
          : Wrap(
              spacing: Space.sm,
              children: [
                for (final (icon, label, count, route) in alerts)
                  ActionChip(
                    avatar: Icon(icon, size: 16, color: fg),
                    label: Text('$label $count'),
                    labelStyle: t.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700),
                    backgroundColor: bg,
                    side: BorderSide.none,
                    onPressed: () => context.push(route),
                  ),
              ],
            ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    // by how often the shop uses them; the rest under "More"
    // each in the colour of the part of the app it opens; the one create action is ink
    const daily = [
      (PhosphorIconsRegular.plus, 'Add product', '/admin/products/new', (BrandColors.ink, Colors.white)),
      (PhosphorIconsRegular.package, 'Products & stock', '/admin/catalogue', Worlds.admin),
      (PhosphorIconsRegular.receipt, 'Orders', '/admin/orders', Worlds.shop),
      (PhosphorIconsRegular.wrench, 'Repairs', '/admin/repairs', Worlds.repairs),
      (PhosphorIconsRegular.link, 'Payment link', '/admin/payment-links', Worlds.cart),
      (PhosphorIconsRegular.sealPercent, 'Offers', '/admin/offers', Worlds.offers),
    ];
    const more = [
      (PhosphorIconsRegular.stack, 'Groups', '/admin/groups', (BrandColors.violetMist, BrandColors.violet)),
      (PhosphorIconsRegular.flagBanner, 'Banners', '/admin/banners', Worlds.account),
      (PhosphorIconsRegular.gearSix, 'Settings', '/admin/settings', (BrandColors.slateMist, BrandColors.slate)),
    ];
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget tile(IconData icon, String label, String route, Tint tint) => InkWell(
          borderRadius: BorderRadius.circular(Radii.lg),
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Column(
              children: [
                IconWell(icon, tint: tint, size: 52, radius: Radii.lg, iconSize: IconSizes.lg),
                const SizedBox(height: Space.xs),
                Text(label, textAlign: TextAlign.center, style: t.labelMedium),
              ],
            ),
          ),
        );
    // three a row, so "Products & stock" and "Add product" fit at large text
    Widget grid(List<(IconData, String, String, Tint)> actions) => Column(
          children: [
            for (var i = 0; i < actions.length; i += 3)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = i; j < i + 3; j++)
                    Expanded(
                      child: j < actions.length ? tile(actions[j].$1, actions[j].$2, actions[j].$3, actions[j].$4) : const SizedBox(),
                    ),
                ],
              ),
          ],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          grid(daily),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.sm, Space.xs),
            child: Text('More', style: t.labelLarge?.copyWith(color: c.onSurfaceVariant)),
          ),
          grid(more),
        ],
      ),
    );
  }
}

/// One-tap Pack / Ship / Confirm. Rows hide immediately and come back if the write fails.
class _NeedsAction extends ConsumerStatefulWidget {
  const _NeedsAction();

  @override
  ConsumerState<_NeedsAction> createState() => _NeedsActionState();
}

class _NeedsActionState extends ConsumerState<_NeedsAction> {
  final _hidden = <String>{};

  Future<void> _run(String id, String done, Future<void> Function() write) async {
    setState(() => _hidden.add(id));
    unawaited(HapticFeedback.selectionClick());
    try {
      await write();
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hidden.remove(id));
      showMessage(context, adminError(e));
    }
  }

  Future<void> _ship(Order o) async {
    final r = await showShipSheet(context, title: 'Ship ${o.number}', action: 'Mark shipped', courier: o.courier);
    if (r == null) return;
    await _run(o.id, '${o.number} shipped',
        () => updateOrder(ref, o.id, OrderStatus.shipped, courier: r.courier, tracking: r.tracking));
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(needsActionProvider);
    if (value.hasError && !value.hasValue) {
      return InlineError(error: value.error!, onRetry: () => ref.invalidate(needsActionProvider));
    }
    final data = value.value;
    if (data == null) {
      return Skeletonizer(
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
              const _Row(icon: PhosphorIconsRegular.receipt, number: 'SM100000', tag: Tag('Confirmed', tone: TagTone.info),
                  subtitle: 'Galaxy S25 · ₹74,999 · COD', action: 'Pack'),
          ],
        ),
      );
    }
    final orders = data.orders.where((o) => !_hidden.contains(o.id)).toList();
    final repairs = data.repairs.where((r) => !_hidden.contains(r.id)).toList();
    if (orders.isEmpty && repairs.isEmpty) {
      final c = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
        child: Row(
          children: [
            Icon(PhosphorIconsRegular.checkCircle, color: c.secondary),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text('All caught up. New orders and repair requests show up here.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final o in orders)
          _Row(
            icon: o.status == OrderStatus.confirmed ? PhosphorIconsRegular.receipt : PhosphorIconsRegular.package,
            number: o.number,
            tag: Tag(o.status.label, tone: orderTone(o.status)),
            subtitle: '${itemsSummary(o)} · ${formatInr(o.totalPaise)} · ${paymentShort(o)}',
            onTap: () => context.push('/admin/orders/${o.id}'),
            action: o.status == OrderStatus.confirmed ? 'Pack' : 'Ship',
            onAction: o.status == OrderStatus.confirmed
                ? () => _run(o.id, '${o.number} packed', () => updateOrder(ref, o.id, OrderStatus.packed))
                : () => _ship(o),
          ),
        for (final r in repairs)
          _Row(
            icon: PhosphorIconsRegular.wrench,
            number: r.number,
            tag: Tag(r.status.label, tone: repairTone(r.status)),
            subtitle: '${r.deviceModel} · ${r.issue.label} · ${repairWhen(r)}',
            onTap: () => context.push('/admin/repairs/${r.id}'),
            action: 'Confirm',
            onAction: () => _run(r.id, '${r.number} confirmed',
                () => updateRepairStatus(ref, r.id, RepairStatus.confirmed)),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.number,
    required this.tag,
    required this.subtitle,
    required this.action,
    this.onTap,
    this.onAction,
  });

  final IconData icon;
  final String number;
  final Widget tag;
  final String subtitle;
  final String action;
  final VoidCallback? onTap;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.outlineVariant))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: c.surfaceContainer, borderRadius: BorderRadius.circular(Radii.md)),
                child: SizedBox.square(dimension: 40, child: Icon(icon, size: 20, color: c.onSurfaceVariant)),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [Text(number, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)), tag],
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48), padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: onAction,
                child: Text(action, semanticsLabel: '$action $number'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
