import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/models/models.dart';
import '../../../core/paging.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../data/admin.dart';
import '../widgets/admin_widgets.dart';

class AdminRepairsScreen extends StatefulWidget {
  const AdminRepairsScreen({super.key});

  @override
  State<AdminRepairsScreen> createState() => _AdminRepairsScreenState();
}

class _AdminRepairsScreenState extends State<AdminRepairsScreen> {
  // The route passes no params; an optional ?status= (a key of repairFilters) is read here.
  late String _filter = switch (GoRouterState.of(context).uri.queryParameters['status']) {
    final s? when repairFilters.containsKey(s) => s,
    _ => 'open',
  };

  @override
  Widget build(BuildContext context) => AdminGate(
        child: Scaffold(
          appBar: AppBar(title: const Text('Repairs')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: ChipBar(options: repairFilters, selected: _filter, onSelected: (f) => setState(() => _filter = f)),
              ),
              Expanded(child: _RepairList(filter: _filter)),
            ],
          ),
        ),
      );
}

class _RepairList extends ConsumerWidget {
  const _RepairList({required this.filter});

  final String filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = adminRepairsProvider(filter);
    return AsyncBody<Paged<RepairBooking>>(
      value: ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      loading: Skeletonizer(child: _Rows(bookings: skeletonBookings)),
      data: (page) => page.items.isEmpty
          ? EmptyState(
              icon: PhosphorIconsRegular.wrench,
              title: 'No repairs here',
              message: filter == 'awaiting_approval'
                  ? 'Quotes you send show up here until the customer answers.'
                  : 'Bookings show up here as customers make them.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(provider.future),
              child: LoadMoreListener(
                hasMore: page.hasMore,
                onMore: ref.read(provider.notifier).loadMore,
                child: _Rows(
                  bookings: page.items,
                  footer: page.hasMore
                      ? PagedFooter(
                          failed: page.moreFailed,
                          onRetry: () => ref.read(provider.notifier).loadMore(retry: true),
                          what: 'more repairs',
                        )
                      : null,
                ),
              ),
            ),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.bookings, this.footer});

  final List<RepairBooking> bookings;
  final Widget? footer; // the next page's spinner or retry

  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl + MediaQuery.paddingOf(context).bottom),
        itemCount: bookings.length + (footer == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
        itemBuilder: (context, i) => i == bookings.length
            ? footer!
            : RepairCard(
                booking: bookings[i],
                showPhone: true,
                onTap: () => context.push('/admin/repairs/${bookings[i].id}'),
              ),
      );
}
