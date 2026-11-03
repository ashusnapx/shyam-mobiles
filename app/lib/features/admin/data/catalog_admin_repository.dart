import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart' show firestoreProvider, functionsProvider;
import '../../../core/models/models.dart';
import '../../../core/supabase.dart' show supabaseProvider;
import 'admin.dart' show AdminProductRow;
import 'catalog_admin_repository_firebase.dart';
import 'catalog_admin_repository_supabase.dart';
import 'catalogue.dart' show CatalogueRow, CatalogueSummary, CatalogueView;

/// One staff catalogue edit: the new values, guarded by the value the screen showed ([expectStock] /
/// [expectPricePaise]). Firebase: the updateVariants callable.
typedef VariantEdit = ({
  String variantId,
  int? expectStock,
  int? expectPricePaise,
  int? stock,
  int? pricePaise,
  int? mrpPaise,
  bool? isActive,
});

/// Staff writes to the catalogue (docs/FIREBASE.md §1 row B: saveProduct, saveVariant, setProductImages,
/// updateVariants, setFeatured, deleteProduct). Customers never write products or variants. Owner: engineer B.
abstract interface class CatalogAdminRepository {
  /// A page of the staff catalogue for [view], with the totals.
  Future<({List<CatalogueRow> rows, CatalogueSummary summary})> catalogue(CatalogueView view, {required int offset, required int limit});

  /// Edits applied one by one; returns the variant ids skipped because their row changed meanwhile (stale).
  Future<List<String>> updateVariants(List<VariantEdit> edits);

  Future<void> setFeatured(List<String> productIds, bool featured);

  /// Every product, hidden ones too, by name.
  Future<List<AdminProductRow>> products();

  /// A product with its variants and photos, hidden or not.
  Future<Product> product(String id);

  /// Creates when [id] is null. [fields] are the edit form's values (name, brand, category, description, specs,
  /// active, featured). Returns the product id.
  Future<String> saveProduct(String? id, Map<String, Object?> fields);

  /// Creates when [variantId] is null.
  Future<void> saveVariant(String productId, String? variantId, Map<String, Object?> fields);

  /// The product's whole photo list, in order. Files are uploaded first with PhotoStore.
  Future<void> setProductImages(String productId, List<ProductPhoto> images);

  /// Refused once any order references the product: hide it instead.
  Future<void> deleteProduct(String id);

  /// Finds or creates the brand named [name].
  Future<Brand> createBrand(String name);
}

final catalogAdminRepositoryProvider = Provider<CatalogAdminRepository>((ref) => backend == Backend.firebase
    ? FirebaseCatalogAdminRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider))
    : SupabaseCatalogAdminRepository(ref.watch(supabaseProvider)));
