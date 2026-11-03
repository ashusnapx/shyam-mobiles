import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/paging.dart';
import '../../../core/supabase.dart';
import 'repairs_repository.dart';

/// The signed-in user's bookings, newest first, a page at a time. Filters on user_id because admins can read every
/// booking.
final myRepairsProvider = AsyncNotifierProvider<MyRepairsNotifier, Paged<RepairBooking>>(MyRepairsNotifier.new);

class MyRepairsNotifier extends PagedNotifier<RepairBooking> {
  @override
  Object idOf(RepairBooking b) => b.id;

  @override
  Future<Paged<RepairBooking>> build() {
    ref.watch(currentUserIdProvider);
    return super.build();
  }

  @override
  Future<List<RepairBooking>> fetch(int from, int size) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return const [];
    return ref.read(repairsRepositoryProvider).myRepairs(uid, from, size);
  }
}

/// One booking with its timeline. RLS limits customers to their own; admins see all, so the admin detail uses this too.
final repairProvider = FutureProvider.autoDispose.family<RepairBooking, String>((ref, id) async {
  ref.watch(currentUserIdProvider); // never show one account's booking to the next
  return ref.watch(repairsRepositoryProvider).repair(id);
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
