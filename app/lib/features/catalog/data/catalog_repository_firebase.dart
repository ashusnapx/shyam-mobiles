import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/models.dart';
import 'catalog.dart' show HomeData, SearchParams;
import 'catalog_index.dart';
import 'catalog_repository.dart';
import 'rails.dart' show closestByPrice, railSize;

/// Firestore docs (functions/src/model/catalog.ts) as the app's models.
Category categoryFromDoc(String id, Map<String, dynamic> d) => Category(
    id: id, slug: id, name: d['name'] as String, kind: CategoryKind.values.byName(d['kind'] as String), sort: (d['sort'] as num?)?.toInt() ?? 0);

Variant variantFromDoc(String id, Map<String, dynamic> d) {
  final attributes = Map<String, dynamic>.from((d['attributes'] as Map?) ?? const {});
  if (attributes.remove('colorHex') case final hex?) attributes['color_hex'] = hex; // the model's key
  return Variant(
    id: id,
    productId: d['productId'] as String,
    sku: d['sku'] as String,
    name: d['name'] as String,
    attributes: attributes,
    pricePaise: (d['pricePaise'] as num).toInt(),
    mrpPaise: (d['mrpPaise'] as num).toInt(),
    stock: (d['stock'] as num).toInt(),
    isActive: d['isActive'] == true,
    sort: (d['sort'] as num?)?.toInt() ?? 0,
  );
}

/// The photo's key doubles as its id (unique within a product; setProductImages sends the whole list).
Product productFromDoc(String id, Map<String, dynamic> d, {required String categoryName, required List<Variant> variants}) =>
    Product(
      id: id,
      slug: id,
      name: d['name'] as String,
      brand: Brand(id: d['brandId'] as String, slug: d['brandId'] as String, name: d['brandName'] as String),
      category: Category(
          id: d['categoryId'] as String,
          slug: d['categoryId'] as String,
          name: categoryName,
          kind: CategoryKind.values.byName(d['categoryKind'] as String)),
      description: d['description'] as String? ?? '',
      specs: [for (final s in (d['specs'] as List? ?? const [])) Spec(s['label'] as String, s['value'] as String)],
      gstRate: ((d['gstRateBp'] as num?) ?? 1800) / 100,
      isActive: d['isActive'] == true,
      isFeatured: d['isFeatured'] == true,
      images: [
        for (final i in (d['images'] as List? ?? const []))
          ProductPhoto(id: i['path'] as String, path: i['path'] as String, sort: (i['sort'] as num).toInt(), color: i['color'] as String?)
      ]..sort((a, b) => a.sort.compareTo(b.sort)),
      variants: [...variants]..sort((a, b) => a.sort.compareTo(b.sort)),
    );

/// A read the Rules refused: a hidden product or variant, which customers see as missing.
bool isDenied(Object e) => e is FirebaseException && e.code == 'permission-denied';

/// Customers' reads on Firebase: every card comes from catalogIndex/public, searched on the phone; product pages read
/// the product, its shown variants and its category.
class FirebaseCatalogRepository implements CatalogRepository {
  FirebaseCatalogRepository(this._db);

  final FirebaseFirestore _db;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Completer<void>? _first;
  IndexCards _cards = const {};

  /// The index, kept current by one listener (Firestore downloads it again only when it changes; offline, the
  /// on-device copy). A failed first load is retried on the next call.
  Future<IndexCards> _index() async {
    if (_first == null) {
      final first = _first = Completer<void>();
      _sub = _db.doc('catalogIndex/public').snapshots().listen((s) {
        _cards = indexCards(s.data());
        if (!first.isCompleted) first.complete();
      }, onError: (Object e) {
        if (first.isCompleted) return;
        first.completeError(e);
        _sub?.cancel();
        _first = null;
      });
    }
    await _first!.future;
    return _cards;
  }

  @override
  Future<List<Category>> categories() async =>
      [for (final d in (await _db.collection('categories').orderBy('sort').get()).docs) categoryFromDoc(d.id, d.data())];

  @override
  Future<List<Brand>> brands() async => [
        for (final d in (await _db.collection('brands').orderBy('name').get()).docs)
          Brand(id: d.id, slug: d.id, name: d['name'] as String)
      ];

  @override
  Future<HomeData> home() async {
    final (categories, cards) = await (this.categories(), _index()).wait;
    final h = homeCards(cards);
    return (categories: categories, featured: h.featured, accessories: h.accessories);
  }

  @override
  Future<Product?> product(String slug) async {
    try {
      final doc = await _db.doc('products/$slug').get();
      final d = doc.data();
      if (d == null) return null;
      final (category, variants) = await (
        _db.doc('categories/${d['categoryId']}').get(),
        // Rules let customers list only shown variants, so the query says so
        _db
            .collection('variants')
            .where('productId', isEqualTo: slug)
            .where('isActive', isEqualTo: true)
            .where('productActive', isEqualTo: true)
            .orderBy('sort')
            .get(),
      ).wait;
      return productFromDoc(slug, d,
          categoryName: category.data()?['name'] as String? ?? '',
          variants: [for (final v in variants.docs) variantFromDoc(v.id, v.data())]);
    } on FirebaseException catch (e) {
      if (isDenied(e)) return null; // hidden
      rethrow;
    }
  }

  @override
  Future<({List<ProductCard> items, int total})> search(SearchParams params, {required int offset, required int limit}) async {
    final hits = searchCards(await _index(), params);
    return (items: hits.skip(offset).take(limit).toList(), total: hits.length);
  }

  @override
  Future<List<ProductCard>> cards(List<String> ids) async {
    final cards = await _index();
    return [for (final id in ids) if (cards[id] case final c?) cardOf(id, c)];
  }

  @override
  Future<List<ProductCard>> fits(Set<String> names) async => fitsCards(await _index(), names, railSize);

  @override
  Future<List<ProductCard>> similar(String categorySlug, int pricePaise, String excludeId) async {
    final cards = await _index();
    return closestByPrice([
      for (final MapEntry(:key, :value) in cards.entries)
        if (value['c'] == categorySlug && key != excludeId) cardOf(key, value)
    ], pricePaise);
  }

  @override
  Future<List<ProductCard>> latest() async => latestCards(await _index());

  @override
  Future<List<Variant>> variants(List<String> ids) async {
    final found = await Future.wait([
      for (final id in ids)
        _db.doc('variants/$id').get().then<Variant?>((s) {
          final d = s.data();
          return d == null || d['isActive'] != true ? null : variantFromDoc(s.id, d);
        }, onError: (Object e, StackTrace st) => isDenied(e) ? null : Error.throwWithStackTrace(e, st)),
    ]);
    return [...found.nonNulls];
  }
}
