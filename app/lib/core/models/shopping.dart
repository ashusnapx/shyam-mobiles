import 'catalog.dart';

/// One cart row, as loaded by
/// `cart_items.select('qty, variant:variants(*, product:products(id, slug, name, is_active, images:product_images(path, sort)))')`.
class CartLine {
  const CartLine({
    required this.variant,
    required this.qty,
    required this.productId,
    required this.productSlug,
    required this.productName,
    this.productActive = true,
    this.coverPath,
  });

  final Variant variant;
  final int qty;
  final String productId;
  final String productSlug;
  final String productName;
  final bool productActive;
  final String? coverPath;

  int get lineTotalPaise => variant.pricePaise * qty;
  bool get purchasable => productActive && variant.isActive && variant.stock >= qty;

  CartLine copyWith({int? qty}) => CartLine(
        variant: variant,
        qty: qty ?? this.qty,
        productId: productId,
        productSlug: productSlug,
        productName: productName,
        productActive: productActive,
        coverPath: coverPath,
      );

  factory CartLine.fromJson(Map<String, dynamic> j) {
    final v = j['variant'] as Map<String, dynamic>;
    final p = v['product'] as Map<String, dynamic>;
    final images = [...(p['images'] as List? ?? const [])]..sort((a, b) => (a['sort'] as int).compareTo(b['sort']));
    return CartLine(
      variant: Variant.fromJson(v),
      qty: j['qty'],
      productId: p['id'],
      productSlug: p['slug'],
      productName: p['name'],
      productActive: p['is_active'] ?? true,
      coverPath: images.isEmpty ? null : images.first['path'],
    );
  }
}

class Address {
  const Address({
    this.id,
    required this.name,
    required this.phone,
    required this.line1,
    required this.city,
    required this.state,
    required this.pincode,
    this.line2,
    this.landmark,
    this.isDefault = false,
  });

  final String? id; // null until saved
  final String name;
  final String phone; // E.164, +91XXXXXXXXXX
  final String line1;
  final String? line2;
  final String? landmark;
  final String city;
  final String state;
  final String pincode;
  final bool isDefault;

  String get oneLine => [line1, line2, landmark, city, '$state $pincode'].where((s) => s != null && s.isNotEmpty).join(', ');

  factory Address.fromJson(Map<String, dynamic> j) => Address(
        id: j['id'],
        name: j['name'],
        phone: j['phone'],
        line1: j['line1'],
        line2: j['line2'],
        landmark: j['landmark'],
        city: j['city'],
        state: j['state'],
        pincode: j['pincode'],
        isDefault: j['is_default'] ?? false,
      );

  /// Columns a client may write. `user_id` is set from the session by the repository.
  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'line1': line1,
        'line2': line2,
        'landmark': landmark,
        'city': city,
        'state': state,
        'pincode': pincode,
        'is_default': isDefault,
      };
}

class StoreSettings {
  const StoreSettings({
    required this.deliveryFeePaise,
    required this.freeDeliveryMinPaise,
    required this.codEnabled,
    required this.codMaxPaise,
    required this.storePhone,
    required this.storeAddress,
    this.storeHours = '',
    required this.repairNote,
    this.returnsPolicy = '',
  });

  final int deliveryFeePaise;
  final int freeDeliveryMinPaise;
  final bool codEnabled;
  final int codMaxPaise;
  final String storePhone;
  final String storeAddress;
  final String storeHours;
  final String repairNote;
  final String returnsPolicy;

  /// Mirrors `place_order`; the server total is the one that's charged.
  int deliveryFeeFor(int subtotalPaise) => subtotalPaise >= freeDeliveryMinPaise ? 0 : deliveryFeePaise;
  bool codAllowedFor(int totalPaise) => codEnabled && totalPaise <= codMaxPaise;

  factory StoreSettings.fromJson(Map<String, dynamic> j) => StoreSettings(
        deliveryFeePaise: j['delivery_fee_paise'],
        freeDeliveryMinPaise: j['free_delivery_min_paise'],
        codEnabled: j['cod_enabled'],
        codMaxPaise: j['cod_max_paise'],
        storePhone: j['store_phone'],
        storeAddress: j['store_address'],
        storeHours: j['store_hours'],
        repairNote: j['repair_note'],
        returnsPolicy: j['returns_policy'],
      );

  Map<String, dynamic> toJson() => {
        'delivery_fee_paise': deliveryFeePaise,
        'free_delivery_min_paise': freeDeliveryMinPaise,
        'cod_enabled': codEnabled,
        'cod_max_paise': codMaxPaise,
        'store_phone': storePhone,
        'store_address': storeAddress,
        'store_hours': storeHours,
        'repair_note': repairNote,
        'returns_policy': returnsPolicy,
      };
}

class Profile {
  const Profile({required this.id, this.fullName, this.phone});

  final String id;
  final String? fullName;
  final String? phone;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(id: j['id'], fullName: j['full_name'], phone: j['phone']);
}
