import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';

/// Staff promotions, product groups and banners (today's AdminOffersApi). Owner: engineer C.
abstract interface class OffersAdminRepository {
  Future<List<Promotion>> promotions();

  /// Creates without an `id`, else changes only the fields sent; returns the id. INVALID_PROMOTION (detail: the
  /// rule), CODE_TAKEN. Firebase: savePromotion, which also writes the code, the mirrors and the banner.
  Future<String> savePromotion(Map<String, Object?> promotion);

  Future<void> deletePromotion(String id);

  Future<List<Collection>> collections();

  /// [before]: the product ids the group had when the form opened, so only the difference is written.
  Future<String> saveCollection(Collection collection, {Set<String> before = const {}});

  Future<void> deleteCollection(String id);

  Future<List<PromoBanner>> banners();

  /// Creates when [id] is null; returns the id.
  Future<String> saveBanner(String? id, Map<String, Object?> fields);

  Future<void> deleteBanner(String id);
}

final offersAdminRepositoryProvider =
    Provider<OffersAdminRepository>((ref) => throw UnimplementedError('Phase 1: OffersAdminRepository'));
