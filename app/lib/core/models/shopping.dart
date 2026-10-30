import '../format.dart';
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

enum AddressLabel {
  home('Home'),
  work('Work'),
  other('Other');

  const AddressLabel(this.displayName);
  final String displayName; // the DB value is `name`

  static AddressLabel parse(String? v) => values.asNameMap()[v] ?? home; // old order snapshots have no label
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
    this.district,
    this.label = AddressLabel.home,
    this.isDefault = false,
  });

  final String? id; // null until saved
  final String name;
  final String phone; // E.164, +91XXXXXXXXXX
  final String line1;
  final String? line2;
  final String? landmark;
  final String city;
  final String? district;
  final String state;
  final String pincode;
  final AddressLabel label;
  final bool isDefault;

  String get oneLine => [
        line1,
        line2,
        landmark,
        city,
        if (district?.toLowerCase() != city.toLowerCase()) district,
        '$state $pincode',
      ].where((s) => s != null && s.isNotEmpty).join(', ');

  factory Address.fromJson(Map<String, dynamic> j) => Address(
        id: j['id'],
        name: j['name'],
        phone: j['phone'],
        line1: j['line1'],
        line2: j['line2'],
        landmark: j['landmark'],
        city: j['city'],
        district: j['district'],
        state: j['state'],
        pincode: j['pincode'],
        label: AddressLabel.parse(j['label']),
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
        'district': district,
        'state': state,
        'pincode': pincode,
        'label': label.name,
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
    this.storeLat,
    this.storeLng,
    this.storeMapsUrl,
    this.storePhotos = const [],
    this.storeHours = '',
    required this.repairNote,
    this.returnsPolicy = '',
    this.referralEnabled = false,
    this.referralFriendPaise = 20000,
    this.referralRewardPaise = 20000,
    this.referralMinOrderPaise = 199900,
    this.referralMonthlyCap = 10,
  });

  final int deliveryFeePaise;
  final int freeDeliveryMinPaise;
  final bool codEnabled;
  final int codMaxPaise;
  final String storePhone;
  final String storeAddress;
  final double? storeLat;
  final double? storeLng;
  final String? storeMapsUrl; // the Google Maps listing; we only link to it
  final List<String> storePhotos; // product-images object keys, in display order
  final String storeHours;
  final String repairNote;
  final String returnsPolicy;
  final bool referralEnabled; // Refer & earn: the friend's welcome coupon and the referrer's reward
  final int referralFriendPaise;
  final int referralRewardPaise;
  final int referralMinOrderPaise;
  final int referralMonthlyCap; // rewards per referrer per IST month

  /// Mirrors `place_order`; the server total is the one that's charged.
  int deliveryFeeFor(int subtotalPaise) => subtotalPaise >= freeDeliveryMinPaise ? 0 : deliveryFeePaise;

  /// `place_order`'s COD rule: on the total *including* delivery (subtotal + fee), limit inclusive.
  bool codAllowedFor(int totalPaise) => codEnabled && totalPaise <= codMaxPaise;

  /// How much more to add for free delivery ("Add ₹X more"); 0 when delivery is already free.
  int freeDeliveryGapFor(int subtotalPaise) =>
      deliveryFeeFor(subtotalPaise) == 0 ? 0 : freeDeliveryMinPaise - subtotalPaise;

  /// Where directions go: the exact pin when staff set one, else the address text.
  String get mapsDestination => storeLat == null || storeLng == null ? storeAddress : '$storeLat,$storeLng';

  /// The shop on Google Maps (photos, reviews, hours): its listing, else the pin. Null when neither is set.
  Uri? get mapsListingUri => storeMapsUrl != null
      ? Uri.tryParse(storeMapsUrl!)
      : storeLat == null || storeLng == null
          ? null
          : mapPinUri(storeLat!, storeLng!);

  factory StoreSettings.fromJson(Map<String, dynamic> j) => StoreSettings(
        deliveryFeePaise: j['delivery_fee_paise'],
        freeDeliveryMinPaise: j['free_delivery_min_paise'],
        codEnabled: j['cod_enabled'],
        codMaxPaise: j['cod_max_paise'],
        storePhone: j['store_phone'],
        storeAddress: j['store_address'],
        storeLat: (j['store_lat'] as num?)?.toDouble(),
        storeLng: (j['store_lng'] as num?)?.toDouble(),
        storeMapsUrl: j['store_maps_url'],
        storePhotos: [...?(j['store_photos'] as List?)?.cast<String>()],
        storeHours: j['store_hours'],
        repairNote: j['repair_note'],
        returnsPolicy: j['returns_policy'],
        // defaults for copies saved on the phone before referrals existed
        referralEnabled: j['referral_enabled'] ?? false,
        referralFriendPaise: j['referral_friend_paise'] ?? 20000,
        referralRewardPaise: j['referral_reward_paise'] ?? 20000,
        referralMinOrderPaise: j['referral_min_order_paise'] ?? 199900,
        referralMonthlyCap: j['referral_monthly_cap'] ?? 10,
      );

  Map<String, dynamic> toJson() => {
        'delivery_fee_paise': deliveryFeePaise,
        'free_delivery_min_paise': freeDeliveryMinPaise,
        'cod_enabled': codEnabled,
        'cod_max_paise': codMaxPaise,
        'store_phone': storePhone,
        'store_address': storeAddress,
        'store_lat': storeLat,
        'store_lng': storeLng,
        'store_maps_url': storeMapsUrl,
        'store_photos': storePhotos,
        'store_hours': storeHours,
        'repair_note': repairNote,
        'returns_policy': returnsPolicy,
        'referral_enabled': referralEnabled,
        'referral_friend_paise': referralFriendPaise,
        'referral_reward_paise': referralRewardPaise,
        'referral_min_order_paise': referralMinOrderPaise,
        'referral_monthly_cap': referralMonthlyCap,
      };
}

class Profile {
  const Profile({required this.id, this.fullName, this.phone});

  final String id;
  final String? fullName;
  final String? phone;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(id: j['id'], fullName: j['full_name'], phone: j['phone']);
}
