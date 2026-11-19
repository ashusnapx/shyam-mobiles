import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/errors.dart';
import '../../../core/supabase.dart' show currentUserIdProvider;
import '../../../core/widgets/widgets.dart';
import '../data/profile_repository.dart';

/// The customer's "Offers & reminders" choice; null where the build sends no such pushes.
final offersOptInProvider = FutureProvider.autoDispose<bool?>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  return uid == null ? null : ref.watch(profileRepositoryProvider).offersOptIn(uid);
});

/// Account → Notifications: "Offers & reminders" on or off in one tap (docs/GROWTH.md §2d, the nagging rule). Order,
/// repair and back-in-stock updates aren't affected.
class OffersSwitch extends ConsumerStatefulWidget {
  const OffersSwitch({super.key});

  @override
  ConsumerState<OffersSwitch> createState() => _OffersSwitchState();
}

class _OffersSwitchState extends ConsumerState<OffersSwitch> {
  bool? _pending; // shown at once; the saved value comes back after

  Future<void> _set(bool on) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    setState(() => _pending = on);
    try {
      await ref.read(profileRepositoryProvider).setOffersOptIn(uid, on: on);
      ref.invalidate(offersOptInProvider);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(offersOptInProvider).value;
    if (saved == null) return const SizedBox.shrink();
    return SwitchListTile(
      value: _pending ?? saved,
      onChanged: _pending == null ? _set : null,
      title: const Text('Offers & reminders'),
      subtitle: const Text('Price drops on your wishlist, a cart you left, tips for a new phone. At most one every 3 days, '
          'never at night. Order and repair updates always come.'),
      isThreeLine: true,
    );
  }
}
