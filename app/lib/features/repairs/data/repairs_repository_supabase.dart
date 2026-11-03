import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import 'repairs_repository.dart';

/// Today's repair queries and RPCs (supabase/migrations/20261030000300_repair_flow.sql), moved here unchanged from
/// repairs.dart and admin.dart. Deleted in Phase 2 with Supabase.
class SupabaseRepairsRepository implements RepairsRepository {
  SupabaseRepairsRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<List<RepairBooking>> myRepairs(String uid, int from, int size) async => [
        for (final r in await _db
            .from('repair_bookings')
            .select()
            .eq('user_id', uid) // admins can read every booking
            .order('created_at', ascending: false)
            .order('id') // ties: no booking repeats or goes missing between pages
            .range(from, from + size - 1))
          RepairBooking.fromJson(r),
      ];

  @override
  Future<RepairBooking> repair(String id) async =>
      RepairBooking.fromJson(await _db.from('repair_bookings').select('*, events:repair_events(*)').eq('id', id).single());

  /// RLS: status requested, no quote/note, date within 30 days IST.
  @override
  Future<String> book({
    required String deviceBrand,
    required String deviceModel,
    required RepairIssue issue,
    required String description,
    required String preferredDate,
    required RepairSlot slot,
    required String contactPhone,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Sign in to book a repair');
    final row = await _db
        .from('repair_bookings')
        .insert({
          'user_id': uid,
          'device_brand': deviceBrand,
          'device_model': deviceModel,
          'issue': issue.value,
          'description': description,
          'preferred_date': preferredDate,
          'slot': slot.value,
          'contact_phone': contactPhone,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  @override
  Future<void> cancel(String id) => _db.rpc<void>('cancel_repair', params: {'p_booking_id': id});

  @override
  Future<void> approveQuote(RepairBooking b) =>
      _db.rpc<void>('approve_repair_quote', params: {'p_booking_id': b.id, 'p_quote_paise': b.quotePaise});

  @override
  Future<void> declineQuote(String id, String reason) =>
      _db.rpc<void>('decline_repair_quote', params: {'p_booking_id': id, 'p_reason': reason.isEmpty ? null : reason});

  @override
  Future<List<RepairBooking>> adminRepairs(String filter, int from, int size) async {
    final open = [for (final s in RepairStatus.values) if (s.isOpen) s.value];
    var q = _db.from('repair_bookings').select();
    q = switch (filter) {
      'all' => q,
      'open' => q.inFilter('status', open),
      // same rule as admin_dashboard's repairs_awaiting_approval
      'awaiting_approval' => q.inFilter('status', open).eq('quote_status', 'pending'),
      _ => q.eq('status', filter),
    };
    final rows = await q
        .order('preferred_date', ascending: upcomingFirst(filter))
        .order('slot', ascending: upcomingFirst(filter))
        .order('id') // ties: no booking repeats or goes missing between pages
        .range(from, from + size - 1);
    return [for (final r in rows) RepairBooking.fromJson(r)];
  }

  @override
  Future<List<RepairBooking>> toConfirm() async => [
        for (final r in await _db
            .from('repair_bookings')
            .select()
            .eq('status', 'requested')
            .order('preferred_date')
            .order('slot')
            .limit(30))
          RepairBooking.fromJson(r),
      ];

  @override
  Future<void> updateStatus(String id, RepairStatus status, {String? note}) =>
      _db.rpc<void>('admin_update_repair', params: {'p_booking_id': id, 'p_status': status.value, 'p_note': note});

  @override
  Future<void> setQuote(String id, int paise, {String? note, bool approved = false}) => _db.rpc<void>('admin_set_repair_quote',
      params: {'p_booking_id': id, 'p_quote_paise': paise, 'p_note': note, 'p_approved': approved});
}
