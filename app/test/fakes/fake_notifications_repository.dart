import 'package:shyam_mobiles/features/notifications/data/notifications.dart' show AppNotification;
import 'package:shyam_mobiles/features/notifications/data/notifications_repository.dart';

import 'fake.dart';

/// Seed [inbox] (newest first). markRead only records; read state comes from the seeded readAt.
class FakeNotificationsRepository with Fake implements NotificationsRepository {
  var inbox = <AppNotification>[];
  final readIds = <String>{};
  bool allRead = false;

  bool _unread(AppNotification n) => n.readAt == null && !allRead && !readIds.contains(n.id);

  @override
  Future<List<AppNotification>> page(String uid, int from, int size) async {
    record('page $from');
    return pageOf(inbox, from, size);
  }

  @override
  Future<int> unread(String uid) async {
    record('unread');
    return inbox.where(_unread).length;
  }

  @override
  Future<AppNotification?> newestUnread(String uid) async {
    record('newestUnread');
    return inbox.where(_unread).firstOrNull;
  }

  @override
  Future<void> markRead(String uid, [List<String>? ids]) async {
    record('markRead ${ids?.join(',') ?? 'all'}');
    ids == null ? allRead = true : readIds.addAll(ids);
  }

  @override
  Future<void> delete(String uid, String id) async {
    record('delete $id');
    inbox = inbox.where((n) => n.id != id).toList();
  }
}
