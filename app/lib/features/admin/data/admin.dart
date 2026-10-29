import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../catalog/data/catalog.dart' show brandsProvider;
import 'rules.dart';
import '../../repairs/data/repairs.dart';

// Reads rely on RLS: admins can select every row (incl. inactive products) via the "admin write" policies.

SupabaseClient _db(WidgetRef ref) => ref.read(supabaseProvider);

// Dashboard -------------------------------------------------------------------

/// `admin_dashboard()`: orders_today, revenue_today_paise, open_orders, low_stock, open_repairs, needs_refund (all ints).
final adminDashboardProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final json = await ref.watch(supabaseProvider).rpc('admin_dashboard') as Map;
  return {for (final e in json.entries) e.key as String: (e.value as num).toInt()};
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

// shortcut: newest 100 only, no paging; add range() paging when a filter regularly passes 100.
final adminOrdersProvider = FutureProvider.autoDispose.family<List<Order>, String>((ref, filter) async {
  var q = ref.watch(supabaseProvider).from('orders').select('*, items:order_items(*)');
  q = switch (filter) {
    'all' => q,
    'open' => q.inFilter('status', ['confirmed', 'packed', 'shipped']),
    'needs_refund' => q.eq('status', 'cancelled').eq('payment_status', 'paid'),
    _ => q.eq('status', filter),
  };
  final rows = await q.order('created_at', ascending: false).limit(100);
  return [for (final r in rows) Order.fromJson(r)];
});

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
  await _db(ref).rpc('admin_update_order', params: {
    'p_order_id': orderId,
    'p_status': status.value,
    'p_note': note,
    'p_courier': courier,
    'p_tracking_number': tracking,
  });
  _ordersChanged(ref, orderId);
}

Future<void> setImeis(WidgetRef ref, String orderId, String itemId, List<String> imeis) async {
  await _db(ref).rpc('admin_set_imeis', params: {'p_order_item_id': itemId, 'p_imeis': imeis});
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
  });

  final String id;
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

final adminProductsProvider = FutureProvider.autoDispose<List<AdminProductRow>>((ref) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('products')
      .select(
        'id, name, is_active, is_featured, brand:brands(name), category:categories(name), '
        'images:product_images(path, sort), variants(stock, is_active)',
      )
      .order('name');
  return [for (final r in rows) AdminProductRow.fromJson(r)];
});

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

/// The bucket accepts JPEG, PNG and WebP; read the real type from the file's first bytes.
(String ext, String mime)? imageTypeOf(Uint8List b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return ('jpg', 'image/jpeg');
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return ('png', 'image/png');
  if (b.length > 12 && String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' && String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
    return ('webp', 'image/webp');
  }
  return null;
}

/// Uploads to `<productId>/<millis>.<ext>`, then adds the product_images row (removing the file if that fails).
Future<void> addProductImage(WidgetRef ref, String productId, Uint8List bytes, int sort) async {
  final type = imageTypeOf(bytes);
  if (type == null) throw const FormatException('Use a JPEG, PNG or WebP photo.');
  final db = _db(ref);
  final bucket = db.storage.from('product-images');
  final path = '$productId/${DateTime.now().millisecondsSinceEpoch}.${type.$1}';
  await bucket.uploadBinary(path, bytes, fileOptions: FileOptions(contentType: type.$2));
  try {
    await db.from('product_images').insert({'product_id': productId, 'path': path, 'sort': sort});
  } catch (_) {
    try {
      await bucket.remove([path]);
    } catch (_) {} // best effort; the row error below is what matters
    rethrow;
  }
  _productChanged(ref, productId);
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

/// Uploads to `store/<millis>.<ext>`, then appends it to [current] (removing the file if that fails).
Future<void> addStorePhoto(WidgetRef ref, List<String> current, Uint8List bytes) async {
  final type = imageTypeOf(bytes);
  if (type == null) throw const FormatException('Use a JPEG, PNG or WebP photo.');
  final bucket = _db(ref).storage.from('product-images');
  final path = 'store/${DateTime.now().millisecondsSinceEpoch}.${type.$1}';
  await bucket.uploadBinary(path, bytes, fileOptions: FileOptions(contentType: type.$2));
  try {
    await saveStorePhotos(ref, [...current, path]);
  } catch (_) {
    try {
      await bucket.remove([path]);
    } catch (_) {} // best effort; the save error below is what matters
    rethrow;
  }
}

/// Unlike product photos, no order points at shop photos, so the file is deleted too.
Future<void> removeStorePhoto(WidgetRef ref, List<String> current, String path) async {
  await saveStorePhotos(ref, [...current]..remove(path));
  try {
    await _db(ref).storage.from('product-images').remove([path]);
  } catch (_) {} // best effort: an orphaned file is harmless
}
