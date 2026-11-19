import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/callable.dart';
import '../../../core/supabase.dart' show thumbPathFor;
import '../../admin/data/photos.dart' show PreparedPhoto;
import 'exchange_repository.dart';

ExchangeRequest exchangeFromDoc(String id, Map<String, dynamic> d) {
  final e = d['estimate'] as Map?;
  return ExchangeRequest(
    id: id,
    brand: d['brand'] as String,
    model: d['model'] as String,
    age: ExchangeAge.parse(d['age'] as String?),
    condition: ExchangeCondition.parse(d['condition'] as String?),
    photos: [for (final p in (d['photos'] as List? ?? const [])) p as String],
    lowPaise: (e?['lowPaise'] as num?)?.toInt(),
    highPaise: (e?['highPaise'] as num?)?.toInt(),
    note: e?['note'] as String? ?? '',
    createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );
}

/// exchanges/{id}: requestExchange and estimateExchange write, Rules let the customer and staff read; photos in
/// Storage exchange-photos/{uid}/ (the customer and staff only).
class FirebaseExchangeRepository implements ExchangeRepository {
  FirebaseExchangeRepository(this._db, this._functions, this._storage);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  @override
  bool get enabled => true;

  @override
  Future<String> request({
    required String brand,
    required String model,
    required ExchangeAge age,
    required ExchangeCondition condition,
    List<String> photos = const [],
    String? forProductId,
  }) async =>
      (await callFunction(_functions, 'requestExchange', {
        'brand': brand,
        'model': model,
        'age': age.value,
        'condition': condition.value,
        'photos': photos,
        'forProductId': forProductId,
      }))['exchangeId'] as String;

  @override
  Future<String> uploadPhoto(String uid, PreparedPhoto photo) async {
    final key = 'exchange-photos/$uid/${DateTime.now().millisecondsSinceEpoch}.webp';
    final meta = SettableMetadata(contentType: 'image/webp');
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
  Future<List<ExchangeRequest>> mine(String uid) async => [
        for (final d in (await _db
                .collection('exchanges')
                .where('uid', isEqualTo: uid)
                .orderBy('createdAt', descending: true)
                .limit(20)
                .get())
            .docs)
          exchangeFromDoc(d.id, d.data())
      ];

  @override
  Future<Uint8List?> photo(String key) => _storage.ref(thumbPathFor(key) ?? key).getData(1024 * 1024);

  @override
  Future<List<ExchangeRequest>> recent({int limit = 50}) async => [
        for (final d in (await _db.collection('exchanges').orderBy('createdAt', descending: true).limit(limit).get()).docs)
          exchangeFromDoc(d.id, d.data())
      ];

  @override
  Future<void> estimate(String id, {required int lowPaise, required int highPaise, String note = ''}) =>
      callFunction(_functions, 'estimateExchange', {'exchangeId': id, 'lowPaise': lowPaise, 'highPaise': highPaise, 'note': note});
}
