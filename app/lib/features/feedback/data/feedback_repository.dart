import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart';
import '../../../core/supabase.dart';
import 'feedback.dart' show FeedbackApi, FeedbackEntry, FeedbackFilter, FeedbackKind, FeedbackStatus;
import 'feedback_repository_firebase.dart';

/// Ratings and comments (docs/FIREBASE.md §6: sendFeedback; staff track each one new → seen → resolved). Owner: D.
abstract interface class FeedbackRepository {
  /// Rating an order or a repair again replaces the earlier rating; FEEDBACK_LIMIT past 10 a day. Returns the id.
  Future<String> send({
    required FeedbackKind kind,
    int? rating,
    String message = '',
    String? orderId,
    String? repairId,
    String? productId,
    String? screen,
  });

  /// The customer's own rating of an order or a repair ([kind] order or repair), if any.
  Future<FeedbackEntry?> mine(String uid, FeedbackKind kind, String id);

  // Staff ------------------------------------------------------------------------------------------------------

  /// Newest first, rows [from]..[from + size − 1].
  Future<List<FeedbackEntry>> inbox(FeedbackFilter filter, int from, int size);

  Future<FeedbackEntry> entry(String id);

  /// Staff may change only these two fields.
  Future<void> update(String id, {FeedbackStatus? status, String? adminNote});

  Future<int> newCount();

  /// Staff: the customer's rating of this order or repair ([kind] order or repair), if any.
  Future<FeedbackEntry?> about(FeedbackKind kind, String id);

  /// Reports about one product listing (kind product), any status.
  Future<int> listingReports(String productId);
}

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) => backend == Backend.firebase
    ? FirebaseFeedbackRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider))
    : FeedbackApi(ref.watch(supabaseProvider)));
