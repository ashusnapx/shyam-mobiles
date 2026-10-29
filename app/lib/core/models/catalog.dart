enum CategoryKind { phone, accessory }

class Category {
  const Category({required this.id, required this.slug, required this.name, required this.kind, this.sort = 0});

  final String id;
  final String slug;
  final String name;
  final CategoryKind kind;
  final int sort;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'],
        slug: j['slug'],
        name: j['name'],
        kind: CategoryKind.values.byName(j['kind']),
        sort: j['sort'] ?? 0,
      );
}

class Brand {
  const Brand({required this.id, required this.slug, required this.name});

  final String id;
  final String slug;
  final String name;

  factory Brand.fromJson(Map<String, dynamic> j) => Brand(id: j['id'], slug: j['slug'], name: j['name']);
}

/// Row of the `product_cards` view: everything a listing tile needs.
class ProductCard {
  const ProductCard({
    required this.id,
    required this.slug,
    required this.name,
    required this.brandName,
    required this.categorySlug,
    required this.minPricePaise,
    required this.mrpPaise,
    required this.inStock,
    this.coverPath,
    this.isFeatured = false,
  });

  final String id;
  final String slug;
  final String name;
  final String brandName;
  final String categorySlug;
  final int minPricePaise;
  final int mrpPaise;
  final bool inStock;
  final String? coverPath;
  final bool isFeatured;

  factory ProductCard.fromJson(Map<String, dynamic> j) => ProductCard(
        id: j['id'],
        slug: j['slug'],
        name: j['name'],
        brandName: j['brand_name'],
        categorySlug: j['category_slug'],
        minPricePaise: j['min_price_paise'],
        mrpPaise: j['mrp_paise'],
        inStock: j['in_stock'],
        coverPath: j['cover_path'],
        isFeatured: j['is_featured'] ?? false,
      );
}

class ProductPhoto {
  const ProductPhoto({required this.id, required this.path, this.sort = 0});

  final String id;
  final String path;
  final int sort;

  factory ProductPhoto.fromJson(Map<String, dynamic> j) =>
      ProductPhoto(id: j['id'], path: j['path'], sort: j['sort'] ?? 0);
}

class Spec {
  const Spec(this.label, this.value);

  final String label;
  final String value;

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

class Variant {
  const Variant({
    required this.id,
    required this.productId,
    required this.sku,
    required this.name,
    required this.pricePaise,
    required this.mrpPaise,
    required this.stock,
    this.attributes = const {},
    this.isActive = true,
    this.sort = 0,
  });

  final String id;
  final String productId;
  final String sku;
  final String name;
  final Map<String, dynamic> attributes;
  final int pricePaise;
  final int mrpPaise;
  final int stock;
  final bool isActive;
  final int sort;

  String? get ram => attributes['ram'];
  String? get storage => attributes['storage'];
  String? get color => attributes['color'];
  String? get colorHex => attributes['color_hex'];
  bool get inStock => isActive && stock > 0;

  factory Variant.fromJson(Map<String, dynamic> j) => Variant(
        id: j['id'],
        productId: j['product_id'],
        sku: j['sku'],
        name: j['name'],
        attributes: Map<String, dynamic>.from(j['attributes'] ?? const {}),
        pricePaise: j['price_paise'],
        mrpPaise: j['mrp_paise'],
        stock: j['stock'],
        isActive: j['is_active'] ?? true,
        sort: j['sort'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'sku': sku,
        'name': name,
        'attributes': attributes,
        'price_paise': pricePaise,
        'mrp_paise': mrpPaise,
        'stock': stock,
        'is_active': isActive,
        'sort': sort,
      };
}

/// Full product, as loaded by
/// `products.select('*, brand:brands(*), category:categories(*), images:product_images(*), variants(*)')`.
class Product {
  const Product({
    required this.id,
    required this.slug,
    required this.name,
    required this.brand,
    required this.category,
    this.description = '',
    this.specs = const [],
    this.gstRate = 18,
    this.isActive = true,
    this.isFeatured = false,
    this.images = const [],
    this.variants = const [],
  });

  final String id;
  final String slug;
  final String name;
  final Brand brand;
  final Category category;
  final String description;
  final List<Spec> specs;
  final num gstRate;
  final bool isActive;
  final bool isFeatured;
  final List<ProductPhoto> images; // sorted by sort
  final List<Variant> variants; // sorted by sort

  List<Variant> get activeVariants => variants.where((v) => v.isActive).toList();

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'],
        slug: j['slug'],
        name: j['name'],
        brand: Brand.fromJson(j['brand']),
        category: Category.fromJson(j['category']),
        description: j['description'] ?? '',
        specs: [for (final s in (j['specs'] as List? ?? const [])) Spec(s['label'], s['value'])],
        gstRate: j['gst_rate'] ?? 18,
        isActive: j['is_active'] ?? true,
        isFeatured: j['is_featured'] ?? false,
        images: [for (final i in (j['images'] as List? ?? const [])) ProductPhoto.fromJson(i)]
          ..sort((a, b) => a.sort.compareTo(b.sort)),
        variants: [for (final v in (j['variants'] as List? ?? const [])) Variant.fromJson(v)]
          ..sort((a, b) => a.sort.compareTo(b.sort)),
      );
}
