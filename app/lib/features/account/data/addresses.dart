import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart';

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

/// The signed-in user's addresses, default first. Setting `is_default` on one unsets the others (DB trigger).
final addressesProvider = AsyncNotifierProvider<AddressesNotifier, List<Address>>(AddressesNotifier.new);

class AddressesNotifier extends AsyncNotifier<List<Address>> {
  SupabaseClient get _db => ref.read(supabaseProvider);

  @override
  Future<List<Address>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const [];
    final rows = await _db
        .from('addresses')
        .select()
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);
    return [for (final r in rows) Address.fromJson(r)];
  }

  /// Inserts when `address.id` is null, else updates. Returns the saved row.
  Future<Address> save(Address address) async {
    final row = address.id == null
        ? await _db
            .from('addresses')
            .insert({...address.toJson(), 'user_id': ref.read(currentUserIdProvider)})
            .select()
            .single()
        : await _db.from('addresses').update(address.toJson()).eq('id', address.id!).select().single();
    ref.invalidateSelf();
    // Saved: a failed reload must not look like a failed save, or a second tap inserts a duplicate.
    try {
      await future;
    } catch (_) {} // the list screen shows the reload error with a retry
    return Address.fromJson(row);
  }

  Future<void> setDefault(String id) async {
    await _db.from('addresses').update({'is_default': true}).eq('id', id);
    ref.invalidateSelf();
    await future;
  }

  Future<void> delete(String id) async {
    await _db.from('addresses').delete().eq('id', id);
    ref.invalidateSelf();
    await future;
  }
}
