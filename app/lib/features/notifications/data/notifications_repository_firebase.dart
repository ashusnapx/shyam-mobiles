import 'package:cloud_firestore/cloud_firestore.dart';

import 'notifications.dart' show AppNotification;
import 'notifications_repository.dart';

/// users/{uid}/notifications (firebase/functions/src/notifications/triggers.ts writes them; Rules let the owner read,
/// delete and set readAt to the server's time).
class FirebaseNotificationsRepository implements NotificationsRepository {
  FirebaseNotificationsRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _mine(String uid) => _db.collection('users/$uid/notifications');
  Query<Map<String, dynamic>> _unread(String uid) => _mine(uid).where('readAt', isNull: true);

  static AppNotification _of(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data()!;
    return AppNotification(
      id: d.id,
      kind: j['kind'] as String,
      title: j['title'] as String,
      body: j['body'] as String? ?? '',
      link: j['link'] as String?,
      readAt: (j['readAt'] as Timestamp?)?.toDate(),
      imagePath: j['imagePath'] as String?,
      createdAt: (j['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// shortcut: offset paging re-reads the rows before [from]; 90 days of notifications stay small.
  @override
  Future<List<AppNotification>> page(String uid, int from, int size) async => [
        for (final d in (await _mine(uid).orderBy('createdAt', descending: true).limit(from + size).get()).docs.skip(from))
          _of(d),
      ];

  @override
  Future<int> unread(String uid) async => (await _unread(uid).count().get()).count ?? 0;

  @override
  Future<AppNotification?> newestUnread(String uid) async {
    final hits = await _unread(uid).orderBy('createdAt', descending: true).limit(1).get();
    return hits.docs.isEmpty ? null : _of(hits.docs.first);
  }

  @override
  Future<void> markRead(String uid, [List<String>? ids]) async {
    final refs = ids == null ? [for (final d in (await _unread(uid).limit(500).get()).docs) d.reference] : [for (final id in ids) _mine(uid).doc(id)];
    if (refs.isEmpty) return;
    final batch = _db.batch();
    for (final r in refs) {
      batch.update(r, {'readAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  @override
  Future<void> delete(String uid, String id) => _mine(uid).doc(id).delete();
}
