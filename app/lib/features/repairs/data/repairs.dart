import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';

/// The signed-in user's bookings, newest first. Filters on user_id because admins can read every booking.
final myRepairsProvider = FutureProvider<List<RepairBooking>>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];
  final rows = await ref
      .watch(supabaseProvider)
      .from('repair_bookings')
      .select()
      .eq('user_id', uid)
      .order('created_at', ascending: false);
  return [for (final r in rows) RepairBooking.fromJson(r)];
});

/// One booking. RLS limits customers to their own; admins see all, so the admin detail uses this too.
final repairProvider = FutureProvider.autoDispose.family<RepairBooking, String>((ref, id) async {
  final row = await ref.watch(supabaseProvider).from('repair_bookings').select().eq('id', id).single();
  return RepairBooking.fromJson(row);
});

/// Phone to prefill: the auth phone (phone OTP users), else the profile phone. E.164 or null.
final myPhoneProvider = FutureProvider<String?>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  final authPhone = normalizeIndianPhone(ref.read(currentUserProvider)?.phone ?? '');
  if (authPhone != null) return authPhone;
  final row = await ref.watch(supabaseProvider).from('profiles').select('phone').eq('id', uid).maybeSingle();
  return row?['phone'] as String?;
});

/// Inserts a booking for the current user (RLS: status requested, no quote/note, date within 30 days IST). Returns its id.
Future<String> bookRepair(
  SupabaseClient db, {
  required String deviceBrand,
  required String deviceModel,
  required RepairIssue issue,
  required String description,
  required String preferredDate,
  required RepairSlot slot,
  required String contactPhone,
}) async {
  final uid = db.auth.currentUser?.id;
  if (uid == null) throw const AuthException('Sign in to book a repair');
  final row = await db
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

Future<void> cancelRepair(SupabaseClient db, String id) => db.rpc<void>('cancel_repair', params: {'p_booking_id': id});
