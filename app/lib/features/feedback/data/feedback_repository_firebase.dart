import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/callable.dart';
import 'feedback.dart' show FeedbackEntry, FeedbackFilter, FeedbackKind, FeedbackStatus;
import 'feedback_repository.dart';

/// feedback/{id} (firebase/functions/src/feedback): written by `sendFeedback`, read under Rules (own or staff); staff
/// set status and adminNote directly.
class FirebaseFeedbackRepository implements FeedbackRepository {
  FirebaseFeedbackRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _feedback => _db.collection('feedback');

  /// The doc as the screens want it: the order or repair number, the product name and the customer's contact come
  /// from the linked docs (staff can't read profiles).
  Future<FeedbackEntry> _entry(DocumentSnapshot<Map<String, dynamic>> d) async {
    final j = d.data()!;
    Future<Map<String, dynamic>?> linked(String path, Object? id) async =>
        id is String ? (await _db.doc('$path/$id').get()).data() : null;
    final (order, repair, product) =
        await (linked('orders', j['orderId']), linked('repairs', j['repairId']), linked('products', j['productId'])).wait;
    final address = order?['address'] as Map<String, dynamic>?;
    return FeedbackEntry(
      id: d.id,
      kind: FeedbackKind.values.byName(j['kind']),
      rating: j['rating'],
      message: j['message'] ?? '',
      orderId: j['orderId'],
      repairId: j['repairId'],
      productId: j['productId'],
      screen: j['screen'],
      status: FeedbackStatus.parse(j['status']),
      adminNote: j['adminNote'],
      createdAt: (j['createdAt'] as Timestamp).toDate(),
      orderNumber: order?['number'],
      repairNumber: repair?['number'],
      productName: product?['name'],
      customerName: address?['name'],
      customerPhone: address?['phone'] ?? repair?['contactPhone'],
    );
  }

  /// shortcut: offset paging reads the rows before [from] again; fine at shop volume, use cursors past ~1,000 rows.
  Future<List<FeedbackEntry>> _page(Query<Map<String, dynamic>> q, int from, int size) async {
    final docs = (await q.limit(from + size).get()).docs.skip(from);
    return Future.wait(docs.map(_entry));
  }

  @override
  Future<String> send({
    required FeedbackKind kind,
    int? rating,
    String message = '',
    String? orderId,
    String? repairId,
    String? productId,
    String? screen,
  }) async =>
      (await callFunction(_functions, 'sendFeedback', {
        'kind': kind.name,
        'rating': ?rating,
        'message': message,
        'orderId': ?orderId,
        'repairId': ?repairId,
        'productId': ?productId,
        'screen': ?screen,
      }))['id'] as String;

  @override
  Future<FeedbackEntry?> mine(String uid, FeedbackKind kind, String id) async {
    final hits = await _feedback
        .where('uid', isEqualTo: uid)
        .where(kind == FeedbackKind.order ? 'orderId' : 'repairId', isEqualTo: id)
        .limit(1)
        .get();
    return hits.docs.isEmpty ? null : _entry(hits.docs.first);
  }

  @override
  Future<FeedbackEntry?> about(FeedbackKind kind, String id) async {
    final d = await _feedback.doc('${kind.name}_$id').get();
    return d.exists ? _entry(d) : null;
  }

  @override
  Future<List<FeedbackEntry>> inbox(FeedbackFilter f, int from, int size) {
    Query<Map<String, dynamic>> q = _feedback;
    if (f.status != null) q = q.where('status', isEqualTo: f.status!.value);
    if (f.kind != null) q = q.where('kind', isEqualTo: f.kind!.name);
    if (f.productId != null) q = q.where('productId', isEqualTo: f.productId);
    return _page(q.orderBy('createdAt', descending: true), from, size);
  }

  @override
  Future<FeedbackEntry> entry(String id) async => _entry(await _feedback.doc(id).get());

  @override
  Future<void> update(String id, {FeedbackStatus? status, String? adminNote}) => _feedback.doc(id).update({
        'status': ?status?.value,
        'adminNote': ?adminNote,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<int> newCount() async => (await _feedback.where('status', isEqualTo: 'new').count().get()).count ?? 0;

  @override
  Future<int> listingReports(String productId) async =>
      (await _feedback.where('kind', isEqualTo: 'product').where('productId', isEqualTo: productId).count().get()).count ?? 0;
}
