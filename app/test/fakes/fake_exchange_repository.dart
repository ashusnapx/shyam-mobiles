import 'dart:typed_data';

import 'package:shyam_mobiles/features/admin/data/photos.dart' show PreparedPhoto;
import 'package:shyam_mobiles/features/exchange/data/exchange_repository.dart';

import 'fake.dart';

class FakeExchangeRepository with Fake implements ExchangeRepository {
  @override
  bool enabled = true;
  var list = <ExchangeRequest>[];

  @override
  Future<String> request({
    required String brand,
    required String model,
    required ExchangeAge age,
    required ExchangeCondition condition,
    List<String> photos = const [],
    String? forProductId,
  }) async {
    record('request $brand $model ${age.value} ${condition.value} ${photos.length} $forProductId');
    return 'e1';
  }

  @override
  Future<String> uploadPhoto(String uid, PreparedPhoto photo) async => 'exchange-photos/$uid/1.webp';

  @override
  Future<List<ExchangeRequest>> mine(String uid) async => list;

  @override
  Future<Uint8List?> photo(String key) async => null;

  @override
  Future<List<ExchangeRequest>> recent({int limit = 50}) async => list;

  @override
  Future<void> estimate(String id, {required int lowPaise, required int highPaise, String note = ''}) async =>
      record('estimate $id $lowPaise $highPaise "$note"');
}
