import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import 'repairs_repository_firebase.dart';
import 'repairs_repository_supabase.dart';

/// Repair bookings, the customer's and the staff side (docs/FIREBASE.md §1: bookRepair … adminSetRepairQuote).
/// Owner: engineer D.
abstract interface class RepairsRepository {
  /// Newest first, rows [from]..[from + size − 1].
  Future<List<RepairBooking>> myRepairs(String uid, int from, int size);

  /// One booking with its timeline (the customer's own, or any for staff).
  Future<RepairBooking> repair(String id);

  /// REPAIR_LIMIT at 3 open bookings; [preferredDate] 'YYYY-MM-DD', today..+30 days (IST). Returns the booking id.
  Future<String> book({
    required String deviceBrand,
    required String deviceModel,
    required RepairIssue issue,
    required String description,
    required String preferredDate,
    required RepairSlot slot,
    required String contactPhone,
  });

  Future<void> cancel(String id);

  /// Sends the amount the customer was shown: QUOTE_CHANGED if staff changed it meanwhile.
  Future<void> approveQuote(RepairBooking booking);

  /// [reason] may be empty.
  Future<void> declineQuote(String id, String reason);

  // Staff ------------------------------------------------------------------------------------------------------

  /// [filter]: a status value, or `open`, `awaiting_approval`, `all` (admin.dart repairFilters).
  Future<List<RepairBooking>> adminRepairs(String filter, int from, int size);

  /// Requested bookings to confirm, soonest first (≤ 30).
  Future<List<RepairBooking>> toConfirm();

  /// One step forward or a cancel; the current status again only adds [note]. QUOTE_NOT_APPROVED before work starts.
  Future<void> updateStatus(String id, RepairStatus status, {String? note});

  /// Sends or changes the quote; [approved] records a yes given at the counter or on the phone.
  Future<void> setQuote(String id, int paise, {String? note, bool approved = false});
}

final repairsRepositoryProvider = Provider<RepairsRepository>((ref) => backend == Backend.firebase
    ? FirebaseRepairsRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider))
    : SupabaseRepairsRepository(ref.watch(supabaseProvider)));

/// Staff lists: open bookings soonest first; finished ones (and "all") newest first.
bool upcomingFirst(String filter) => switch (filter) {
      'all' => false,
      'open' || 'awaiting_approval' => true,
      _ => RepairStatus.parse(filter).isOpen,
    };
