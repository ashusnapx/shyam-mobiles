import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/paging.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/notifications.dart';
import '../widgets/notification_widgets.dart';

/// Everything that happened to your orders, repairs and coupons (and, for staff, what needs doing), newest first under
/// Today / Yesterday / Earlier. Tap one to open it; the × or a swipe removes it.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(notificationsProvider);
    final list = ref.read(notificationsProvider.notifier);
    final unread = page.value?.items.any((n) => n.unread) ?? false;

    Future<void> fail(Object e) async {
      ref.invalidate(notificationsProvider); // back to what the server has
      await ref.read(unreadCountProvider.notifier).refresh();
      if (context.mounted) showMessage(context, friendlyError(e));
    }

    Future<void> markAll() async {
      list.replaceItems((items) => [for (final n in items) n.unread ? n.markedRead() : n]);
      ref.read(unreadCountProvider.notifier).set(0);
      try {
        await ref.read(notificationsApiProvider).markRead();
      } catch (e) {
        await fail(e);
      }
    }

    Future<void> remove(AppNotification n) async {
      list.replaceItems((items) => [for (final i in items) if (i.id != n.id) i]);
      if (n.unread) ref.read(unreadCountProvider.notifier).set(ref.read(unreadCountProvider) - 1);
      try {
        await ref.read(notificationsApiProvider).delete(n.id);
      } catch (e) {
        await fail(e);
      }
    }

    void open(AppNotification n) {
      list.replaceItems((items) => [for (final i in items) i.id == n.id ? i.markedRead() : i]);
      unawaited(ref.read(unreadCountProvider.notifier).open(GoRouter.of(context), n));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [if (unread) TextButton(onPressed: markAll, child: const Text('Mark all read'))],
      ),
      body: AsyncBody(
        value: page,
        onRetry: () => ref.invalidate(notificationsProvider),
        loading: Skeletonizer(
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < 6; i++) _Tile(_placeholder, now: DateTime.now(), onOpen: () {}, onDelete: () {}),
            ],
          ),
        ),
        data: (p) {
          if (p.items.isEmpty) {
            return const EmptyState(
              icon: PhosphorIconsRegular.bell,
              title: 'No notifications yet',
              message: 'Updates on your orders, repairs and offers show up here.',
            );
          }
          final now = DateTime.now();
          final rows = <Object>[
            for (final (group, items) in groupByDay(p.items, now)) ...[group, ...items],
          ];
          return RefreshIndicator(
            onRefresh: () => Future.wait([
              ref.refresh(notificationsProvider.future),
              ref.read(unreadCountProvider.notifier).refresh(),
            ]),
            child: LoadMoreListener(
              hasMore: p.hasMore,
              onMore: list.loadMore,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                // edge-to-edge: keep the last row clear of the system nav bar
                padding: EdgeInsets.only(bottom: Space.lg + MediaQuery.paddingOf(context).bottom),
                itemCount: rows.length + (p.hasMore ? 1 : 0),
                itemBuilder: (_, i) => switch (i < rows.length ? rows[i] : null) {
                  final DayGroup g => SectionHeader(g.label),
                  final AppNotification n => _Tile(
                      n,
                      key: ValueKey(n.id),
                      now: now,
                      onOpen: () => open(n),
                      onDelete: () => remove(n),
                    ),
                  _ => PagedFooter(
                      failed: p.moreFailed,
                      onRetry: () => list.loadMore(retry: true),
                      what: 'more notifications',
                    ),
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

final _placeholder = AppNotification(
  id: '',
  kind: 'order_packed',
  title: 'SM100000 is packed',
  body: 'It ships soon. We’ll tell you when it’s on the way.',
  createdAt: DateTime.now(),
);

class _Tile extends StatelessWidget {
  const _Tile(this.n, {super.key, required this.now, required this.onOpen, required this.onDelete});

  final AppNotification n;
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('swipe ${n.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: ColoredBox(
        color: c.errorContainer,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: Space.xl),
            child: Icon(PhosphorIconsRegular.trash, color: c.onErrorContainer),
          ),
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.xs, Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NotificationIcon(n.kind),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: t.titleSmall?.copyWith(fontWeight: n.unread ? FontWeight.w800 : FontWeight.w500),
                          ),
                        ),
                        if (n.unread)
                          Semantics(
                            label: 'Unread',
                            child: const Padding(
                              padding: EdgeInsets.only(left: Space.sm, top: 6),
                              child: DecoratedBox(
                                decoration: BoxDecoration(color: BrandColors.peacock, shape: BoxShape.circle),
                                child: SizedBox.square(dimension: 8),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (n.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                    ],
                    const SizedBox(height: Space.xs),
                    Text(timeAgo(n.createdAt, now), style: t.labelSmall?.copyWith(color: c.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete notification',
                onPressed: onDelete,
                icon: Icon(PhosphorIconsRegular.x, size: 18, color: c.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
