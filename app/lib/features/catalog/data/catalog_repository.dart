import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart' show firestoreProvider;
import '../../../core/models/models.dart';
import '../../../core/supabase.dart' show supabaseProvider;
import 'catalog.dart' show HomeData, SearchParams;
import 'catalog_repository_firebase.dart';
import 'catalog_repository_supabase.dart';

/// What customers browse: categories, brands, the home rails, product pages and search (docs/FIREBASE.md D3: on
/// Firebase all card reads come from catalogIndex/public, searched on the phone). Owner: engineer B.
abstract interface class CatalogRepository {
  Future<List<Category>> categories();

  Future<List<Brand>> brands();

  /// Categories, featured products (phones first) and Home's "Deals under ₹1,500" rail.
  Future<HomeData> home();

  /// Null when the slug doesn't exist or the product is hidden.
  Future<Product?> product(String slug);

  /// One page of search results and the total match count, in-stock rows first, ending on id for stable paging.
  Future<({List<ProductCard> items, int total})> search(SearchParams params, {required int offset, required int limit});

  /// Cards for these product ids (hidden products drop out), in no particular order.
  Future<List<ProductCard>> cards(List<String> ids);

  /// Accessories whose "Fits" spec names one of [names], in stock first.
  Future<List<ProductCard>> fits(Set<String> names);

  /// Products in [categorySlug] priced nearest [pricePaise], [excludeId] left out.
  Future<List<ProductCard>> similar(String categorySlug, int pricePaise, String excludeId);

  /// The newest products (Home's "More to explore").
  Future<List<ProductCard>> latest();

  /// Purchasable variants by id (reorder puts a past order back in the cart).
  Future<List<Variant>> variants(List<String> ids);
}

/// The DI seam: Supabase or Firebase by `backend`; tests use test/fakes/fake_catalog_repository.dart.
final catalogRepositoryProvider = Provider<CatalogRepository>((ref) => backend == Backend.firebase
    ? FirebaseCatalogRepository(ref.watch(firestoreProvider))
    : SupabaseCatalogRepository(ref.watch(supabaseProvider)));
