import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../catalog/data/catalog.dart' show cardColumns;
import 'offers_repository.dart';

/// Today's offer RPCs (available_offers, offers_for_product, offer_products, my_referral, apply_referral_code).
class SupabaseOffersRepository implements OffersRepository {
  const SupabaseOffersRepository(this._db);

  final SupabaseClient _db;

  List<Offer> _offers(List<dynamic> rows) => [for (final r in rows) Offer.fromJson(r as Map<String, dynamic>)];

  @override
  Future<List<Offer>> available() async => _offers(await _db.rpc<List<dynamic>>('available_offers'));

  @override
  Future<List<Offer>> forProduct(String productId) async =>
      _offers(await _db.rpc<List<dynamic>>('offers_for_product', params: {'p_product_id': productId}));

  @override
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
  @override
  Future<List<PromoBanner>> banners() async =>
      [for (final r in await _db.from('banners').select().order('sort').order('created_at')) PromoBanner.fromJson(r)];

  @override
  Future<Referral> myReferral() async => Referral.fromJson(await _db.rpc<Map<String, dynamic>>('my_referral'));

  @override
  Future<Offer> applyReferral(String code) async =>
      Offer.fromJson(await _db.rpc<Map<String, dynamic>>('apply_referral_code', params: {'p_code': code}));
}
