import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/paging.dart';
import '../../../core/supabase.dart';
import '../../orders/data/orders_repository.dart';
import '../../catalog/data/catalog.dart' show brandsProvider;
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/settings_repository.dart';
import 'catalog_admin_repository.dart';
import 'catalogue.dart' show catalogueSummaryProvider;
import 'photo_store.dart';
import 'photos.dart';
import 'rules.dart';
import '../../repairs/data/repairs.dart';
import '../../repairs/data/repairs_repository.dart';

// Reads rely on RLS: admins can select every row (incl. inactive products) via the "admin write" policies.


// Dashboard -------------------------------------------------------------------

/// `admin_dashboard()`: orders_today, revenue_today_paise, open_orders, low_stock, open_repairs, needs_refund (all ints).
final adminDashboardProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  return ref.watch(ordersRepositoryProvider).dashboard();
});

typedef NeedsAction = ({List<Order> orders, List<RepairBooking> repairs});

/// Confirmed orders to pack, packed orders to ship, requested repairs to confirm. Oldest first.
final needsActionProvider = FutureProvider.autoDispose<NeedsAction>((ref) async {
  final (list, repairs) = await (ref.watch(ordersRepositoryProvider).toFulfil(), ref.read(repairsRepositoryProvider).toConfirm()).wait;
  return (orders: list, repairs: repairs);
});

// Orders ----------------------------------------------------------------------

/// Filter keys for `/admin/orders?status=`: a status value, or `all`, `open`, `needs_refund`.
final orderFilters = {
  'all': 'All',
  'today': 'Today',
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
    return ref.read(ordersRepositoryProvider).adminOrders(filter, from, size);
  }
}

final adminOrderProvider = FutureProvider.autoDispose.family<Order, String>((ref, id) async {
  return ref.watch(ordersRepositoryProvider).order(id);
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
  await ref.read(ordersRepositoryProvider).updateOrder(orderId, status, note: note, courier: courier, tracking: tracking);
  _ordersChanged(ref, orderId);
}

Future<void> setImeis(WidgetRef ref, String orderId, String itemId, List<String> imeis) async {
  await ref.read(ordersRepositoryProvider).setImeis(orderId, itemId, imeis);
  ref.invalidate(adminOrderProvider(orderId));
}

// Repairs ---------------------------------------------------------------------

/// Filter keys for `/admin/repairs?status=`: a status value, or `open`, `awaiting_approval`, `all`.
final repairFilters = {
  'open': 'Open',
  'awaiting_approval': 'Awaiting approval',
  for (final s in RepairStatus.values) s.value: s.label,
  'all': 'All',
};

/// By preferred date, a page at a time: soonest first for open work, latest first for history.
final adminRepairsProvider = AsyncNotifierProvider.autoDispose
    .family<AdminRepairsNotifier, Paged<RepairBooking>, String>(AdminRepairsNotifier.new);

class AdminRepairsNotifier extends PagedNotifier<RepairBooking> {
  AdminRepairsNotifier(this.filter);

  final String filter;

  @override
  Object idOf(RepairBooking b) => b.id;

  @override
  Future<List<RepairBooking>> fetch(int from, int size) async {
    return ref.read(repairsRepositoryProvider).adminRepairs(filter, from, size);
  }
}

void _repairsChanged(WidgetRef ref, String id) {
  ref.invalidate(repairProvider(id));
  ref.invalidate(adminRepairsProvider);
  ref.invalidate(needsActionProvider);
  ref.invalidate(adminDashboardProvider);
  ref.invalidate(myRepairsProvider);
}

/// `admin_update_repair`: one step forward or a cancel (rules.dart mirrors the steps); the current status only
/// adds [note] to the timeline.
Future<void> updateRepairStatus(WidgetRef ref, String id, RepairStatus status, {String? note}) async {
  await ref.read(repairsRepositoryProvider).updateStatus(id, status, note: note);
  _repairsChanged(ref, id);
}

/// `admin_set_repair_quote`: sends or changes the quote, which then waits for the customer; [approved] records a
/// yes given at the counter or on the phone.
Future<void> setRepairQuote(WidgetRef ref, String id, int paise, {String? note, bool approved = false}) async {
  await ref.read(repairsRepositoryProvider).setQuote(id, paise, note: note, approved: approved);
  _repairsChanged(ref, id);
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

/// Every product, for the pickers in the offer, group and banner editors (they search the whole list).
final adminProductsProvider =
    FutureProvider.autoDispose<List<AdminProductRow>>((ref) => ref.watch(catalogAdminRepositoryProvider).products());

final adminProductProvider =
    FutureProvider.autoDispose.family<Product, String>((ref, id) => ref.watch(catalogAdminRepositoryProvider).product(id));

final adminBrandsProvider = FutureProvider.autoDispose<List<Brand>>((ref) => ref.watch(catalogRepositoryProvider).brands());

/// Staff add a brand from the product form's brand picker. An existing slug returns that brand instead.
Future<Brand> createBrand(WidgetRef ref, String name) async {
  final clean = brandDisplayName(name);
  final slug = slugify(clean);
  if (clean.isEmpty || clean.length > 40) throw const FormatException('Brand names are 1 to 40 characters.');
  if (slug.isEmpty) throw const FormatException('Use English letters or numbers in the brand name.');
  final brand = await ref.read(catalogAdminRepositoryProvider).createBrand(clean);
  ref.invalidate(adminBrandsProvider);
  ref.invalidate(brandsProvider);
  return brand;
}

final adminCategoriesProvider =
    FutureProvider.autoDispose<List<Category>>((ref) => ref.watch(catalogRepositoryProvider).categories());

void _productChanged(WidgetRef ref, String productId) {
  ref.invalidate(adminProductProvider(productId));
  ref.invalidate(adminProductsProvider);
  ref.invalidate(adminDashboardProvider);
  ref.invalidate(catalogueSummaryProvider); // the stock alerts
}

/// Inserts when [id] is null. Returns the product id.
Future<String> saveProduct(WidgetRef ref, String? id, Map<String, dynamic> fields) async {
  final saved = await ref.read(catalogAdminRepositoryProvider).saveProduct(id, fields);
  _productChanged(ref, saved);
  return saved;
}

/// Compresses [original] (photos.dart) and uploads `<folder>/<millis>.webp` plus `<folder>/<millis>@thumb.webp`.
/// Returns the full photo's key, the only one the DB stores, and the sizes for the "4.2 MB → 180 KB" message.
Future<({String path, int before, int after})> _uploadPhoto(WidgetRef ref, String folder, Uint8List original) async {
  final photo = await preparePhoto(original);
  final path = await ref.read(photoStoreProvider).upload(folder, photo);
  return (path: path, before: photo.originalBytes, after: photo.full.length);
}

Future<void> _removeFiles(WidgetRef ref, String path) => ref.read(photoStoreProvider).remove([path, ?thumbPathFor(path)]);

/// The product's photos as saved now (the edit screen's copy may be a reload behind).
Future<List<ProductPhoto>> _photos(WidgetRef ref, String productId) async =>
    (await ref.read(catalogAdminRepositoryProvider).product(productId)).images;

Future<void> _setPhotos(WidgetRef ref, String productId, List<ProductPhoto> images) async {
  await ref.read(catalogAdminRepositoryProvider).setProductImages(productId, images);
  _productChanged(ref, productId);
}

/// Uploads the photo and its thumb, then adds it to the product (removing the files if that fails).
/// [color]: the variant colour it shows (null: every colour).
Future<({int before, int after})> addProductImage(WidgetRef ref, String productId, Uint8List original, int sort,
    {String? color}) async {
  final up = await _uploadPhoto(ref, productId, original);
  try {
    await _setPhotos(ref, productId, [...await _photos(ref, productId), ProductPhoto(id: '', path: up.path, sort: sort, color: color)]);
  } catch (_) {
    await _removeFiles(ref, up.path);
    rethrow;
  }
  return (before: up.before, after: up.after);
}

/// Removes the photo from the product but keeps the file: past orders still show it via the order's image path.
/// shortcut: files are never cleaned up (~200 KB each); add a sweep for unreferenced files if storage grows.
Future<void> deleteProductImage(WidgetRef ref, String productId, ProductPhoto image) async =>
    _setPhotos(ref, productId, [for (final i in await _photos(ref, productId)) if (i.id != image.id) i]);

/// sort = position, in the order shown.
Future<void> reorderImages(WidgetRef ref, String productId, List<ProductPhoto> ordered) => _setPhotos(
    ref, productId, [for (final (i, image) in ordered.indexed) ProductPhoto(id: image.id, path: image.path, sort: i, color: image.color)]);

/// Which colour a photo shows: one of the variants' colours, or null for every colour.
Future<void> setImageColor(WidgetRef ref, String productId, ProductPhoto image, String? color) async => _setPhotos(ref, productId, [
      for (final i in await _photos(ref, productId))
        i.id == image.id ? ProductPhoto(id: i.id, path: i.path, sort: i.sort, color: color) : i
    ]);

/// Inserts when [variantId] is null.
Future<void> saveVariant(WidgetRef ref, String productId, String? variantId, Map<String, dynamic> fields) async {
  await ref.read(catalogAdminRepositoryProvider).saveVariant(productId, variantId, fields);
  _productChanged(ref, productId);
}

// Settings --------------------------------------------------------------------

Future<void> saveSettings(WidgetRef ref, StoreSettings settings) async {
  await ref.read(settingsRepositoryProvider).saveStoreSettings(settings);
  ref.invalidate(storeSettingsProvider);
}

/// Saves the shop photo list (max 8) and waits for the reload, so the next edit starts from the saved list.
Future<void> saveStorePhotos(WidgetRef ref, List<String> paths) async {
  await ref.read(settingsRepositoryProvider).saveStorePhotos(paths);
  ref.invalidate(storeSettingsProvider);
  try {
    await ref.read(storeSettingsProvider.future);
  } catch (_) {} // saved; the screen shows the reload error
}

/// Uploads the photo and its thumb to `store/`, then appends it to [current] (removing the files if that fails).
Future<({int before, int after})> addStorePhoto(WidgetRef ref, List<String> current, Uint8List original) async {
  final up = await _uploadPhoto(ref, 'store', original);
  try {
    await saveStorePhotos(ref, [...current, up.path]);
  } catch (_) {
    await _removeFiles(ref, up.path);
    rethrow;
  }
  return (before: up.before, after: up.after);
}

/// Unlike product photos, no order points at shop photos, so the file and its thumb are deleted too.
Future<void> removeStorePhoto(WidgetRef ref, List<String> current, String path) async {
  await saveStorePhotos(ref, [...current]..remove(path));
  await _removeFiles(ref, path);
}

/// Staff, signed in within 5 minutes (Rules); Firebase build only.
Future<void> saveBusinessProfile(WidgetRef ref, BusinessProfile profile) async {
  await ref.read(settingsRepositoryProvider).saveBusinessProfile(profile);
  ref.invalidate(businessProfileProvider);
  ref.invalidate(storeSettingsProvider); // the store phone and address come from it
}

// Banners ---------------------------------------------------------------------

/// Uploads a banner photo and its thumb to `banners/`; returns the key for the banner's image path.
Future<String> uploadBannerImage(WidgetRef ref, Uint8List original) async => (await _uploadPhoto(ref, 'banners', original)).path;

/// No order points at banner photos, so a replaced or removed one is deleted with its thumb.
Future<void> deleteBannerImage(WidgetRef ref, String path) => _removeFiles(ref, path);
