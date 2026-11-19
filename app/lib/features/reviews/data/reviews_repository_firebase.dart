import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/callable.dart';
import '../../../core/supabase.dart' show thumbPathFor;
import '../../admin/data/photos.dart' show PreparedPhoto;
import 'reviews_repository.dart';

Review reviewFromDoc(String id, Map<String, dynamic> d) => Review(
      id: id,
      productId: d['productId'] as String,
      uid: d['uid'] as String,
      name: d['name'] as String? ?? 'Customer',
      rating: (d['rating'] as num).toInt(),
      text: d['text'] as String? ?? '',
      photos: [for (final p in (d['photos'] as List? ?? const [])) p as String],
      hidden: d['hidden'] == true,
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );

Map<String, int> _counts(Object? m) => {for (final e in ((m as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt()};

ProductStats statsFromDoc(Map<String, dynamic>? d) => d == null
    ? const ProductStats()
    : ProductStats(
        ratingCount: (d['ratingCount'] as num?)?.toInt() ?? 0,
        ratingSum: (d['ratingSum'] as num?)?.toInt() ?? 0,
        stars: [for (final s in (d['stars'] as List? ?? const [0, 0, 0, 0, 0])) (s as num).toInt()],
        sold: _counts(d['sold']),
        boughtWith: _counts(d['with']),
      );

/// reviews/{productId}_{uid} (saveReview writes; Rules: visible ones public, staff hide), productStats/{id} and
/// reviewIndex/public (triggers), photos in Storage review-photos/{uid}/.
class FirebaseReviewsRepository implements ReviewsRepository {
  FirebaseReviewsRepository(this._db, this._functions, this._storage);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _reviews => _db.collection('reviews');

  @override
  Future<ProductStats> stats(String productId) async => statsFromDoc((await _db.doc('productStats/$productId').get()).data());

  @override
  Future<List<Review>> reviews(String productId, {int limit = 20}) async => [
        for (final d in (await _reviews
                .where('productId', isEqualTo: productId)
                .where('hidden', isEqualTo: false)
                .orderBy('updatedAt', descending: true)
                .limit(limit)
                .get())
            .docs)
          reviewFromDoc(d.id, d.data())
      ];

  /// Rules: a customer lists orders filtered on their own uid.
  @override
  Future<Set<String>> reviewable(String uid) async => {
        for (final o in (await _db
                .collection('orders')
                .where('uid', isEqualTo: uid)
                .where('status', isEqualTo: 'delivered')
                .limit(50)
                .get())
            .docs)
          for (final i in (o.data()['items'] as List? ?? const [])) (i as Map)['productId'] as String,
      };

  @override
  Future<Review?> mine(String uid, String productId) async {
    final d = await _reviews.doc('${productId}_$uid').get();
    return d.exists ? reviewFromDoc(d.id, d.data()!) : null;
  }

  @override
  Future<void> save({required String productId, required int rating, String text = '', List<String> photos = const []}) =>
      callFunction(_functions, 'saveReview', {'productId': productId, 'rating': rating, 'text': text, 'photos': photos});

  @override
  Future<String> uploadPhoto(String uid, PreparedPhoto photo) async {
    final key = 'review-photos/$uid/${DateTime.now().millisecondsSinceEpoch}.webp';
    final meta = SettableMetadata(contentType: 'image/webp', cacheControl: 'public, max-age=31536000');
    await _storage.ref(key).putData(photo.full, meta);
    try {
      await _storage.ref(thumbPathFor(key)!).putData(photo.thumb, meta);
    } catch (_) {
      await _storage.ref(key).delete().catchError((_) {});
      rethrow;
    }
    return key;
  }

  @override
  Stream<Map<String, TileRating>> tileRatings() => _db.doc('reviewIndex/public').snapshots().map((s) => {
        for (final e in ((s.data()?['cards'] as Map?) ?? const {}).entries)
          e.key as String: (avg10: ((e.value as Map)['a'] as num).toInt(), count: ((e.value as Map)['n'] as num).toInt()),
      });

  @override
  Future<List<Review>> recent({int limit = 50}) async => [
        for (final d in (await _reviews.orderBy('updatedAt', descending: true).limit(limit).get()).docs)
          reviewFromDoc(d.id, d.data())
      ];

  @override
  Future<void> setHidden(String id, {required bool hidden}) =>
      _reviews.doc(id).update({'hidden': hidden, 'updatedAt': FieldValue.serverTimestamp()});
}
