import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/callable.dart';
import '../../../core/models/models.dart';
import 'repairs_repository.dart';

/// repairs/{id} (firebase/functions/src/repairs): read under Rules (own or staff), changed only by the callables.
class FirebaseRepairsRepository implements RepairsRepository {
  FirebaseRepairsRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _repairs => _db.collection('repairs');
  Future<void> _call(String name, Map<String, Object?> data) => callFunction(_functions, name, data);

  static DateTime _at(Object? t) => (t as Timestamp?)?.toDate() ?? DateTime.now();

  static RepairBooking _of(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data()!;
    final quote = j['quote'] as Map<String, dynamic>? ?? const {};
    final events = j['events'] as List? ?? const [];
    return RepairBooking(
      id: d.id,
      number: j['number'],
      userId: j['uid'],
      deviceBrand: j['deviceBrand'],
      deviceModel: j['deviceModel'],
      issue: RepairIssue.parse(j['issue']),
      description: j['description'] ?? '',
      preferredDate: DateTime.parse(j['preferredDate']),
      slot: RepairSlot.parse(j['slot']),
      contactPhone: j['contactPhone'],
      status: RepairStatus.parse(j['status']),
      quotePaise: quote['paise'],
      quoteStatus: RepairQuoteStatus.parse(quote['status'] ?? 'none'),
      quoteDecidedAt: quote['decidedAt'] == null ? null : _at(quote['decidedAt']),
      createdAt: _at(j['createdAt']),
      events: [
        for (final (i, e) in events.cast<Map<String, dynamic>>().indexed)
          RepairEvent(
            id: i,
            status: RepairStatus.parse(e['status']),
            quoteStatus: e['quoteStatus'] == null ? null : RepairQuoteStatus.parse(e['quoteStatus']),
            quotePaise: e['quotePaise'],
            note: e['note'],
            createdAt: _at(e['at']),
          ),
      ],
    );
  }

  /// shortcut: offset paging re-reads the rows before [from]; fine at shop volume, use cursors past ~1,000 bookings.
  Future<List<RepairBooking>> _page(Query<Map<String, dynamic>> q, int from, int size) async =>
      [for (final d in (await q.limit(from + size).get()).docs.skip(from)) _of(d)];

  @override
  Future<List<RepairBooking>> myRepairs(String uid, int from, int size) =>
      _page(_repairs.where('uid', isEqualTo: uid).orderBy('createdAt', descending: true), from, size);

  @override
  Future<RepairBooking> repair(String id) async => _of(await _repairs.doc(id).get());

  @override
  Future<String> book({
    required String deviceBrand,
    required String deviceModel,
    required RepairIssue issue,
    required String description,
    required String preferredDate,
    required RepairSlot slot,
    required String contactPhone,
  }) async =>
      (await callFunction(_functions, 'bookRepair', {
        'deviceBrand': deviceBrand,
        'deviceModel': deviceModel,
        'issue': issue.value,
        'description': description,
        'preferredDate': preferredDate,
        'slot': slot.value,
        'contactPhone': contactPhone,
      }))['repairId'] as String;

  @override
  Future<void> cancel(String id) => _call('cancelRepair', {'repairId': id});

  @override
  Future<void> approveQuote(RepairBooking b) => _call('approveRepairQuote', {'repairId': b.id, 'quotePaise': b.quotePaise});

  @override
  Future<void> declineQuote(String id, String reason) =>
      _call('declineRepairQuote', {'repairId': id, 'reason': reason.isEmpty ? null : reason});

  /// shortcut: ordered by date only (the Supabase build also orders by slot within a day).
  @override
  Future<List<RepairBooking>> adminRepairs(String filter, int from, int size) {
    final open = [for (final s in RepairStatus.values) if (s.isOpen) s.value];
    final Query<Map<String, dynamic>> q = switch (filter) {
      'all' => _repairs,
      'open' => _repairs.where('status', whereIn: open),
      'awaiting_approval' => _repairs.where('status', whereIn: open).where('quote.status', isEqualTo: 'pending'),
      _ => _repairs.where('status', isEqualTo: filter),
    };
    return _page(q.orderBy('preferredDate', descending: !upcomingFirst(filter)), from, size);
  }

  @override
  Future<List<RepairBooking>> toConfirm() => _page(_repairs.where('status', isEqualTo: 'requested').orderBy('preferredDate'), 0, 30);

  @override
  Future<void> updateStatus(String id, RepairStatus status, {String? note}) =>
      _call('adminUpdateRepair', {'repairId': id, 'status': status.value, 'note': note});

  @override
  Future<void> setQuote(String id, int paise, {String? note, bool approved = false}) =>
      _call('adminSetRepairQuote', {'repairId': id, 'quotePaise': paise, 'note': note, 'approved': approved});
}
