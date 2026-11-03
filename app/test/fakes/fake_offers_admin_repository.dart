import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/offers_admin_repository.dart';

import 'fake.dart';

/// Saves land in [savedPromotions] / [savedBanners] by id; the lists are what the screens read back.
class FakeOffersAdminRepository with Fake implements OffersAdminRepository {
  var promotionList = <Promotion>[];
  var collectionList = <Collection>[];
  var bannerList = <PromoBanner>[];
  final savedPromotions = <String, Map<String, Object?>>{};
  final savedBanners = <String, Map<String, Object?>>{};
  final savedCollections = <String, Collection>{};
  var _next = 0;

  @override
  Future<List<Promotion>> promotions() async {
    record('promotions');
    return promotionList;
  }

  @override
  Future<String> savePromotion(Map<String, Object?> promotion) async {
    record('savePromotion');
    final id = promotion['id'] as String? ?? 'promo${_next++}';
    savedPromotions[id] = {...?savedPromotions[id], ...promotion, 'id': id};
    return id;
  }

  @override
  Future<void> deletePromotion(String id) async => record('deletePromotion $id');

  @override
  Future<List<Collection>> collections() async {
    record('collections');
    return collectionList;
  }

  @override
  Future<String> saveCollection(Collection collection, {Set<String> before = const {}}) async {
    record('saveCollection');
    final id = collection.id ?? 'group${_next++}';
    savedCollections[id] = collection;
    return id;
  }

  @override
  Future<void> deleteCollection(String id) async => record('deleteCollection $id');

  @override
  Future<List<PromoBanner>> banners() async {
    record('banners');
    return bannerList;
  }

  @override
  Future<String> saveBanner(String? id, Map<String, Object?> fields) async {
    record('saveBanner ${id ?? 'new'}');
    final saved = id ?? 'banner${_next++}';
    savedBanners[saved] = {...?savedBanners[saved], ...fields};
    return saved;
  }

  @override
  Future<void> deleteBanner(String id) async => record('deleteBanner $id');
}
