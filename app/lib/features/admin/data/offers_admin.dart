import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart';

/// Staff reads and writes for offers, groups and banners (RLS: is_admin()); a provider so tests can swap it.
class AdminOffersApi {
  const AdminOffersApi(this._db);

  final SupabaseClient _db;

  /// `admin_promotions()`: every promotion with its `status`, `targets`, `uses` and `discount_total_paise`, newest first.
  Future<List<Promotion>> promotions() async =>
      [for (final r in await _db.rpc<List<dynamic>>('admin_promotions')) Promotion.fromJson(r as Map<String, dynamic>)];

  /// `admin_save_promotion(p)`: inserts without `id`, else updates only the keys given (`{id, is_active: false}`
  /// pauses), with the targets in the same transaction, checking every rule again. Returns the id.
  Future<String> savePromotion(Map<String, dynamic> p) async => await _db.rpc<String>('admin_save_promotion', params: {'p': p});

  /// RLS deletes only a promotion no live order used; a used one deletes no row, so `.single()` throws PGRST116.
  Future<void> deletePromotion(String id) async {
    await _db.from('promotions').delete().eq('id', id).select('id').single();
  }

  Future<List<Collection>> collections() async {
    final rows = await _db.from('collections').select('*, products:collection_products(product_id)').order('name');
    return [for (final r in rows) Collection.fromJson(r)];
  }

  /// Saves the group, then its products: new ones first, removed ones last, so a failure part-way never drops
  /// products from a group a running offer may target. Returns the id.
  Future<String> saveCollection(Collection c, {Set<String> before = const {}}) async {
    final fields = {'slug': c.slug, 'name': c.name};
    final table = _db.from('collections');
    final row = c.id == null
        ? await table.insert(fields).select('id').single()
        : await table.update(fields).eq('id', c.id!).select('id').single();
    final id = row['id'] as String;
    final added = c.productIds.difference(before), removed = before.difference(c.productIds);
    if (added.isNotEmpty) {
      await _db
          .from('collection_products')
          .upsert([for (final p in added) {'collection_id': id, 'product_id': p}], ignoreDuplicates: true);
    }
    if (removed.isNotEmpty) {
      await _db.from('collection_products').delete().eq('collection_id', id).inFilter('product_id', removed.toList());
    }
    return id;
  }

  Future<void> deleteCollection(String id) async {
    await _db.from('collection_products').delete().eq('collection_id', id);
    await _db.from('collections').delete().eq('id', id).select('id').single();
  }

  Future<List<PromoBanner>> banners() async {
    final rows = await _db.from('banners').select().order('sort').order('created_at');
    return [for (final r in rows) PromoBanner.fromJson(r)];
  }

  /// Inserts when [id] is null. Returns the id.
  Future<String> saveBanner(String? id, Map<String, dynamic> fields) async {
    final table = _db.from('banners');
    final row = id == null
        ? await table.insert(fields).select('id').single()
        : await table.update(fields).eq('id', id).select('id').single();
    return row['id'] as String;
  }

  Future<void> deleteBanner(String id) async {
    await _db.from('banners').delete().eq('id', id).select('id').single();
  }
}

final adminOffersApiProvider = Provider<AdminOffersApi>((ref) => AdminOffersApi(ref.watch(supabaseProvider)));

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
