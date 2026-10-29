import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart';

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
    await future;
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
