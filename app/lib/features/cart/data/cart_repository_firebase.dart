import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/models.dart';
import '../../catalog/data/catalog_repository_firebase.dart' show isDenied, variantFromDoc;
import 'cart_repository.dart';

/// carts/{uid} `{lines: {variantId: {qty, addedAt}}, updatedAt}` (Rules: the owner, ≤ 20 lines). The variant and its
/// product are read for each line; one the shop hid (Rules deny it) or deleted comes back in `hidden`.
class FirebaseCartRepository implements CartRepository {
  const FirebaseCartRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _cart(String uid) => _db.doc('carts/$uid');

  Future<Map<String, dynamic>?> _read(String path) async {
    try {
      return (await _db.doc(path).get()).data();
    } catch (e) {
      if (isDenied(e)) return null;
      rethrow;
    }
  }

  @override
  Future<({List<CartLine> lines, List<String> hidden})> load(String uid) async {
    final raw = Map<String, dynamic>.from((await _cart(uid).get()).data()?['lines'] as Map? ?? const {});
    final ids = raw.keys.toList()
      ..sort((a, b) => ((raw[a]['addedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
          .compareTo((raw[b]['addedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
    final variants = await Future.wait(ids.map((id) => _read('variants/$id')));
    final products = <String, Future<Map<String, dynamic>?>>{};
    final lines = <CartLine>[], hidden = <String>[];
    for (final (i, id) in ids.indexed) {
      final v = variants[i];
      final p = v == null ? null : await products.putIfAbsent(v['productId'] as String, () => _read('products/${v['productId']}'));
      if (v == null || p == null) {
        hidden.add(id);
        continue;
      }
      final images = [...(p['images'] as List? ?? const [])]..sort((a, b) => (a['sort'] as num).compareTo(b['sort'] as num));
      lines.add(CartLine(
        variant: variantFromDoc(id, v),
        qty: (raw[id]['qty'] as num).toInt(),
        productId: v['productId'] as String,
        productSlug: v['productId'] as String, // the slug is the product's id
        productName: p['name'] as String,
        productActive: p['isActive'] == true,
        coverPath: images.isEmpty ? null : images.first['path'] as String,
      ));
    }
    return (lines: lines, hidden: hidden);
  }

  @override
  Future<void> put(String uid, String variantId, int qty) async {
    final ref = _cart(uid);
    final lines = (await ref.get()).data()?['lines'] as Map?;
    if (lines?.containsKey(variantId) ?? false) {
      await ref.update({'lines.$variantId.qty': qty, 'updatedAt': FieldValue.serverTimestamp()});
    } else {
      await ref.set({
        'lines': {variantId: {'qty': qty, 'addedAt': Timestamp.now()}},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  @override
  Future<void> remove(String uid, List<String> variantIds) async {
    if (variantIds.isEmpty) return;
    await _cart(uid).update({for (final id in variantIds) 'lines.$id': FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()});
  }
}
