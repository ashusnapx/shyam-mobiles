import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/offers/data/offers_repository.dart';

import 'fake.dart';

/// Seed the lists; [welcome] is what applyReferral returns for any code but [referral]'s own.
class FakeOffersRepository with Fake implements OffersRepository {
  var offers = <Offer>[];
  final offersByProduct = <String, List<Offer>>{};
  final coveredCards = <String, List<ProductCard>>{}; // promotionId → cards, by name
  var bannerList = <PromoBanner>[];
  var referral = const Referral(enabled: true, code: 'RAVI2026', friendPaise: 20000, rewardPaise: 20000, minOrderPaise: 199900);
  Offer? welcome;

  @override
  Future<List<Offer>> available() async {
    record('available');
    return offers;
  }

  @override
  Future<List<Offer>> forProduct(String productId) async {
    record('forProduct $productId');
    return [...?offersByProduct[productId]];
  }

  @override
  Future<List<ProductCard>> products(String promotionId, int from, int size) async {
    record('products $promotionId $from');
    return pageOf(coveredCards[promotionId] ?? const [], from, size);
  }

  @override
  Future<List<PromoBanner>> banners() async {
    record('banners');
    return bannerList;
  }

  @override
  Future<Referral> myReferral() async {
    record('myReferral');
    return referral;
  }

  @override
  Future<Offer> applyReferral(String code) async {
    record('applyReferral $code');
    if (code == referral.code) throw reason('REFERRAL_SELF');
    return welcome ?? (throw reason('REFERRAL_INVALID'));
  }
}
