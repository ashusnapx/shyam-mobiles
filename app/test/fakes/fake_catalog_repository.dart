import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart' show HomeData, SearchParams;
import 'package:shyam_mobiles/features/catalog/data/catalog_repository.dart';

import 'fake.dart';

/// Seed [productsBySlug] and [cardList]; search matches the query against card names, in-stock first.
class FakeCatalogRepository with Fake implements CatalogRepository {
  var categoryList = <Category>[];
  var brandList = <Brand>[];
  var cardList = <ProductCard>[];
  final productsBySlug = <String, Product>{};
  final variantsById = <String, Variant>{};

  @override
  Future<List<Category>> categories() async {
    record('categories');
    return categoryList;
  }

  @override
  Future<List<Brand>> brands() async {
    record('brands');
    return brandList;
  }

  @override
  Future<HomeData> home() async {
    record('home');
    return (
      categories: categoryList,
      featured: cardList.where((c) => c.isFeatured).take(10).toList(),
      accessories: cardList.where((c) => c.inStock && c.minPricePaise <= 150000).take(10).toList(),
    );
  }

  @override
  Future<Product?> product(String slug) async {
    record('product $slug');
    return productsBySlug[slug];
  }

  @override
  Future<({List<ProductCard> items, int total})> search(SearchParams params, {required int offset, required int limit}) async {
    record('search ${params.q}');
    final q = params.q.toLowerCase();
    final hits = cardList
        .where((c) => c.name.toLowerCase().contains(q))
        .where((c) => params.category == null || c.categorySlug == params.category)
        .where((c) => !params.inStock || c.inStock)
        .toList()
      ..sort((a, b) => (b.inStock ? 1 : 0) - (a.inStock ? 1 : 0));
    return (items: pageOf(hits, offset, limit), total: hits.length);
  }

  @override
  Future<List<ProductCard>> cards(List<String> ids) async {
    record('cards');
    return cardList.where((c) => ids.contains(c.id)).toList();
  }

  @override
  Future<List<ProductCard>> fits(Set<String> names) async {
    record('fits');
    return const [];
  }

  @override
  Future<List<ProductCard>> similar(String categorySlug, int pricePaise, String excludeId) async {
    record('similar $categorySlug');
    return cardList.where((c) => c.categorySlug == categorySlug && c.id != excludeId).take(8).toList();
  }

  @override
  Future<List<ProductCard>> latest() async {
    record('latest');
    return cardList.take(10).toList();
  }

  @override
  Future<List<Variant>> variants(List<String> ids) async {
    record('variants');
    return [for (final id in ids) ?variantsById[id]];
  }
}
