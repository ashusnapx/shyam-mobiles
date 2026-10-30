// Offline stand-ins for the offer RPCs: no network, every call recorded.
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/offers_admin.dart';
import 'package:shyam_mobiles/features/offers/data/offers.dart';

/// An automatic sale on a big cart: enough to put every summary line on screen.
const saleQuote = Quote(
  subtotalPaise: 12999900,
  deliveryFeePaise: 0,
  discountPaise: 150000,
  totalPaise: 12849900,
  promotion: (id: 'sale1', title: 'Diwali dhamaka on phones', code: null, kind: OfferKind.percent),
);

final diwali = Offer(
  id: '11111111-1111-1111-1111-111111111111',
  title: 'Flat ₹500 off phones',
  description: 'On every smartphone. Not with exchange offers.',
  code: 'DIWALI500',
  kind: OfferKind.flat,
  value: 50000,
  minSubtotalPaise: 999900,
  startsAt: DateTime(2026, 10, 1),
  endsAt: DateTime.now().add(const Duration(days: 3, hours: 2)),
  wholeOrder: false,
);

final festiveSale = Offer(
  id: '22222222-2222-2222-2222-222222222222',
  title: 'Festive sale: 10% off accessories',
  kind: OfferKind.percent,
  value: 10,
  maxDiscountPaise: 50000,
  startsAt: DateTime(2026, 10, 1),
);

class FakeOffersApi implements OffersApi {
  FakeOffersApi({
    this.offers = const [],
    this.bannerRows = const [],
    this.referral,
    this.productRows = const [],
    Quote Function(String? code, PaymentMethod? method)? quote,
  }) : onQuote = quote ?? ((_, _) => saleQuote);

  List<Offer> offers;
  List<PromoBanner> bannerRows;
  Referral? referral;
  List<ProductCard> productRows;
  Quote Function(String? code, PaymentMethod? method) onQuote;
  Exception? referralError; // thrown by applyReferral
  final calls = <String>[];

  @override
  Future<Quote> quote({String? code, PaymentMethod? method}) async {
    calls.add('quote ${code ?? '-'} ${method?.value ?? '-'}');
    return onQuote(code, method);
  }

  @override
  Future<List<Offer>> available() async => offers;

  @override
  Future<List<Offer>> forProduct(String productId) async => offers;

  @override
  Future<List<ProductCard>> products(String promotionId, int from, int size) async =>
      productRows.skip(from).take(size).toList();

  @override
  Future<List<PromoBanner>> banners() async => bannerRows;

  @override
  Future<Referral> myReferral() async => referral!;

  @override
  Future<Offer> applyReferral(String code) async {
    calls.add('referral $code');
    if (referralError case final e?) throw e;
    return Offer(id: 'w1', title: 'Welcome', code: 'FRIEND8X2K', kind: OfferKind.flat, value: 20000, startsAt: DateTime(2026));
  }
}

class FakeAdminOffersApi implements AdminOffersApi {
  FakeAdminOffersApi({this.list = const [], this.groups = const [], this.bannerRows = const []});

  List<Promotion> list;
  List<Collection> groups;
  List<PromoBanner> bannerRows;
  final saved = <Map<String, dynamic>>[];
  final calls = <String>[];

  @override
  Future<List<Promotion>> promotions() async => list;

  @override
  Future<String> savePromotion(Map<String, dynamic> p) async {
    saved.add(p);
    return p['id'] as String? ?? 'new-id';
  }

  @override
  Future<void> deletePromotion(String id) async => calls.add('delete $id');

  @override
  Future<List<Collection>> collections() async => groups;

  @override
  Future<String> saveCollection(Collection c, {Set<String> before = const {}}) async {
    calls.add('group ${c.name} ${c.productIds.length}');
    return c.id ?? 'g-new';
  }

  @override
  Future<void> deleteCollection(String id) async => calls.add('delete group $id');

  @override
  Future<List<PromoBanner>> banners() async => bannerRows;

  @override
  Future<String> saveBanner(String? id, Map<String, dynamic> fields) async {
    saved.add(fields);
    return id ?? 'b-new';
  }

  @override
  Future<void> deleteBanner(String id) async => calls.add('delete banner $id');
}
