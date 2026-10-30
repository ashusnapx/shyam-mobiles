import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/paging.dart';
import '../../../core/supabase.dart';
import '../../catalog/data/catalog.dart' show brandsProvider;
import 'photos.dart';
import 'rules.dart';
import '../../repairs/data/repairs.dart';

// Reads rely on RLS: admins can select every row (incl. inactive products) via the "admin write" policies.

SupabaseClient _db(WidgetRef ref) => ref.read(supabaseProvider);

// Dashboard -------------------------------------------------------------------

/// `admin_dashboard()`: orders_today, revenue_today_paise, open_orders, low_stock, open_repairs, needs_refund (all ints).
final adminDashboardProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final json = await ref.watch(supabaseProvider).rpc<Map<String, dynamic>>('admin_dashboard');
  return {for (final e in json.entries) e.key: (e.value as num).toInt()};
});

typedef NeedsAction = ({List<Order> orders, List<RepairBooking> repairs});

/// Confirmed orders to pack, packed orders to ship, requested repairs to confirm. Oldest first.
final needsActionProvider = FutureProvider.autoDispose<NeedsAction>((ref) async {
  final db = ref.watch(supabaseProvider);
  final (orders, repairs) = await (
    db
        .from('orders')
        .select('*, items:order_items(*)')
        .inFilter('status', ['confirmed', 'packed'])
        .order('created_at')
        .limit(30),
    db.from('repair_bookings').select().eq('status', 'requested').order('preferred_date').order('slot').limit(30),
  ).wait;
  final list = [for (final r in orders) Order.fromJson(r)];
  // packing comes before shipping
  list.sort((a, b) => a.status.index.compareTo(b.status.index));
  return (orders: list, repairs: [for (final r in repairs) RepairBooking.fromJson(r)]);
});

// Orders ----------------------------------------------------------------------

/// Filter keys for `/admin/orders?status=`: a status value, or `all`, `open`, `needs_refund`.
final orderFilters = {
  'all': 'All',
  'open': 'Open',
  for (final s in OrderStatus.values) s.value: s.label,
  'needs_refund': 'Needs refund',
};

/// Newest first, a page at a time.
final adminOrdersProvider =
    AsyncNotifierProvider.autoDispose.family<AdminOrdersNotifier, Paged<Order>, String>(AdminOrdersNotifier.new);

class AdminOrdersNotifier extends PagedNotifier<Order> {
  AdminOrdersNotifier(this.filter);

  final String filter;

  @override
  Object idOf(Order o) => o.id;

  @override
  Future<List<Order>> fetch(int from, int size) async {
    var q = ref.read(supabaseProvider).from('orders').select('*, items:order_items(*)');
    q = switch (filter) {
      'all' => q,
      'open' => q.inFilter('status', ['confirmed', 'packed', 'shipped']),
      'needs_refund' => q.eq('status', 'cancelled').eq('payment_status', 'paid'),
      _ => q.eq('status', filter),
    };
    // id breaks created_at ties, so no order repeats or goes missing between pages
    final rows = await q.order('created_at', ascending: false).order('id').range(from, from + size - 1);
    return [for (final r in rows) Order.fromJson(r)];
  }
}

final adminOrderProvider = FutureProvider.autoDispose.family<Order, String>((ref, id) async {
  final row = await ref
      .watch(supabaseProvider)
      .from('orders')
      .select('*, items:order_items(*), events:order_events(*)')
      .eq('id', id)
      .single();
  return Order.fromJson(row);
});

void _ordersChanged(WidgetRef ref, String orderId) {
  ref.invalidate(adminOrderProvider(orderId));
  ref.invalidate(adminOrdersProvider);
  ref.invalidate(needsActionProvider);
  ref.invalidate(adminDashboardProvider);
}

/// `admin_update_order`. Passing the current status only edits courier/tracking (null keeps the old value) and adds [note].
Future<void> updateOrder(
  WidgetRef ref,
  String orderId,
  OrderStatus status, {
  String? note,
  String? courier,
  String? tracking,
}) async {
  await _db(ref).rpc<void>('admin_update_order', params: {
    'p_order_id': orderId,
    'p_status': status.value,
    'p_note': note,
    'p_courier': courier,
    'p_tracking_number': tracking,
  });
  _ordersChanged(ref, orderId);
}

Future<void> setImeis(WidgetRef ref, String orderId, String itemId, List<String> imeis) async {
  await _db(ref).rpc<void>('admin_set_imeis', params: {'p_order_item_id': itemId, 'p_imeis': imeis});
  ref.invalidate(adminOrderProvider(orderId));
}

// Repairs ---------------------------------------------------------------------

final repairFilters = {
  'open': 'Open',
  for (final s in RepairStatus.values) s.value: s.label,
  'all': 'All',
};

/// By preferred date: soonest first for open work, latest first for history.
final adminRepairsProvider = FutureProvider.autoDispose.family<List<RepairBooking>, String>((ref, filter) async {
  var q = ref.watch(supabaseProvider).from('repair_bookings').select();
  q = switch (filter) {
    'all' => q,
    'open' => q.inFilter('status', [for (final s in RepairStatus.values) if (s.isOpen) s.value]),
    _ => q.eq('status', filter),
  };
  final upcoming = filter == 'open' || (filter != 'all' && RepairStatus.parse(filter).isOpen);
  final rows = await q.order('preferred_date', ascending: upcoming).order('slot', ascending: upcoming).limit(200);
  return [for (final r in rows) RepairBooking.fromJson(r)];
});

/// Admins write repair_bookings directly (RLS "admin write").
Future<void> updateRepair(WidgetRef ref, String id, Map<String, dynamic> changes) async {
  await _db(ref).from('repair_bookings').update(changes).eq('id', id).select('id').single(); // errors if no row changed
  ref.invalidate(repairProvider(id));
  ref.invalidate(adminRepairsProvider);
  ref.invalidate(needsActionProvider);
  ref.invalidate(adminDashboardProvider);
  ref.invalidate(myRepairsProvider);
}

// Products --------------------------------------------------------------------

class AdminProductRow {
  const AdminProductRow({
    required this.id,
    required this.name,
    required this.brandName,
    required this.categoryName,
    required this.isActive,
    required this.isFeatured,
    required this.coverPath,
    required this.activeVariants,
    required this.stock,
    required this.lowStock,
    this.slug = '',
  });

  final String id;
  final String slug;
  final String name;
  final String brandName;
  final String categoryName;
  final bool isActive;
  final bool isFeatured;
  final String? coverPath;
  final int activeVariants;
  final int stock; // across active variants
  final bool lowStock; // same rule as admin_dashboard: active product, an active variant with stock <= 3

  factory AdminProductRow.fromJson(Map<String, dynamic> j) {
    final variants = [for (final v in j['variants'] as List) v as Map<String, dynamic>];
    final active = variants.where((v) => v['is_active'] == true).toList();
    final images = [...j['images'] as List]..sort((a, b) => (a['sort'] as int).compareTo(b['sort'] as int));
    return AdminProductRow(
      id: j['id'],
      slug: j['slug'] ?? '',
      name: j['name'],
      brandName: j['brand']['name'],
      categoryName: j['category']['name'],
      isActive: j['is_active'],
      isFeatured: j['is_featured'],
      coverPath: images.isEmpty ? null : images.first['path'],
      activeVariants: active.length,
      stock: active.fold(0, (sum, v) => sum + (v['stock'] as int)),
      lowStock: j['is_active'] == true && active.any((v) => (v['stock'] as int) <= 3),
    );
  }
}

const _productColumns = 'id, slug, name, is_active, is_featured, brand:brands(name), category:categories(name), '
    'images:product_images(path, sort), variants(stock, is_active)';

/// Every product, for the pickers in the offer, group and banner editors (they search the whole list).
/// shortcut: PostgREST's max_rows (1000) caps it; page the pickers through search if the shop passes 1000 products.
final adminProductsProvider = FutureProvider.autoDispose<List<AdminProductRow>>((ref) async {
  final rows = await ref.watch(supabaseProvider).from('products').select(_productColumns).order('name', ascending: true).order('id');
  return [for (final r in rows) AdminProductRow.fromJson(r)];
});

typedef ProductListView = ({String query, bool lowOnly});

/// The Products screen, a page at a time: name search and the low-stock filter run on the server.
final adminProductPagesProvider = AsyncNotifierProvider.autoDispose
    .family<AdminProductPages, Paged<AdminProductRow>, ProductListView>(AdminProductPages.new);

class AdminProductPages extends PagedNotifier<AdminProductRow> {
  AdminProductPages(this.view);

  final ProductListView view;

  @override
  Object idOf(AdminProductRow p) => p.id;

  @override
  Future<List<AdminProductRow>> fetch(int from, int size) async {
    // "low" embeds the variants a second time, inner-joined and filtered, so only products with a low active
    // variant come back while `variants` still lists them all for the stock count (admin_dashboard's rule)
    var q = ref
        .read(supabaseProvider)
        .from('products')
        .select(view.lowOnly ? '$_productColumns, low:variants!inner(id)' : _productColumns);
    if (view.query.isNotEmpty) q = q.ilike('name', '%${view.query}%');
    if (view.lowOnly) q = q.eq('is_active', true).eq('low.is_active', true).lte('low.stock', 3);
    final rows = await q.order('name', ascending: true).order('id').range(from, from + size - 1);
    return [for (final r in rows) AdminProductRow.fromJson(r)];
  }
}

final adminProductProvider = FutureProvider.autoDispose.family<Product, String>((ref, id) async {
  final row = await ref
      .watch(supabaseProvider)
      .from('products')
      .select('*, brand:brands(*), category:categories(*), images:product_images(*), variants(*)')
      .eq('id', id)
      .single();
  return Product.fromJson(row);
});

final adminBrandsProvider = FutureProvider.autoDispose<List<Brand>>((ref) async {
  final rows = await ref.watch(supabaseProvider).from('brands').select().order('name');
  return [for (final r in rows) Brand.fromJson(r)];
});

/// Staff add a brand from the product form's brand picker. An existing slug returns that brand instead.
Future<Brand> createBrand(WidgetRef ref, String name) async {
  final clean = brandDisplayName(name);
  final slug = slugify(clean);
  if (clean.isEmpty || clean.length > 40) throw const FormatException('Brand names are 1 to 40 characters.');
  if (slug.isEmpty) throw const FormatException('Use English letters or numbers in the brand name.');
  final db = _db(ref);
  Map<String, dynamic> row;
  try {
    row = await db.from('brands').insert({'slug': slug, 'name': clean}).select().single();
  } on PostgrestException catch (e) {
    if (e.code != '23505') rethrow; // already exists under another spelling: use it
    row = await db.from('brands').select().eq('slug', slug).single();
  }
  ref.invalidate(adminBrandsProvider);
  ref.invalidate(brandsProvider);
  return Brand.fromJson(row);
}

final adminCategoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) async {
  final rows = await ref.watch(supabaseProvider).from('categories').select().order('sort');
  return [for (final r in rows) Category.fromJson(r)];
});

void _productChanged(WidgetRef ref, String productId) {
  ref.invalidate(adminProductProvider(productId));
  ref.invalidate(adminProductsProvider);
  ref.invalidate(adminProductPagesProvider);
  ref.invalidate(adminDashboardProvider); // low stock
}

/// Inserts when [id] is null. Returns the product id.
Future<String> saveProduct(WidgetRef ref, String? id, Map<String, dynamic> fields) async {
  final products = _db(ref).from('products');
  final row = id == null
      ? await products.insert(fields).select('id').single()
      : await products.update(fields).eq('id', id).select('id').single();
  final saved = row['id'] as String;
  _productChanged(ref, saved);
  return saved;
}

/// Compresses [original] (photos.dart) and uploads `<folder>/<millis>.webp` plus `<folder>/<millis>@thumb.webp`.
/// Returns the full photo's key, the only one the DB stores, and the sizes for the "4.2 MB → 180 KB" message.
Future<({String path, int before, int after})> _uploadPhoto(StorageFileApi bucket, String folder, Uint8List original) async {
  final photo = await preparePhoto(original);
  final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.webp';
  // Keys are never reused (<millis>.webp), so phones may cache a photo for a year: one download per customer.
  const webp = FileOptions(contentType: 'image/webp', cacheControl: '31536000');
  await bucket.uploadBinary(path, photo.full, fileOptions: webp);
  try {
    await bucket.uploadBinary(thumbPathFor(path)!, photo.thumb, fileOptions: webp);
  } catch (_) {
    await _removeQuietly(bucket, [path]);
    rethrow;
  }
  return (path: path, before: photo.originalBytes, after: photo.full.length);
}

/// Best effort: an orphaned file is harmless; the error that caused the clean-up is what matters.
Future<void> _removeQuietly(StorageFileApi bucket, List<String> paths) async {
  try {
    await bucket.remove(paths);
  } catch (_) {}
}

/// Uploads the photo and its thumb, then adds the product_images row (removing the files if that fails).
Future<({int before, int after})> addProductImage(WidgetRef ref, String productId, Uint8List original, int sort) async {
  final db = _db(ref);
  final bucket = db.storage.from('product-images');
  final up = await _uploadPhoto(bucket, productId, original);
  try {
    await db.from('product_images').insert({'product_id': productId, 'path': up.path, 'sort': sort});
  } catch (_) {
    await _removeQuietly(bucket, [up.path, thumbPathFor(up.path)!]);
    rethrow;
  }
  _productChanged(ref, productId);
  return (before: up.before, after: up.after);
}

/// Removes the photo from the product but keeps the file: past orders still show it via `order_items.image_path`.
/// shortcut: files are never cleaned up (~200 KB each); add a sweep for unreferenced files if storage grows.
Future<void> deleteProductImage(WidgetRef ref, String productId, ProductPhoto image) async {
  final db = _db(ref);
  await db.from('product_images').delete().eq('id', image.id);
  _productChanged(ref, productId);
}

/// Writes sort = position for every image whose position changed.
Future<void> reorderImages(WidgetRef ref, String productId, List<ProductPhoto> ordered) async {
  final db = _db(ref);
  for (final (i, image) in ordered.indexed) {
    if (image.sort != i) await db.from('product_images').update({'sort': i}).eq('id', image.id);
  }
  _productChanged(ref, productId);
}

/// Inserts when [variantId] is null.
Future<void> saveVariant(WidgetRef ref, String productId, String? variantId, Map<String, dynamic> fields) async {
  final variants = _db(ref).from('variants');
  if (variantId == null) {
    await variants.insert({...fields, 'product_id': productId});
  } else {
    await variants.update(fields).eq('id', variantId).select('id').single();
  }
  _productChanged(ref, productId);
}

// Settings --------------------------------------------------------------------

Future<void> saveSettings(WidgetRef ref, StoreSettings settings) async {
  // store_photos has its own writers below; the form's copy may be stale
  await _db(ref).from('store_settings').update(settings.toJson()..remove('store_photos')).eq('id', true).select('id').single();
  ref.invalidate(storeSettingsProvider);
}

/// Saves the shop photo list (max 8) and waits for the reload, so the next edit starts from the saved list.
Future<void> saveStorePhotos(WidgetRef ref, List<String> paths) async {
  await _db(ref).from('store_settings').update({'store_photos': paths}).eq('id', true).select('id').single();
  ref.invalidate(storeSettingsProvider);
  try {
    await ref.read(storeSettingsProvider.future);
  } catch (_) {} // saved; the screen shows the reload error
}

/// Uploads the photo and its thumb to `store/`, then appends it to [current] (removing the files if that fails).
Future<({int before, int after})> addStorePhoto(WidgetRef ref, List<String> current, Uint8List original) async {
  final bucket = _db(ref).storage.from('product-images');
  final up = await _uploadPhoto(bucket, 'store', original);
  try {
    await saveStorePhotos(ref, [...current, up.path]);
  } catch (_) {
    await _removeQuietly(bucket, [up.path, thumbPathFor(up.path)!]);
    rethrow;
  }
  return (before: up.before, after: up.after);
}

/// Unlike product photos, no order points at shop photos, so the file and its thumb are deleted too.
Future<void> removeStorePhoto(WidgetRef ref, List<String> current, String path) async {
  await saveStorePhotos(ref, [...current]..remove(path));
  await _removeQuietly(_db(ref).storage.from('product-images'), [path, ?thumbPathFor(path)]);
}

// Banners ---------------------------------------------------------------------

/// Uploads a banner photo and its thumb to `banners/`; returns the key for `banners.image_path`.
Future<String> uploadBannerImage(WidgetRef ref, Uint8List original) async =>
    (await _uploadPhoto(_db(ref).storage.from('product-images'), 'banners', original)).path;

/// No order points at banner photos, so a replaced or removed one is deleted with its thumb.
Future<void> deleteBannerImage(WidgetRef ref, String path) =>
    _removeQuietly(_db(ref).storage.from('product-images'), [path, ?thumbPathFor(path)]);
