import 'package:cloud_firestore/cloud_firestore.dart';

import 'wishlist_repository.dart';

/// users/{uid}/wishlist/{productId} {productId, addedAt, waitVariant} (docs/FIREBASE.md §3). waitVariant is D's
/// back-in-stock mark; a plain heart leaves it null.
class FirebaseWishlistRepository implements WishlistRepository {
  const FirebaseWishlistRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _of(String uid) => _db.collection('users/$uid/wishlist');

  @override
  Future<List<String>> productIds(String uid) async =>
      [for (final d in (await _of(uid).orderBy('addedAt', descending: true).get()).docs) d.id];

  /// A doc already there keeps its addedAt; Rules let it change only its mark.
  @override
  Future<void> add(String uid, String productId, {String? waitFor}) async {
    final ref = _of(uid).doc(productId);
    if ((await ref.get()).exists) {
      if (waitFor != null) await ref.update({'waitVariant': waitFor});
      return;
    }
    await ref.set({'productId': productId, 'addedAt': FieldValue.serverTimestamp(), 'waitVariant': waitFor});
  }

  @override
  Future<void> remove(String uid, String productId) => _of(uid).doc(productId).delete();
}
