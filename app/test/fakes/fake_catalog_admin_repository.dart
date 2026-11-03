import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/admin.dart' show AdminProductRow;
import 'package:shyam_mobiles/features/admin/data/catalog_admin_repository.dart';
import 'package:shyam_mobiles/features/admin/data/catalogue.dart' show CatalogueRow, CatalogueSummary, CatalogueView;

import 'fake.dart';

/// Seed [rows], [productRows] and [productsById]. [staleIds]: edits to these variants come back stale.
class FakeCatalogAdminRepository with Fake implements CatalogAdminRepository {
  var rows = <CatalogueRow>[];
  var productRows = <AdminProductRow>[];
  final productsById = <String, Product>{};
  final savedProducts = <String, Map<String, Object?>>{};
  final images = <String, List<ProductPhoto>>{};
  final staleIds = <String>{};
  final edits = <VariantEdit>[];
  var _next = 0;

  @override
  Future<({List<CatalogueRow> rows, CatalogueSummary summary})> catalogue(CatalogueView view,
      {required int offset, required int limit}) async {
    record('catalogue ${view.query}');
    final units = rows.fold<int>(0, (n, r) => n + r.stock);
    return (
      rows: pageOf(rows, offset, limit),
      summary: (
        skus: rows.length,
        units: units,
        valueAtPricePaise: rows.fold<int>(0, (n, r) => n + r.stock * r.pricePaise),
        valueAtMrpPaise: rows.fold<int>(0, (n, r) => n + r.stock * r.mrpPaise),
        low: rows.where((r) => r.stock > 0 && r.stock <= 3).length,
        out: rows.where((r) => r.stock == 0).length,
        total: rows.length,
      ),
    );
  }

  @override
  Future<List<String>> updateVariants(List<VariantEdit> edits) async {
    record('updateVariants ${edits.length}');
    this.edits.addAll(edits.where((e) => !staleIds.contains(e.variantId)));
    return [for (final e in edits) if (staleIds.contains(e.variantId)) e.variantId];
  }

  @override
  Future<void> setFeatured(List<String> productIds, bool featured) async => record('setFeatured ${productIds.join(',')} $featured');

  @override
  Future<List<AdminProductRow>> products() async {
    record('products');
    return productRows;
  }

  @override
  Future<Product> product(String id) async {
    record('product $id');
    return productsById[id] ?? (throw reason('NOT_FOUND'));
  }

  @override
  Future<String> saveProduct(String? id, Map<String, Object?> fields) async {
    record('saveProduct ${id ?? 'new'}');
    final saved = id ?? 'p${_next++}';
    savedProducts[saved] = {...?savedProducts[saved], ...fields};
    return saved;
  }

  @override
  Future<void> saveVariant(String productId, String? variantId, Map<String, Object?> fields) async =>
      record('saveVariant $productId ${variantId ?? 'new'}');

  @override
  Future<void> setProductImages(String productId, List<ProductPhoto> images) async {
    record('setProductImages $productId ${images.length}');
    this.images[productId] = [...images];
  }

  @override
  Future<void> deleteProduct(String id) async => record('deleteProduct $id');

  @override
  Future<Brand> createBrand(String name) async {
    record('createBrand $name');
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return Brand(id: slug, slug: slug, name: name);
  }
}
