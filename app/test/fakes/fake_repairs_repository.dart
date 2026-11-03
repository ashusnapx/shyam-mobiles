import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/repairs/data/repairs_repository.dart';

import 'fake.dart';

/// Seed [repairs] (newest first). Booking adds one; past [limit] open bookings it fails with REPAIR_LIMIT.
class FakeRepairsRepository with Fake implements RepairsRepository {
  var repairs = <RepairBooking>[];
  int limit = 3;
  final quotes = <String, ({int paise, String? note, bool approved})>{};
  final statusChanges = <({String id, RepairStatus status, String? note})>[];
  var _next = 1;

  @override
  Future<List<RepairBooking>> myRepairs(String uid, int from, int size) async {
    record('myRepairs $uid $from');
    return pageOf(repairs.where((r) => r.userId == null || r.userId == uid).toList(), from, size);
  }

  @override
  Future<RepairBooking> repair(String id) async {
    record('repair $id');
    return repairs.where((r) => r.id == id).firstOrNull ?? (throw reason('NOT_FOUND'));
  }

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
    record('book $deviceBrand $deviceModel');
    if (repairs.where((r) => r.status.isOpen).length >= limit) throw reason('REPAIR_LIMIT');
    final id = 'r${_next++}';
    repairs = [
      RepairBooking(
        id: id,
        number: 'RP${100000 + _next}',
        deviceBrand: deviceBrand,
        deviceModel: deviceModel,
        issue: issue,
        description: description,
        preferredDate: DateTime.parse(preferredDate),
        slot: slot,
        contactPhone: contactPhone,
        status: RepairStatus.requested,
        createdAt: DateTime.now(),
      ),
      ...repairs,
    ];
    return id;
  }

  @override
  Future<void> cancel(String id) async => record('cancel $id');

  @override
  Future<void> approveQuote(RepairBooking booking) async => record('approveQuote ${booking.id} ${booking.quotePaise}');

  @override
  Future<void> declineQuote(String id, String reason) async => record('declineQuote $id');

  @override
  Future<List<RepairBooking>> adminRepairs(String filter, int from, int size) async {
    record('adminRepairs $filter $from');
    final hits = switch (filter) {
      'all' => repairs,
      'open' => repairs.where((r) => r.status.isOpen).toList(),
      'awaiting_approval' => repairs.where((r) => r.status.isOpen && r.quoteStatus == RepairQuoteStatus.pending).toList(),
      _ => repairs.where((r) => r.status.value == filter).toList(),
    };
    return pageOf(hits, from, size);
  }

  @override
  Future<List<RepairBooking>> toConfirm() async {
    record('toConfirm');
    return repairs.where((r) => r.status == RepairStatus.requested).toList();
  }

  @override
  Future<void> updateStatus(String id, RepairStatus status, {String? note}) async {
    record('updateStatus $id ${status.value}');
    statusChanges.add((id: id, status: status, note: note));
  }

  @override
  Future<void> setQuote(String id, int paise, {String? note, bool approved = false}) async {
    record('setQuote $id $paise');
    quotes[id] = (paise: paise, note: note, approved: approved);
  }
}
