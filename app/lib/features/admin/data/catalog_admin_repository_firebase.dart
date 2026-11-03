import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/callable.dart';
import '../../../core/models/models.dart';
import '../../catalog/data/catalog_index.dart' show IndexCards, indexCards;
import '../../catalog/data/catalog_repository_firebase.dart' show productFromDoc, variantFromDoc;
import 'admin.dart' show AdminProductRow;
import 'catalog_admin_repository.dart';
import 'catalogue.dart';
import 'rules.dart' show slugify;

/// Every variant of catalogIndex/staff as catalogue rows.
List<CatalogueRow> staffRows(IndexCards cards) => [
      for (final MapEntry(key: productId, value: c) in cards.entries)
        for (final v in (c['variants'] as List? ?? const []).cast<Map>())
          CatalogueRow(
            variantId: v['id'] as String,
            productId: productId,
            productName: c['n'] as String,
            variantName: v['n'] as String,
            sku: v['sku'] as String,
            pricePaise: (v['p'] as num).toInt(),
            mrpPaise: (v['m'] as num).toInt(),
            stock: (v['st'] as num).toInt(),
            variantActive: v['a'] == true,
            productActive: c['active'] == true,
            featured: c['f'] == true,
            categoryId: c['c'] as String,
            brandId: c['b'] as String,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(max((v['u'] as num).toInt(), (c['u'] as num).toInt())),
            coverPath: c['cv'] as String?,
          ),
    ];

/// admin_catalogue on the phone: the same search (product name, variant name or SKU contain the text), filters, sort
/// (ties: product name, variant name, id) and totals over every matching row.
({List<CatalogueRow> rows, CatalogueSummary summary}) cataloguePage(List<CatalogueRow> all, CatalogueView v,
    {required int offset, required int limit}) {
  final q = v.query.trim().toLowerCase();
  final match = all.where((r) =>
      (q.isEmpty || '${r.productName} ${r.variantName} ${r.sku}'.toLowerCase().contains(q)) &&
      (v.categoryId == null || r.categoryId == v.categoryId) &&
      (v.brandId == null || r.brandId == v.brandId) &&
      switch (v.stock) {
        StockFilter.all => true,
        StockFilter.low => r.stock >= 1 && r.stock <= lowStockMax,
        StockFilter.out => r.stock == 0,
      } &&
      switch (v.visibility) {
        VisibilityFilter.all => true,
        VisibilityFilter.shown => r.visible,
        VisibilityFilter.hidden => !r.visible,
      }).toList()
    ..sort((a, b) {
      final by = switch (v.sort) {
        CatalogueSort.stock => a.stock.compareTo(b.stock),
        CatalogueSort.price => a.pricePaise.compareTo(b.pricePaise),
        CatalogueSort.updated => b.updatedAt.compareTo(a.updatedAt),
        CatalogueSort.name => 0,
      };
      if (by != 0) return by;
      final name = a.productName.toLowerCase().compareTo(b.productName.toLowerCase());
      if (name != 0) return name;
      final variant = a.variantName.toLowerCase().compareTo(b.variantName.toLowerCase());
      return variant != 0 ? variant : a.variantId.compareTo(b.variantId);
    });
  int sum(int Function(CatalogueRow) f) => match.fold(0, (n, r) => n + f(r));
  return (
    rows: match.skip(offset).take(limit).toList(),
    summary: (
      skus: match.length,
      units: sum((r) => r.stock),
      valueAtPricePaise: sum((r) => r.pricePaise * r.stock),
      valueAtMrpPaise: sum((r) => r.mrpPaise * r.stock),
      low: match.where((r) => r.stock >= 1 && r.stock <= lowStockMax).length,
      out: match.where((r) => r.stock == 0).length,
      total: all.length,
    ),
  );
}

/// The edit form's fields (today's column names) as the saveProduct / saveVariant contracts.
Map<String, Object?> productInput(String? id, Map<String, Object?> f) => {
      'id': id,
      'slug': id ?? f['slug'],
      'name': f['name'],
      'brandId': f['brand_id'],
      'categoryId': f['category_id'],
      'description': f['description'] ?? '',
      'specs': f['specs'] ?? const [],
      'gstRateBp': ((f['gst_rate'] as num? ?? 18) * 100).round(),
      'isActive': f['is_active'],
      'isFeatured': f['is_featured'],
    };

Map<String, Object?> variantInput(String productId, String? id, Map<String, Object?> f) {
  final attributes = Map<String, Object?>.from(f['attributes'] as Map? ?? const {});
  if (attributes.remove('color_hex') case final hex?) attributes['colorHex'] = hex;
  return {
    'productId': productId,
    'id': id,
    'sku': f['sku'],
    'name': f['name'],
    'attributes': attributes,
    'pricePaise': f['price_paise'],
    'mrpPaise': f['mrp_paise'],
    'stock': f['stock'],
    'isActive': f['is_active'],
    'sort': ?f['sort'],
  };
}

/// Staff on Firebase: reads from catalogIndex/staff and the product docs (staff Rules), writes through the catalog
/// callables (functions/src/catalog/contract.ts), brands as plain staff docs.
class FirebaseCatalogAdminRepository implements CatalogAdminRepository {
  FirebaseCatalogAdminRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  /// One read per screen visit: the index is re-read each time (staff want the latest stock), never streamed.
  Future<IndexCards> _staff() async => indexCards((await _db.doc('catalogIndex/staff').get()).data());

  Future<Map<String, dynamic>> _call(String name, Map<String, Object?> data) => callFunction(_functions, name, data);

  @override
  Future<({List<CatalogueRow> rows, CatalogueSummary summary})> catalogue(CatalogueView view,
          {required int offset, required int limit}) async =>
      cataloguePage(staffRows(await _staff()), view, offset: offset, limit: limit);

  @override
  Future<List<String>> updateVariants(List<VariantEdit> edits) async {
    final res = await _call('updateVariants', {
      'edits': [
        for (final e in edits)
          {
            'variantId': e.variantId,
            'expect': {'stock': ?e.expectStock, 'pricePaise': ?e.expectPricePaise},
            'stock': ?e.stock,
            'pricePaise': ?e.pricePaise,
            'mrpPaise': ?e.mrpPaise,
            'isActive': ?e.isActive,
          }
      ],
    });
    return [...(res['stale'] as List).cast<String>()];
  }

  @override
  Future<void> setFeatured(List<String> productIds, bool featured) =>
      _call('setFeatured', {'productIds': productIds, 'featured': featured});

  @override
  Future<List<AdminProductRow>> products() async {
    final (cards, categories) = await (_staff(), _db.collection('categories').get()).wait;
    final categoryName = {for (final d in categories.docs) d.id: d['name'] as String};
    final rows = [
      for (final MapEntry(key: id, value: c) in cards.entries)
        () {
          final active = [for (final v in (c['variants'] as List? ?? const []).cast<Map>()) if (v['a'] == true) v];
          return AdminProductRow(
            id: id,
            slug: id,
            name: c['n'] as String,
            brandName: c['bn'] as String,
            categoryName: categoryName[c['c']] ?? '',
            isActive: c['active'] == true,
            isFeatured: c['f'] == true,
            coverPath: c['cv'] as String?,
            activeVariants: active.length,
            stock: active.fold(0, (n, v) => n + (v['st'] as num).toInt()),
            lowStock: c['active'] == true && active.any((v) => (v['st'] as num) <= lowStockMax),
          );
        }(),
    ]..sort((a, b) => a.name != b.name ? a.name.compareTo(b.name) : a.id.compareTo(b.id));
    return rows;
  }

  @override
  Future<Product> product(String id) async {
    final (doc, variants) =
        await (_db.doc('products/$id').get(), _db.collection('variants').where('productId', isEqualTo: id).orderBy('sort').get()).wait;
    final d = doc.data() ?? (throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found'));
    final category = await _db.doc('categories/${d['categoryId']}').get();
    return productFromDoc(id, d,
        categoryName: category.data()?['name'] as String? ?? '',
        variants: [for (final v in variants.docs) variantFromDoc(v.id, v.data())]);
  }

  @override
  Future<String> saveProduct(String? id, Map<String, Object?> fields) async =>
      (await _call('saveProduct', productInput(id, fields)))['id'] as String;

  @override
  Future<void> saveVariant(String productId, String? variantId, Map<String, Object?> fields) =>
      _call('saveVariant', variantInput(productId, variantId, fields));

  @override
  Future<void> setProductImages(String productId, List<ProductPhoto> images) => _call('setProductImages', {
        'productId': productId,
        'images': [
          for (final i in images) {'path': i.path, 'color': ?i.color, 'sort': i.sort}
        ],
      });

  @override
  Future<void> deleteProduct(String id) => _call('deleteProduct', {'id': id});

  /// brands/{slug} under staff Rules; an existing slug is that brand.
  @override
  Future<Brand> createBrand(String name) async {
    final slug = slugify(name);
    final ref = _db.doc('brands/$slug');
    final existing = await ref.get();
    if (existing.data() case final d?) return Brand(id: slug, slug: slug, name: d['name'] as String);
    await ref.set({'name': name, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
    return Brand(id: slug, slug: slug, name: name);
  }
}
