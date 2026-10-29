import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/addresses.dart';

class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  static const _fake = Address(
    name: 'Placeholder name',
    phone: '+919999999999',
    line1: 'House and street line',
    city: 'City name',
    state: 'State',
    pincode: '000000',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressesProvider);
    final count = addresses.value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Addresses')),
      floatingActionButton: count == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: () => count >= 10 // DB trigger limit
                  ? showMessage(context, 'You can save up to 10 addresses. Delete one to add another.')
                  : context.push('/account/addresses/new'),
              icon: const Icon(PhosphorIconsRegular.plus),
              label: const Text('Add address'),
            ),
      body: AsyncBody(
        value: addresses,
        onRetry: () => ref.invalidate(addressesProvider),
        loading: Skeletonizer(child: _List(addresses: List.filled(3, _fake))),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: PhosphorIconsRegular.mapPin,
                title: 'No saved addresses',
                message: 'Add one now and checkout gets quicker.',
                action: FilledButton.icon(
                  onPressed: () => context.push('/account/addresses/new'),
                  icon: const Icon(PhosphorIconsRegular.plus),
                  label: const Text('Add address'),
                ),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(addressesProvider.future),
                child: _List(addresses: list),
              ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.addresses});

  final List<Address> addresses;

  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        // Room for the FAB and the gesture bar.
        padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 96 + MediaQuery.paddingOf(context).bottom),
        itemCount: addresses.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.md),
        itemBuilder: (_, i) => _AddressCard(address: addresses[i]),
      );
}

enum _Action { edit, makeDefault, delete }

class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.address});

  final Address address;

  Future<void> _run(BuildContext context, WidgetRef ref, _Action action) async {
    final notifier = ref.read(addressesProvider.notifier);
    try {
      switch (action) {
        case _Action.edit:
          await context.push('/account/addresses/${address.id}');
        case _Action.makeDefault:
          await notifier.setDefault(address.id!);
          if (context.mounted) showMessage(context, 'Default address updated.');
        case _Action.delete:
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete this address?'),
              content: Text(address.oneLine),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await notifier.delete(address.id!);
          if (context.mounted) showMessage(context, 'Address deleted.');
      }
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: () => _run(context, ref, _Action.edit),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.xs, Space.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.xs,
                  children: [
                    const SizedBox(height: Space.xs),
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(address.name, style: t.titleSmall),
                        if (address.isDefault) const Tag('Default', tone: TagTone.ok),
                      ],
                    ),
                    Text(address.oneLine, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                    Text(displayPhone(address.phone), style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                  ],
                ),
              ),
              PopupMenuButton<_Action>(
                tooltip: 'Address options',
                icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
                onSelected: (a) => _run(context, ref, a),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: _Action.edit, child: Text('Edit')),
                  if (!address.isDefault)
                    const PopupMenuItem(value: _Action.makeDefault, child: Text('Set as default')),
                  const PopupMenuItem(value: _Action.delete, child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
