// Offers (docs/SPEC.md "Offers"): promotions are coupons (with a code) or automatic sales (without one). Every
// amount here comes from the server; the app never works out a discount itself.

enum OfferKind {
  percent('percent', 'Percent off'),
  flat('flat', 'Flat amount off'),
  freeDelivery('free_delivery', 'Free delivery');

  const OfferKind(this.value, this.label);
  final String value;
  final String label; // for the admin type picker

  static OfferKind parse(String v) => values.firstWhere((k) => k.value == v);
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

/// A running offer the caller may use, from `available_offers()` or `offers_for_product()`.
class Offer {
  const Offer({
    required this.id,
    required this.title,
    required this.kind,
    required this.value,
    required this.startsAt,
    this.description = '',
    this.code,
    this.maxDiscountPaise,
    this.minSubtotalPaise = 0,
    this.endsAt,
    this.wholeOrder = true,
    this.onlineOnly = false,
    this.firstOrderOnly = false,
  });

  final String id;
  final String title;
  final String description; // the terms line
  final String? code; // null: an automatic sale
  final OfferKind kind;
  final int value; // percent 1..90, flat paise, 0 for free delivery
  final int? maxDiscountPaise;
  final int minSubtotalPaise;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool wholeOrder; // applies_to = order; false: only some products
  final bool onlineOnly;
  final bool firstOrderOnly;

  bool get automatic => code == null;

  factory Offer.fromJson(Map<String, dynamic> j) => Offer(
        id: j['id'],
        title: j['title'],
        description: j['description'] ?? '',
        code: j['code'],
        kind: OfferKind.parse(j['kind']),
        value: j['value'],
        maxDiscountPaise: j['max_discount_paise'],
        minSubtotalPaise: j['min_subtotal_paise'] ?? 0,
        startsAt: DateTime.parse(j['starts_at']),
        endsAt: _date(j['ends_at']),
        wholeOrder: j['applies_to'] != 'items',
        onlineOnly: j['online_only'] ?? false,
        firstOrderOnly: j['first_order_only'] ?? false,
      );
}

/// `quote_order()`: the server's price for the cart as it is now, with the chosen code (or the best sale).
class Quote {
  const Quote({
    required this.subtotalPaise,
    required this.deliveryFeePaise,
    required this.discountPaise,
    required this.totalPaise,
    this.promotion,
    this.couponError,
    this.couponErrorDetail,
  });

  final int subtotalPaise;
  final int deliveryFeePaise;
  final int discountPaise;
  final int totalPaise;
  final ({String id, String title, String? code, OfferKind kind})? promotion;
  final String? couponError; // a COUPON_* code when the typed code didn't apply
  final String? couponErrorDetail; // the minimum in paise for COUPON_MIN_ORDER

  /// What the summary calls the discount: the code, or the sale's title.
  String? get discountLabel => promotion == null ? null : promotion!.code ?? promotion!.title;

  factory Quote.fromJson(Map<String, dynamic> j) {
    final p = j['promotion'] as Map<String, dynamic>?;
    return Quote(
      subtotalPaise: j['subtotal_paise'],
      deliveryFeePaise: j['delivery_fee_paise'],
      discountPaise: j['discount_paise'] ?? 0,
      totalPaise: j['total_paise'],
      promotion: p == null ? null : (id: p['id'], title: p['title'], code: p['code'], kind: OfferKind.parse(p['kind'])),
      couponError: j['coupon_error'],
      couponErrorDetail: j['coupon_error_detail']?.toString(),
    );
  }
}

/// A home banner. `link` is an app route (DB allowlist); `tone` indexes heroGradients.
class PromoBanner {
  const PromoBanner({
    required this.id,
    required this.title,
    required this.link,
    required this.startsAt,
    this.subtitle = '',
    this.ctaLabel = 'Shop now',
    this.imagePath,
    this.tone = 0,
    this.sort = 0,
    this.endsAt,
    this.isActive = true,
    this.promotionId,
  });

  final String id;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final String link;
  final String? imagePath;
  final int tone;
  final int sort;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool isActive;
  final String? promotionId; // made by an offer's "Show a banner"

  bool runningAt(DateTime now) => statusAt(now) == PromotionStatus.running;

  PromotionStatus statusAt(DateTime now) => statusOf(isActive: isActive, startsAt: startsAt, endsAt: endsAt, now: now);

  factory PromoBanner.fromJson(Map<String, dynamic> j) => PromoBanner(
        id: j['id'],
        title: j['title'],
        subtitle: j['subtitle'] ?? '',
        ctaLabel: j['cta_label'] ?? 'Shop now',
        link: j['link'],
        imagePath: j['image_path'],
        tone: j['tone'] ?? 0,
        sort: j['sort'] ?? 0,
        startsAt: DateTime.parse(j['starts_at']),
        endsAt: _date(j['ends_at']),
        isActive: j['is_active'] ?? true,
        promotionId: j['promotion_id'],
      );
}

/// `my_referral()`.
class Referral {
  const Referral({
    required this.enabled,
    required this.code,
    required this.friendPaise,
    required this.rewardPaise,
    required this.minOrderPaise,
    this.joined = 0,
    this.rewarded = 0,
    this.canEnterCode = false,
  });

  final bool enabled;
  final String code;
  final int friendPaise;
  final int rewardPaise;
  final int minOrderPaise;
  final int joined; // friends who used the code
  final int rewarded; // rewards earned so far
  final bool canEnterCode; // no referrer yet and no order yet

  factory Referral.fromJson(Map<String, dynamic> j) => Referral(
        enabled: j['enabled'] ?? false,
        code: j['code'] ?? '',
        friendPaise: j['friend_paise'] ?? 0,
        rewardPaise: j['reward_paise'] ?? 0,
        minOrderPaise: j['min_order_paise'] ?? 0,
        joined: j['joined'] ?? 0,
        rewarded: j['rewarded'] ?? 0,
        canEnterCode: j['can_enter_code'] ?? false,
      );
}

enum TargetType { product, category, brand, collection }

enum PromotionStatus {
  running('Running'),
  scheduled('Scheduled'),
  paused('Paused'),
  ended('Ended');

  const PromotionStatus(this.label);
  final String label;
}

/// Where an offer or banner is in its life. Ended wins over paused, paused over scheduled.
PromotionStatus statusOf({required bool isActive, required DateTime startsAt, DateTime? endsAt, required DateTime now}) =>
    endsAt != null && !endsAt.isAfter(now)
        ? PromotionStatus.ended
        : !isActive
            ? PromotionStatus.paused
            : startsAt.isAfter(now)
                ? PromotionStatus.scheduled
                : PromotionStatus.running;

/// A `promotions` row for staff, with its targets and, from `admin_promotions()`, how often it was used.
class Promotion {
  const Promotion({
    this.id,
    required this.title,
    required this.kind,
    required this.value,
    required this.startsAt,
    this.description = '',
    this.code,
    this.maxDiscountPaise,
    this.minSubtotalPaise = 0,
    this.wholeOrder = true,
    this.endsAt,
    this.usageLimit,
    this.perUserLimit = 1,
    this.firstOrderOnly = false,
    this.onlineOnly = false,
    this.isPublic = true,
    this.isActive = true,
    this.showBanner = false,
    this.userId,
    this.targets = const {},
    this.uses = 0,
    this.discountTotalPaise = 0,
    this.status,
  });

  final String? id; // null until saved
  final String title;
  final String description;
  final String? code;
  final OfferKind kind;
  final int value;
  final int? maxDiscountPaise;
  final int minSubtotalPaise;
  final bool wholeOrder;
  final DateTime startsAt;
  final DateTime? endsAt;
  final int? usageLimit;
  final int? perUserLimit;
  final bool firstOrderOnly;
  final bool onlineOnly;
  final bool isPublic;
  final bool isActive;
  final bool showBanner;
  final String? userId; // a personal (referral) coupon
  final Set<(TargetType, String)> targets;
  final int uses;
  final int discountTotalPaise;
  final PromotionStatus? status; // `admin_promotions()` says; [statusAt] works it out for rows without it

  PromotionStatus statusAt(DateTime now) =>
      status ?? statusOf(isActive: isActive, startsAt: startsAt, endsAt: endsAt, now: now);

  factory Promotion.fromJson(Map<String, dynamic> j) => Promotion(
        id: j['id'],
        title: j['title'],
        description: j['description'] ?? '',
        code: j['code'],
        kind: OfferKind.parse(j['kind']),
        value: j['value'],
        maxDiscountPaise: j['max_discount_paise'],
        minSubtotalPaise: j['min_subtotal_paise'] ?? 0,
        wholeOrder: j['applies_to'] != 'items',
        startsAt: DateTime.parse(j['starts_at']),
        endsAt: _date(j['ends_at']),
        usageLimit: j['usage_limit'],
        perUserLimit: j['per_user_limit'],
        firstOrderOnly: j['first_order_only'] ?? false,
        onlineOnly: j['online_only'] ?? false,
        isPublic: j['is_public'] ?? true,
        isActive: j['is_active'] ?? true,
        showBanner: j['show_banner'] ?? false,
        userId: j['user_id'],
        targets: {
          for (final t in (j['targets'] as List? ?? const []))
            (TargetType.values.byName(t['target_type']), t['target_id'] as String),
        },
        uses: (j['uses'] as num?)?.toInt() ?? 0,
        discountTotalPaise: (j['discount_total_paise'] as num?)?.toInt() ?? 0,
        status: PromotionStatus.values.asNameMap()[j['status']],
      );

  /// The `admin_save_promotion(p)` payload: the row's columns plus its targets (which replace the old ones). No
  /// `id` inserts; `user_id` is left out, so a personal coupon keeps its owner.
  Map<String, dynamic> toJson() => {
        'id': ?id,
        'title': title,
        'description': description,
        'code': code,
        'kind': kind.value,
        'value': value,
        'max_discount_paise': maxDiscountPaise,
        'min_subtotal_paise': minSubtotalPaise,
        'applies_to': wholeOrder ? 'order' : 'items',
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'usage_limit': usageLimit,
        'per_user_limit': perUserLimit,
        'first_order_only': firstOrderOnly,
        'online_only': onlineOnly,
        'is_public': isPublic,
        'is_active': isActive,
        'show_banner': showBanner,
        'targets': [
          if (!wholeOrder)
            for (final (type, id) in targets) {'target_type': type.name, 'target_id': id},
        ],
      };
}

/// A product group (`collections` + `collection_products`).
class Collection {
  const Collection({this.id, required this.slug, required this.name, this.productIds = const {}});

  final String? id;
  final String slug;
  final String name;
  final Set<String> productIds;

  factory Collection.fromJson(Map<String, dynamic> j) => Collection(
        id: j['id'],
        slug: j['slug'],
        name: j['name'],
        productIds: {for (final p in (j['products'] as List? ?? const [])) p['product_id'] as String},
      );
}
