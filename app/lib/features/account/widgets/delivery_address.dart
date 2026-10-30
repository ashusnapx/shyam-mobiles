import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../data/addresses.dart';

const _addNew = 'new';

/// The address form, then that address is the one the order goes to. Null when the form was left.
Future<Address?> addDeliveryAddress(BuildContext context, WidgetRef ref) async {
  final a = await context.push<Address>('/account/addresses/new');
  if (a?.id != null) ref.read(selectedAddressProvider.notifier).set(a);
  return a;
}

/// The saved addresses to pick from, plus "Add new address". The cart and checkout share the pick.
Future<void> changeDeliveryAddress(BuildContext context, WidgetRef ref, List<Address> list, Address? current) async {
  final picked = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddressSheet(addresses: list, selectedId: current?.id),
  );
  if (!context.mounted) return;
  if (picked is Address) ref.read(selectedAddressProvider.notifier).set(picked);
  if (picked == _addNew) await addDeliveryAddress(context, ref);
}

/// "Deliver to Asha · Waidhan 486886  Change" at the top of the cart; "Add a delivery address" when there's none.
/// Nothing while the addresses load or if they fail (checkout still asks for one).
class DeliverToRow extends ConsumerWidget {
  const DeliverToRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(addressesProvider).value;
    if (list == null) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final a = deliveryAddressFrom(list, ref.watch(selectedAddressProvider));
    Future<void> act() => a == null ? addDeliveryAddress(context, ref) : changeDeliveryAddress(context, ref, list, a);
    return InkWell(
      onTap: act,
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.surfaceContainerLow, border: Border(bottom: BorderSide(color: c.outlineVariant))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.sm, Space.xs),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.mapPin, size: 20, color: c.onSurfaceVariant),
              const SizedBox(width: Space.sm),
              Expanded(
                child: a == null
                    ? Text('Add a delivery address', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))
                    : Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: 'Deliver to '),
                          TextSpan(text: a.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: ' · ${a.city} ${a.pincode}'),
                        ]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium,
                      ),
              ),
              TextButton(
                onPressed: act,
                child: Text(a == null ? 'Add' : 'Change', semanticsLabel: a == null ? 'Add a delivery address' : 'Change delivery address'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressSheet extends StatelessWidget {
  const _AddressSheet({required this.addresses, required this.selectedId});

  final List<Address> addresses;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Semantics(header: true, child: Text('Deliver to', style: t.titleLarge)),
          ),
          Flexible(
            child: RadioGroup<String>(
              groupValue: selectedId,
              onChanged: (id) => Navigator.pop(context, addresses.firstWhere((a) => a.id == id)),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in addresses)
                    RadioListTile<String>(
                      value: a.id!,
                      title: Text(a.name),
                      subtitle: Text('${a.oneLine}\n${displayPhone(a.phone)}'),
                      isThreeLine: true,
                    ),
                ],
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(PhosphorIconsRegular.plus, color: c.primary),
            title: Text('Add new address', style: t.titleSmall?.copyWith(color: c.primary)),
            onTap: () => Navigator.pop(context, _addNew),
          ),
        ],
      ),
    );
  }
}
