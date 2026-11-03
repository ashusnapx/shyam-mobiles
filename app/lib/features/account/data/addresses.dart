import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import 'profile_repository.dart';

/// The address the next order goes to, picked in the cart or at checkout (they share it). Null: the default.
final selectedAddressProvider = NotifierProvider<SelectedAddress, Address?>(SelectedAddress.new);

class SelectedAddress extends Notifier<Address?> {
  @override
  Address? build() {
    ref.watch(currentUserIdProvider); // never carried into another account
    return null;
  }

  void set(Address? a) => state = a;
}

/// The pick while it's still saved, else the default (the list comes default first, then newest). The address form
/// returns the new row before the list has reloaded, so a pick missing from [list] is kept as it is.
Address? deliveryAddressFrom(List<Address> list, Address? picked) =>
    picked == null ? list.firstOrNull : list.where((a) => a.id == picked.id).firstOrNull ?? picked;

/// The signed-in user's addresses, default first.
final addressesProvider = AsyncNotifierProvider<AddressesNotifier, List<Address>>(AddressesNotifier.new);

class AddressesNotifier extends AsyncNotifier<List<Address>> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);
  String get _uid => ref.read(currentUserIdProvider)!;

  @override
  Future<List<Address>> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const [];
    return ref.watch(profileRepositoryProvider).addresses(uid);
  }

  /// Creates when `address.id` is null, else updates. Returns the saved address.
  Future<Address> save(Address address) async {
    final saved = await _repo.saveAddress(_uid, address);
    ref.invalidateSelf();
    // Saved: a failed reload must not look like a failed save, or a second tap inserts a duplicate.
    try {
      await future;
    } catch (_) {} // the list screen shows the reload error with a retry
    return saved;
  }

  Future<void> setDefault(String id) async {
    await _repo.setDefaultAddress(_uid, id);
    ref.invalidateSelf();
    await future;
  }

  Future<void> delete(String id) async {
    await _repo.deleteAddress(_uid, id);
    ref.invalidateSelf();
    await future;
  }
}
