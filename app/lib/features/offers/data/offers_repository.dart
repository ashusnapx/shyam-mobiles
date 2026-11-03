import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import 'offers_repository_firebase.dart';
import 'offers_repository_supabase.dart';

/// Offers customers may use, home banners and Refer & earn (docs/FIREBASE.md §1: publicOffers, users/{uid}/coupons,
/// banners, myReferral, applyReferralCode). Hidden and personal codes are never listable. Owner: engineer C.
abstract interface class OffersRepository {
  /// Running offers the caller may use: public ones plus their personal coupons.
  Future<List<Offer>> available();

  /// Running offers that cover [productId].
  Future<List<Offer>> forProduct(String productId);

  /// What an offer covers, by name, rows [from]..[from + size − 1].
  Future<List<ProductCard>> products(String promotionId, int from, int size);

  /// Customers get the running ones; staff get every banner (callers filter with PromoBanner.runningAt).
  Future<List<PromoBanner>> banners();

  Future<Referral> myReferral();

  /// Links the caller to a friend's code (REFERRAL_*); returns the welcome coupon.
  Future<Offer> applyReferral(String code);
}

final offersRepositoryProvider = Provider<OffersRepository>((ref) => backend == Backend.firebase
    ? FirebaseOffersRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider), ref.watch(firebaseAuthProvider))
    : SupabaseOffersRepository(ref.watch(supabaseProvider)));
