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
import '../../../core/widgets/widgets.dart';
import '../../repairs/data/booking_days.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../../feedback/data/feedback.dart';
import '../data/admin.dart';
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
              ]),
              child: ListView(
                padding: const EdgeInsets.only(bottom: Space.xl),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
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
                  const _Stats(),
                  SectionHeader(
                    'Manage',
                    actionLabel: 'All products',
                    onAction: () => context.push('/admin/products'),
                  ),
                  const _QuickActions(),
                  SectionHeader(
                    'Needs action',
                    actionLabel: 'All orders',
                    onAction: () => context.push('/admin/orders?status=open'),
                  ),
                  const _NeedsAction(),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Stats extends ConsumerWidget {
  const _Stats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminDashboardProvider);
    if (value.hasError && !value.hasValue) {
      return InlineError(error: value.error!, onRetry: () => ref.invalidate(adminDashboardProvider));
    }
    final d = value.value;
    int n(String k) => d?[k] ?? 0;
    final fresh = ref.watch(feedbackNewCountProvider).value ?? 0; // feedback with status new
    final tiles = [
      _Tile(PhosphorIconsRegular.receipt, 'Orders today', n('orders_today'), '/admin/orders?status=today'),
      _Tile(PhosphorIconsRegular.currencyInr, 'Revenue today', n('revenue_today_paise'),
          '/admin/orders?status=today', format: shortInr),
      _Tile(PhosphorIconsRegular.package, 'Open orders', n('open_orders'), '/admin/orders?status=open'),
      _Tile(PhosphorIconsRegular.wrench, 'Open repairs', n('open_repairs'), '/admin/repairs'),
      _Tile(PhosphorIconsRegular.hourglassMedium, 'Awaiting approval', n('repairs_awaiting_approval'),
          '/admin/repairs?status=awaiting_approval'),
      _Tile(PhosphorIconsBold.warning, 'Low stock', n('low_stock'), '/admin/products?stock=low',
          tone: n('low_stock') > 0 ? TagTone.deal : null),
      _Tile(PhosphorIconsBold.arrowCounterClockwise, 'Needs refund', n('needs_refund'),
          '/admin/orders?status=needs_refund',
          tone: n('needs_refund') > 0 ? TagTone.bad : null),
      _Tile(PhosphorIconsRegular.chatCircleText, 'New feedback', fresh, '/admin/feedback',
          tone: fresh > 0 ? TagTone.info : null),
    ];
    return Skeletonizer(
      enabled: d == null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        child: Column(
          children: [
            for (var i = 0; i < tiles.length; i += 2)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm + 2),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: tiles[i]),
                      const SizedBox(width: Space.sm + 2),
                      Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.label, this.count, this.route, {this.tone, this.format = _plain});

  final IconData icon;
  final String label;
  final int count;
  final String route;
  final TagTone? tone; // null = plain tile
  final String Function(int) format;

  static String _plain(int n) => '$n';

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final colors = tone == null ? (bg: c.surfaceContainerLow, fg: c.onSurface) : toneColors(c, tone!);
    return Semantics(
      button: true,
      label: '$label, ${format(count)}',
      excludeSemantics: true,
      child: Material(
        color: colors.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: tone == null ? BorderSide(color: c.outlineVariant) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: tone == null ? c.onSurfaceVariant : colors.fg),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        style: t.labelMedium?.copyWith(color: tone == null ? c.onSurfaceVariant : colors.fg),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // counts up when the numbers arrive, and rolls when they change
                CountTo(
                  count,
                  format: format,
                  fromZero: true,
                  style: t.headlineSmall?.copyWith(color: colors.fg, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    const actions = [
      (PhosphorIconsRegular.plus, 'Add product', '/admin/products/new'),
      (PhosphorIconsRegular.package, 'Catalogue', '/admin/catalogue'),
      (PhosphorIconsRegular.receipt, 'Orders', '/admin/orders'),
      (PhosphorIconsRegular.wrench, 'Repairs', '/admin/repairs'),
      (PhosphorIconsRegular.sealPercent, 'Offers', '/admin/offers'),
      (PhosphorIconsRegular.stack, 'Groups', '/admin/groups'),
      (PhosphorIconsRegular.flagBanner, 'Banners', '/admin/banners'),
      (PhosphorIconsRegular.gearSix, 'Settings', '/admin/settings'),
    ];
    final c = Theme.of(context).colorScheme;
    Widget tile(IconData icon, String label, String route) => InkWell(
          borderRadius: BorderRadius.circular(Radii.lg),
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(16)),
                  child: SizedBox.square(dimension: 52, child: Icon(icon, color: c.onPrimaryContainer)),
                ),
                const SizedBox(height: 6),
                Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
        );
    // three a row, so "Catalogue" and "Add product" fit on one line at large text
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: Column(
        children: [
          for (var i = 0; i < actions.length; i += 3)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = i; j < i + 3; j++)
                  Expanded(child: j < actions.length ? tile(actions[j].$1, actions[j].$2, actions[j].$3) : const SizedBox()),
              ],
            ),
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
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 48), padding: const EdgeInsets.symmetric(horizontal: 14)),
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
