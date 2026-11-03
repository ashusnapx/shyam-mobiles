import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import 'offers_admin_repository.dart';

/// Staff reads and writes for offers, groups and banners (tests override this provider), from OffersAdminRepository.
class AdminOffersApi {
  const AdminOffersApi(this._repo);

  final OffersAdminRepository _repo;

  /// Every promotion with its status, targets, uses and discount total, newest first.
  Future<List<Promotion>> promotions() => _repo.promotions();

  /// Inserts without `id`, else updates only the keys given (`{id, is_active: false}` pauses), checking every rule
  /// again. Returns the id.
  Future<String> savePromotion(Map<String, dynamic> p) => _repo.savePromotion(p);

  /// Only a promotion no live order used.
  Future<void> deletePromotion(String id) => _repo.deletePromotion(id);

  Future<List<Collection>> collections() => _repo.collections();

  /// Only the difference from [before] is written, new products first. Returns the id.
  Future<String> saveCollection(Collection c, {Set<String> before = const {}}) => _repo.saveCollection(c, before: before);

  Future<void> deleteCollection(String id) => _repo.deleteCollection(id);

  Future<List<PromoBanner>> banners() => _repo.banners();

  /// Inserts when [id] is null. Returns the id.
  Future<String> saveBanner(String? id, Map<String, dynamic> fields) => _repo.saveBanner(id, fields);

  Future<void> deleteBanner(String id) => _repo.deleteBanner(id);
}

final adminOffersApiProvider = Provider<AdminOffersApi>((ref) => AdminOffersApi(ref.watch(offersAdminRepositoryProvider)));

final adminPromotionsProvider =
    FutureProvider.autoDispose<List<Promotion>>((ref) => ref.watch(adminOffersApiProvider).promotions());

final adminCollectionsProvider =
    FutureProvider.autoDispose<List<Collection>>((ref) => ref.watch(adminOffersApiProvider).collections());

final adminBannersProvider =
    FutureProvider.autoDispose<List<PromoBanner>>((ref) => ref.watch(adminOffersApiProvider).banners());

/// Same rules as the DB checks (docs/SPEC.md "Offers").
final collectionSlugPattern = RegExp(r'^[a-z0-9-]{1,60}$');
const maxPercentOff = 90;
const minFlatPaise = 100; // ₹1

/// An 8-character code with no look-alikes (no 0/O, 1/I/L), easy to read out over the phone.
String generateCode([Random? random]) {
  const letters = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final r = random ?? Random.secure();
  return String.fromCharCodes([for (var i = 0; i < 8; i++) letters.codeUnitAt(r.nextInt(letters.length))]);
}
