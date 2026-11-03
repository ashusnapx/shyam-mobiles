import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/callable.dart';
import '../../../core/models/models.dart';
import '../../orders/data/snake.dart';
import 'offers_admin_repository.dart';

/// Staff read promotions, groups and banners under Rules; a promotion is written only by savePromotion /
/// deletePromotion (with its code, mirror and banner), groups and banners are staff writes.
class FirebaseOffersAdminRepository implements OffersAdminRepository {
  const FirebaseOffersAdminRepository(this._db, this._fn);

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  static const _contract = {
    'id', 'title', 'description', 'code', 'kind', 'value', 'maxDiscountPaise', 'minSubtotalPaise', 'appliesTo', 'targets',
    'startsAt', 'endsAt', 'usageLimit', 'perUserLimit', 'firstOrderOnly', 'onlineOnly', 'isPublic', 'uid', 'isActive', 'showBanner',
  };

  static Promotion _promotion(String id, Map<String, dynamic> d) {
    final now = DateTime.now();
    final starts = (d['startsAt'] as Timestamp).toDate(), ends = (d['endsAt'] as Timestamp?)?.toDate();
    final status = d['isActive'] != true
        ? 'paused'
        : ends != null && !ends.isAfter(now)
            ? 'ended'
            : starts.isAfter(now)
                ? 'scheduled'
                : 'running';
    return Promotion.fromJson({
      ...snakeMap(d, id),
      'user_id': d['uid'],
      'uses': d['usesActive'],
      'status': status,
      'targets': [for (final t in (d['targets'] as List? ?? const [])) {'target_type': t['type'], 'target_id': t['id']}],
    });
  }

  @override
  Future<List<Promotion>> promotions() async => [
        for (final d in (await _db.collection('promotions').orderBy('createdAt', descending: true).limit(100).get()).docs)
          _promotion(d.id, d.data()),
      ];

  @override
  Future<String> savePromotion(Map<String, Object?> promotion) async {
    final p = camelMap(promotion);
    final input = {
      for (final e in p.entries)
        if (_contract.contains(e.key)) e.key: e.value,
      if (p.containsKey('userId')) 'uid': p['userId'],
      if (p['targets'] is List)
        'targets': [for (final t in p['targets'] as List) {'type': t['target_type'], 'id': t['target_id']}],
    };
    return (await callFunction(_fn, 'savePromotion', input))['id'] as String;
  }

  @override
  Future<void> deletePromotion(String id) => callFunction(_fn, 'deletePromotion', {'id': id});

  @override
  Future<List<Collection>> collections() async => [
        for (final d in (await _db.collection('collections').orderBy('name').limit(100).get()).docs)
          Collection(id: d.id, slug: d.id, name: d['name'] as String, productIds: {...(d['productIds'] as List).cast<String>()}),
      ];

  /// The group's doc id is its slug.
  @override
  Future<String> saveCollection(Collection c, {Set<String> before = const {}}) async {
    final ref = _db.doc('collections/${c.id ?? c.slug}');
    final fields = {'name': c.name, 'productIds': [...c.productIds], 'updatedAt': FieldValue.serverTimestamp()};
    if (c.id == null) {
      await ref.set({...fields, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      await ref.update(fields);
    }
    return ref.id;
  }

  @override
  Future<void> deleteCollection(String id) => _db.doc('collections/$id').delete();

  @override
  Future<List<PromoBanner>> banners() async => [
        for (final d in (await _db.collection('banners').orderBy('sort').limit(100).get()).docs) PromoBanner.fromJson(snakeMap(d.data(), d.id)),
      ];

  @override
  Future<String> saveBanner(String? id, Map<String, Object?> fields) async {
    final f = camelMap(fields);
    for (final k in ['startsAt', 'endsAt']) {
      if (f[k] case final String iso) f[k] = Timestamp.fromDate(DateTime.parse(iso));
    }
    final ref = id == null ? _db.collection('banners').doc() : _db.doc('banners/$id');
    if (id == null) {
      await ref.set({...f, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
    } else {
      await ref.update({...f, 'updatedAt': FieldValue.serverTimestamp()});
    }
    return ref.id;
  }

  @override
  Future<void> deleteBanner(String id) => _db.doc('banners/$id').delete();
}
