import 'package:shyam_mobiles/features/feedback/data/feedback.dart';
import 'package:shyam_mobiles/features/feedback/data/feedback_repository.dart';

import 'fake.dart';

/// Seed [entries] (newest first). Sending records the call and returns [sentId]; past [dailyLimit] sends it fails
/// with FEEDBACK_LIMIT.
class FakeFeedbackRepository with Fake implements FeedbackRepository {
  var entries = <FeedbackEntry>[];
  String sentId = 'f1';
  int dailyLimit = 10;
  final sent = <({FeedbackKind kind, int? rating, String message, String? orderId, String? repairId, String? productId})>[];
  final updates = <({String id, FeedbackStatus? status, String? adminNote})>[];

  @override
  Future<String> send({
    required FeedbackKind kind,
    int? rating,
    String message = '',
    String? orderId,
    String? repairId,
    String? productId,
    String? screen,
  }) async {
    record('send ${kind.name}');
    if (sent.length >= dailyLimit) throw reason('FEEDBACK_LIMIT');
    sent.add((kind: kind, rating: rating, message: message, orderId: orderId, repairId: repairId, productId: productId));
    return sentId;
  }

  @override
  Future<FeedbackEntry?> mine(String uid, FeedbackKind kind, String id) async {
    record('mine ${kind.name} $id');
    return entries.where((e) => e.kind == kind && (e.orderId == id || e.repairId == id)).firstOrNull;
  }

  @override
  Future<List<FeedbackEntry>> inbox(FeedbackFilter filter, int from, int size) async {
    record('inbox $from');
    final hits = entries
        .where((e) => filter.status == null || e.status == filter.status)
        .where((e) => filter.kind == null || e.kind == filter.kind)
        .where((e) => filter.productId == null || e.productId == filter.productId)
        .toList();
    return pageOf(hits, from, size);
  }

  @override
  Future<FeedbackEntry> entry(String id) async {
    record('entry $id');
    return entries.where((e) => e.id == id).firstOrNull ?? (throw reason('NOT_FOUND'));
  }

  @override
  Future<void> update(String id, {FeedbackStatus? status, String? adminNote}) async {
    record('update $id');
    updates.add((id: id, status: status, adminNote: adminNote));
  }

  @override
  Future<int> newCount() async {
    record('newCount');
    return entries.where((e) => e.status == FeedbackStatus.unread).length;
  }

  @override
  Future<FeedbackEntry?> about(FeedbackKind kind, String id) async {
    record('about ${kind.name} $id');
    return entries.where((e) => e.kind == kind && (e.orderId == id || e.repairId == id)).firstOrNull;
  }

  @override
  Future<int> listingReports(String productId) async {
    record('listingReports $productId');
    return entries.where((e) => e.kind == FeedbackKind.product && e.productId == productId).length;
  }
}
