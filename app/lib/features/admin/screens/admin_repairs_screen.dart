import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/models/models.dart';
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
    return AsyncBody<List<RepairBooking>>(
      value: ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      loading: Skeletonizer(child: _Rows(bookings: skeletonBookings)),
      data: (bookings) => bookings.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsRegular.wrench,
              title: 'No repairs here',
              message: 'Bookings show up here as customers make them.',
            )
          : RefreshIndicator(onRefresh: () => ref.refresh(provider.future), child: _Rows(bookings: bookings)),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.bookings});

  final List<RepairBooking> bookings;

  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl + MediaQuery.paddingOf(context).bottom),
        itemCount: bookings.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
        itemBuilder: (context, i) => RepairCard(
          booking: bookings[i],
          showPhone: true,
          onTap: () => context.push('/admin/repairs/${bookings[i].id}'),
        ),
      );
}
