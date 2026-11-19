import 'dart:typed_data';

import '../../admin/data/photos.dart' show PreparedPhoto;
import 'exchange_repository.dart';

/// Before the cut-over requests aren't saved: the sheet offers WhatsApp only. Deleted in Phase 2.
class SupabaseExchangeRepository implements ExchangeRepository {
  const SupabaseExchangeRepository();

  @override
  bool get enabled => false;

  @override
  Future<String> request({
    required String brand,
    required String model,
    required ExchangeAge age,
    required ExchangeCondition condition,
    List<String> photos = const [],
    String? forProductId,
  }) =>
      throw UnsupportedError('Exchange requests need the Firebase backend');

  @override
  Future<String> uploadPhoto(String uid, PreparedPhoto photo) => throw UnsupportedError('Exchange requests need the Firebase backend');

  @override
  Future<List<ExchangeRequest>> mine(String uid) async => const [];

  @override
  Future<Uint8List?> photo(String key) => throw UnsupportedError('Exchange requests need the Firebase backend');

  @override
  Future<List<ExchangeRequest>> recent({int limit = 50}) async => const [];

  @override
  Future<void> estimate(String id, {required int lowPaise, required int highPaise, String note = ''}) =>
      throw UnsupportedError('Exchange requests need the Firebase backend');
}
