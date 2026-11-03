import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import 'admin.dart' show AdminProductRow;
import 'catalog_admin_repository.dart';
import 'catalogue.dart' show CatalogueRow, CatalogueSummary, CatalogueView, catalogueSummaryFromJson;
import 'rules.dart' show slugify;

const _productColumns = 'id, slug, name, is_active, is_featured, brand:brands(name), category:categories(name), '
    'images:product_images(path, sort), variants(stock, is_active)';

/// Today's staff reads and writes: the admin_catalogue RPC and direct table writes under the "admin write" RLS
/// policies, moved here unchanged. Deleted in Phase 2.
class SupabaseCatalogAdminRepository implements CatalogAdminRepository {
  const SupabaseCatalogAdminRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<({List<CatalogueRow> rows, CatalogueSummary summary})> catalogue(CatalogueView v,
      {required int offset, required int limit}) async {
    final j = await _db.rpc<Map<String, dynamic>>('admin_catalogue', params: {
      'p_query': v.query,
      'p_category_id': v.categoryId,
      'p_brand_id': v.brandId,
      'p_stock': v.stock.name,
      'p_visibility': v.visibility.name,
      'p_sort': v.sort.name,
      'p_offset': offset,
      'p_limit': limit,
    });
    final summary = j['summary'] as Map<String, dynamic>?; // the RPC sends it with the first page only
    return (
      rows: [for (final r in j['rows'] as List) CatalogueRow.fromJson(r as Map<String, dynamic>)],
      summary: summary == null
          ? (skus: 0, units: 0, valueAtPricePaise: 0, valueAtMrpPaise: 0, low: 0, out: 0, total: 0)
          : catalogueSummaryFromJson(summary),
    );
  }

  /// A guarded edit is one PATCH that matches only while the row holds the value shown; unguarded edits with the same
  /// change go out together, one PATCH per 100 ids (keeps the URL near 4 KB).
  @override
  Future<List<String>> updateVariants(List<VariantEdit> edits) async {
    final stale = <String>[];
    Map<String, Object> fields(VariantEdit e) => {
          'stock': ?e.stock,
          'price_paise': ?e.pricePaise,
          'mrp_paise': ?e.mrpPaise,
          'is_active': ?e.isActive,
        };
    final same = <String, List<VariantEdit>>{};
    for (final e in edits) {
      if (e.expectStock == null && e.expectPricePaise == null) {
        (same[fields(e).toString()] ??= []).add(e);
        continue;
      }
      var q = _db.from('variants').update(fields(e)).eq('id', e.variantId);
      q = e.expectStock != null ? q.eq('stock', e.expectStock!) : q.eq('price_paise', e.expectPricePaise!);
      if ((await q.select('id')).isEmpty) stale.add(e.variantId);
    }
    for (final group in same.values) {
      for (var i = 0; i < group.length; i += 100) {
        final ids = [for (final e in group.sublist(i, min(i + 100, group.length))) e.variantId];
        final done = {for (final r in await _db.from('variants').update(fields(group.first)).inFilter('id', ids).select('id')) r['id']};
        stale.addAll(ids.where((id) => !done.contains(id))); // a row vanished, or RLS refused it
      }
    }
    return stale;
  }

  @override
  Future<void> setFeatured(List<String> productIds, bool featured) async {
    for (var i = 0; i < productIds.length; i += 100) {
      final ids = productIds.sublist(i, min(i + 100, productIds.length));
      final done = await _db.from('products').update({'is_featured': featured}).inFilter('id', ids).select('id');
      if (done.length != ids.length) throw const PostgrestException(message: 'not found', code: 'PGRST116');
    }
  }

  /// shortcut: PostgREST's max_rows (1000) caps it; page the pickers through search if the shop passes 1000 products.
  @override
  Future<List<AdminProductRow>> products() async => [
        for (final r in await _db.from('products').select(_productColumns).order('name', ascending: true).order('id'))
          AdminProductRow.fromJson(r)
      ];

  @override
  Future<Product> product(String id) async => Product.fromJson(await _db
      .from('products')
      .select('*, brand:brands(*), category:categories(*), images:product_images(*), variants(*)')
      .eq('id', id)
      .single());

  @override
  Future<String> saveProduct(String? id, Map<String, Object?> fields) async {
    final products = _db.from('products');
    final row = id == null
        ? await products.insert(fields).select('id').single()
        : await products.update(fields).eq('id', id).select('id').single();
    return row['id'] as String;
  }

  @override
  Future<void> saveVariant(String productId, String? variantId, Map<String, Object?> fields) async {
    final variants = _db.from('variants');
    if (variantId == null) {
      await variants.insert({...fields, 'product_id': productId});
    } else {
      await variants.update(fields).eq('id', variantId).select('id').single();
    }
  }

  /// product_images rows: new photos (empty id) are inserted, dropped ones deleted, moved or recoloured ones updated.
  @override
  Future<void> setProductImages(String productId, List<ProductPhoto> images) async {
    final current = {
      for (final r in await _db.from('product_images').select().eq('product_id', productId)) r['id'] as String: ProductPhoto.fromJson(r)
    };
    final kept = {for (final i in images) i.id};
    for (final id in current.keys.where((id) => !kept.contains(id))) {
      await _db.from('product_images').delete().eq('id', id);
    }
    for (final i in images) {
      final was = current[i.id];
      if (was == null) {
        await _db.from('product_images').insert({'product_id': productId, 'path': i.path, 'sort': i.sort, 'color': i.color});
      } else if (was.sort != i.sort || was.color != i.color) {
        await _db.from('product_images').update({'sort': i.sort, 'color': i.color}).eq('id', i.id);
      }
    }
  }

  @override
  Future<void> deleteProduct(String id) => throw UnsupportedError('Products are hidden, never deleted, on this build');

  @override
  Future<Brand> createBrand(String name) async {
    final slug = slugify(name);
    Map<String, dynamic> row;
    try {
      row = await _db.from('brands').insert({'slug': slug, 'name': name}).select().single();
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow; // already exists under another spelling: use it
      row = await _db.from('brands').select().eq('slug', slug).single();
    }
    return Brand.fromJson(row);
  }
}
