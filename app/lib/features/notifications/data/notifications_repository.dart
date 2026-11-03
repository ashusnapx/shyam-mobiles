import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart';
import '../../../core/supabase.dart';
import 'notifications.dart' show AppNotification, NotificationsApi;
import 'notifications_repository_firebase.dart';

/// The signed-in user's in-app notifications (Firebase: users/{uid}/notifications, written by triggers; the owner
/// may only mark them read or delete them). Owner: engineer D.
abstract interface class NotificationsRepository {
  /// Newest first, rows [from]..[from + size − 1].
  Future<List<AppNotification>> page(String uid, int from, int size);

  Future<int> unread(String uid);

  Future<AppNotification?> newestUnread(String uid);

  /// [ids] null: all of the user's notifications.
  Future<void> markRead(String uid, [List<String>? ids]);

  Future<void> delete(String uid, String id);
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) => backend == Backend.firebase
    ? FirebaseNotificationsRepository(ref.watch(firestoreProvider))
    : NotificationsApi(ref.watch(supabaseProvider)));
