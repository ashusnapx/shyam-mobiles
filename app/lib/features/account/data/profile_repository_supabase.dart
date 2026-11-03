import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import 'profile_repository.dart';

/// Today's profile and address queries behind [ProfileRepository] (own-row RLS); deleted in Phase 2 with Supabase.
class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Profile?> profile(String uid) async {
    final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  @override
  Future<void> saveFullName(String uid, String? fullName) =>
      _db.from('profiles').update({'full_name': (fullName?.isEmpty ?? true) ? null : fullName}).eq('id', uid);

  // Setting `is_default` on one address unsets the others (DB trigger).
  @override
  Future<List<Address>> addresses(String uid) async {
    final rows =
        await _db.from('addresses').select().order('is_default', ascending: false).order('created_at', ascending: false);
    return [for (final r in rows) Address.fromJson(r)];
  }

  @override
  Future<Address> saveAddress(String uid, Address address) async {
    final row = address.id == null
        ? await _db.from('addresses').insert({...address.toJson(), 'user_id': uid}).select().single()
        : await _db.from('addresses').update(address.toJson()).eq('id', address.id!).select().single();
    return Address.fromJson(row);
  }

  @override
  Future<void> setDefaultAddress(String uid, String addressId) =>
      _db.from('addresses').update({'is_default': true}).eq('id', addressId);

  @override
  Future<void> deleteAddress(String uid, String addressId) => _db.from('addresses').delete().eq('id', addressId);

  @override
  Future<void> deleteAccount() => _db.functions.invoke('delete-account', body: const <String, dynamic>{});

  /// What RLS lets the user read of their own rows.
  @override
  Future<Map<String, Object?>> exportMyData(String uid) async {
    final mine = {
      'profile': 'profiles',
      'addresses': 'addresses',
      'orders': 'orders',
      'repairs': 'repair_bookings',
      'feedback': 'feedback',
      'notifications': 'notifications',
    };
    final rows = await Future.wait([for (final t in mine.values) _db.from(t).select().limit(500)]);
    return {'exportedAt': DateTime.now().toUtc().toIso8601String(), for (final (i, k) in mine.keys.indexed) k: rows[i]};
  }
}
