import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import 'offers_admin_repository.dart';

/// Today's staff offer queries (RLS: is_admin()). Deleted in Phase 2.
class SupabaseOffersAdminRepository implements OffersAdminRepository {
  const SupabaseOffersAdminRepository(this._db);

  final SupabaseClient _db;

  /// `admin_promotions()`: every promotion with its `status`, `targets`, `uses` and `discount_total_paise`, newest first.
  @override
  Future<List<Promotion>> promotions() async =>
      [for (final r in await _db.rpc<List<dynamic>>('admin_promotions')) Promotion.fromJson(r as Map<String, dynamic>)];

  /// `admin_save_promotion(p)`: inserts without `id`, else updates only the keys given, with the targets in the same
  /// transaction, checking every rule again.
  @override
  Future<String> savePromotion(Map<String, Object?> promotion) async =>
      await _db.rpc<String>('admin_save_promotion', params: {'p': promotion});

  /// RLS deletes only a promotion no live order used; a used one deletes no row, so `.single()` throws PGRST116.
  @override
  Future<void> deletePromotion(String id) async {
    await _db.from('promotions').delete().eq('id', id).select('id').single();
  }

  @override
  Future<List<Collection>> collections() async =>
      [for (final r in await _db.from('collections').select('*, products:collection_products(product_id)').order('name')) Collection.fromJson(r)];

  /// Saves the group, then its products: new ones first, removed ones last, so a failure part-way never drops
  /// products from a group a running offer may target.
  @override
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

  @override
  Future<void> deleteCollection(String id) async {
    await _db.from('collection_products').delete().eq('collection_id', id);
    await _db.from('collections').delete().eq('id', id).select('id').single();
  }

  @override
  Future<List<PromoBanner>> banners() async =>
      [for (final r in await _db.from('banners').select().order('sort').order('created_at')) PromoBanner.fromJson(r)];

  @override
  Future<String> saveBanner(String? id, Map<String, Object?> fields) async {
    final table = _db.from('banners');
    final row = id == null
        ? await table.insert(fields).select('id').single()
        : await table.update(fields).eq('id', id).select('id').single();
    return row['id'] as String;
  }

  @override
  Future<void> deleteBanner(String id) async {
    await _db.from('banners').delete().eq('id', id).select('id').single();
  }
}
