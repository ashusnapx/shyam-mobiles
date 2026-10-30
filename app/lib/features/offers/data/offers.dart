import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/paging.dart';
import '../../../core/supabase.dart';
import '../../cart/data/cart.dart';
import '../../catalog/data/catalog.dart' show cardColumns;

/// Offer RPCs and banners; a provider so tests can swap it. Customers never read `promotions` itself, so hidden
/// and personal codes can't be listed.
class OffersApi {
  const OffersApi(this._db);

  final SupabaseClient _db;

  /// Prices the caller's cart as it is on the server. A bad [code] comes back as `couponError`, not a throw.
  Future<Quote> quote({String? code, PaymentMethod? method}) async => Quote.fromJson(await _db.rpc<Map<String, dynamic>>(
        'quote_order',
        params: {'p_coupon_code': code, 'p_payment_method': method?.value},
      ));

  Future<List<Offer>> available() async => _offers(await _db.rpc<List<dynamic>>('available_offers'));

  Future<List<Offer>> forProduct(String productId) async =>
      _offers(await _db.rpc<List<dynamic>>('offers_for_product', params: {'p_product_id': productId}));

  /// Rows [from]..[from + size - 1] of what the offer covers, by name (`offer_products` takes PostgREST paging).
  Future<List<ProductCard>> products(String promotionId, int from, int size) async {
    final rows = await _db
        .rpc<PostgrestList>('offer_products', params: {'p_promotion_id': promotionId})
        .select(cardColumns)
        .order('name', ascending: true)
        .order('id')
        .range(from, from + size - 1);
    return [for (final r in rows) ProductCard.fromJson(r)];
  }

  /// RLS shows customers only running banners; staff see every row, so callers filter with `runningAt`.
  Future<List<PromoBanner>> banners() async {
    final rows = await _db.from('banners').select().order('sort').order('created_at');
    return [for (final r in rows) PromoBanner.fromJson(r)];
  }

  Future<Referral> myReferral() async => Referral.fromJson(await _db.rpc<Map<String, dynamic>>('my_referral'));

  /// Returns the friend's welcome coupon.
  Future<Offer> applyReferral(String code) async =>
      Offer.fromJson(await _db.rpc<Map<String, dynamic>>('apply_referral_code', params: {'p_code': code}));

  List<Offer> _offers(List<dynamic> rows) => [for (final r in rows) Offer.fromJson(r as Map<String, dynamic>)];
}

final offersApiProvider = Provider<OffersApi>((ref) => OffersApi(ref.watch(supabaseProvider)));

/// The code the customer applied in the cart, at checkout or from Offers. It rides along to every quote and to
/// `place_order`, and is dropped after an order or on a change of account.
final couponCodeProvider = NotifierProvider<CouponCode, String?>(CouponCode.new);

class CouponCode extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(currentUserIdProvider);
    return null;
  }

  void set(String? code) => state = code;
}

/// The server's price of the cart for [method] (null before one is picked) with the applied code. Re-quotes on
/// every cart or code change, once the cart's queued writes have landed, so it prices what `place_order` charges.
final quoteProvider = FutureProvider.autoDispose.family<Quote, PaymentMethod?>((ref, method) async {
  // quote_order refuses an empty cart (CART_EMPTY); nothing shows a total then anyway
  if ((await ref.watch(cartProvider.future)).isEmpty) return const Quote(subtotalPaise: 0, deliveryFeePaise: 0, discountPaise: 0, totalPaise: 0);
  final code = ref.watch(couponCodeProvider);
  await ref.read(cartProvider.notifier).settled;
  return ref.watch(offersApiProvider).quote(code: code, method: method);
});

/// Running offers the caller may use: public ones plus their personal coupons.
final availableOffersProvider = FutureProvider.autoDispose<List<Offer>>((ref) {
  cacheFor(ref, const Duration(minutes: 2));
  ref.watch(currentUserIdProvider); // personal coupons belong to the signed-in account
  return ref.watch(offersApiProvider).available();
});

final productOffersProvider = FutureProvider.autoDispose.family<List<Offer>, String>((ref, productId) {
  cacheFor(ref, const Duration(minutes: 5));
  ref.watch(currentUserIdProvider);
  return ref.watch(offersApiProvider).forProduct(productId);
});

/// What an offer covers, a page at a time (an order-wide offer covers the whole shop).
final offerProductsProvider =
    AsyncNotifierProvider.autoDispose.family<OfferProducts, Paged<ProductCard>, String>(OfferProducts.new);

class OfferProducts extends PagedNotifier<ProductCard> {
  OfferProducts(this.promotionId);

  final String promotionId;

  @override
  Object idOf(ProductCard c) => c.id;

  @override
  Future<Paged<ProductCard>> build() {
    cacheFor(ref, const Duration(minutes: 5));
    return super.build();
  }

  @override
  Future<List<ProductCard>> fetch(int from, int size) => ref.read(offersApiProvider).products(promotionId, from, size);
}

/// App routes a banner may open (the DB allows `^/(search|product/|offers|repairs)`; this also checks the rest
/// is a real route, so a typo can't land on an error page).
final _bannerLink = RegExp(r'^/(search(\?[^#\s]*)?|product/[a-z0-9-]{1,160}|offers(/[0-9a-f-]{36})?|repairs(/new)?)$');

bool isBannerLink(String link) => _bannerLink.hasMatch(link);

/// Home banners that are running now and link somewhere real, in staff order.
final bannersProvider = FutureProvider<List<PromoBanner>>((ref) async {
  final now = DateTime.now();
  return [
    for (final b in await ref.watch(offersApiProvider).banners())
      if (b.runningAt(now) && isBannerLink(b.link)) b,
  ];
});

/// Home's banner slides: running now and linking somewhere real ([bannersProvider]); an offer's banner only while
/// this customer can still use the offer (available_offers leaves out ended, used-up and spent first-order ones,
/// which would open "This offer has ended").
final homeBannersProvider = Provider.autoDispose<List<PromoBanner>>((ref) {
  final now = DateTime.now();
  final open = {...?ref.watch(availableOffersProvider).value?.map((o) => o.id)};
  return [
    for (final b in ref.watch(bannersProvider).value ?? const <PromoBanner>[])
      if (b.runningAt(now) && (b.promotionId == null || open.contains(b.promotionId))) b,
  ];
});

final myReferralProvider = FutureProvider.autoDispose<Referral>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(offersApiProvider).myReferral();
});

/// Links the caller to a friend and returns their welcome coupon, which then also shows in Offers.
Future<Offer> applyReferralCode(WidgetRef ref, String code) async {
  final welcome = await ref.read(offersApiProvider).applyReferral(code);
  ref.invalidate(myReferralProvider);
  ref.invalidate(availableOffersProvider);
  return welcome;
}
