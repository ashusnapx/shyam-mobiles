import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/callable.dart';
import '../../../core/models/models.dart';
import '../../catalog/data/catalog_index.dart' show cardOf, indexCards;
import '../../orders/data/snake.dart';
import 'offers_repository.dart';

/// publicOffers + the caller's users/{uid}/coupons (docs/FIREBASE.md §3), judged like private.offer_open. The
/// per-user rules come from the caller's own orders (docs/FIREBASE.md §5 "Per-user offer data"); quoteOrder decides.
class FirebaseOffersRepository implements OffersRepository {
  const FirebaseOffersRepository(this._db, this._fn, this._auth);

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;
  final FirebaseAuth _auth;

  Offer _offer(DocumentSnapshot<Map<String, dynamic>> d) =>
      Offer.fromJson({...snakeMap(d.data()!, d.id), 'automatic': d.data()!['code'] == null});

  static bool _covers(Map<String, dynamic> p, String productId, String? category, String? brand, List<String> groups) =>
      p['appliesTo'] == 'order' ||
      (p['targets'] as List? ?? const []).any((t) => switch (t['type']) {
            'product' => t['id'] == productId,
            'category' => t['id'] == category,
            'brand' => t['id'] == brand,
            _ => groups.contains(t['id']),
          });

  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _open() async {
    final uid = _auth.currentUser?.uid;
    final now = DateTime.now();
    final public = _db.collection('publicOffers').where('usedUp', isEqualTo: false).limit(100).get();
    final mine = uid == null ? null : _db.collection('users/$uid/coupons').where('usedUp', isEqualTo: false).limit(100).get();
    final orders = uid == null
        ? null
        : _db.collection('orders').where('uid', isEqualTo: uid).where('status', isNotEqualTo: 'cancelled').limit(100).get();
    final placed = (await orders)?.docs ?? const [];
    final uses = <Object?, int>{};
    for (final o in placed) {
      final id = (o.data()['promotion'] as Map?)?['id'];
      uses[id] = (uses[id] ?? 0) + 1;
    }
    bool open(DocumentSnapshot<Map<String, dynamic>> s) {
      final p = s.data()!;
      final ends = (p['endsAt'] as Timestamp?)?.toDate();
      return p['isActive'] == true && !(p['startsAt'] as Timestamp).toDate().isAfter(now) && (ends == null || ends.isAfter(now)) &&
          (uid == null ||
              ((p['perUserLimit'] == null || (uses[s.id] ?? 0) < (p['perUserLimit'] as num)) && !(p['firstOrderOnly'] == true && placed.isNotEmpty)));
    }

    final personal = [...?(await mine)?.docs.where(open)];
    int byEnd(DocumentSnapshot<Map<String, dynamic>> a, DocumentSnapshot<Map<String, dynamic>> b) {
      final x = (a.data()!['endsAt'] as Timestamp?), y = (b.data()!['endsAt'] as Timestamp?);
      return x == null ? (y == null ? 0 : 1) : (y == null ? -1 : x.compareTo(y));
    }

    return [...personal..sort(byEnd), ...(await public).docs.where(open).toList()..sort(byEnd)]; // personal coupons first
  }

  @override
  Future<List<Offer>> available() async => [for (final d in await _open()) _offer(d)];

  @override
  Future<List<Offer>> forProduct(String productId) async {
    final (product, groups, offers) = await (
      _db.doc('products/$productId').get(),
      _db.collection('collections').where('productIds', arrayContains: productId).limit(50).get(),
      _open(),
    ).wait;
    final p = product.data() ?? const {};
    final ids = [for (final g in groups.docs) g.id];
    return [
      for (final o in offers)
        if (_covers(o.data()!, productId, p['categoryId'] as String?, p['brandId'] as String?, ids)) _offer(o),
    ];
  }

  @override
  Future<List<ProductCard>> products(String promotionId, int from, int size) async {
    final uid = _auth.currentUser?.uid;
    var offer = await _db.doc('publicOffers/$promotionId').get();
    if (!offer.exists && uid != null) offer = await _db.doc('users/$uid/coupons/$promotionId').get();
    final p = offer.data();
    if (p == null) return const [];
    final cards = indexCards((await _db.doc('catalogIndex/public').get()).data()).entries
        .where((e) => _covers(p, e.key, e.value['c'] as String?, e.value['b'] as String?, [...(e.value['col'] as List? ?? const [])].cast<String>()))
        .map((e) => cardOf(e.key, e.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name) != 0 ? a.name.compareTo(b.name) : a.id.compareTo(b.id));
    return cards.skip(from).take(size).toList();
  }

  @override
  Future<List<PromoBanner>> banners() async => [
        for (final d in (await _db.collection('banners').where('isActive', isEqualTo: true).orderBy('sort').limit(50).get()).docs)
          PromoBanner.fromJson(snakeMap(d.data(), d.id)),
      ];

  @override
  Future<Referral> myReferral() async => Referral.fromJson(snakeMap(await callFunction(_fn, 'myReferral')));

  @override
  Future<Offer> applyReferral(String code) async =>
      Offer.fromJson(snakeMap(await callFunction(_fn, 'applyReferralCode', {'code': code})));
}
