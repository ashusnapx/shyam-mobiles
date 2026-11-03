import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import 'cart_repository_firebase.dart';
import 'cart_repository_supabase.dart';

/// The signed-in customer's cart (Firebase: carts/{uid}, ≤ 20 lines, qty 1..5). Owner: engineer C.
abstract interface class CartRepository {
  /// Lines oldest first. [hidden]: variant ids whose item the shop hid; the caller removes them and says so.
  Future<({List<CartLine> lines, List<String> hidden})> load(String uid);

  /// Sets the line's quantity, adding the line if it isn't there (CART_LIMIT past 20 lines).
  Future<void> put(String uid, String variantId, int qty);

  Future<void> remove(String uid, List<String> variantIds);
}

final cartRepositoryProvider = Provider<CartRepository>((ref) => backend == Backend.firebase
    ? FirebaseCartRepository(ref.watch(firestoreProvider))
    : SupabaseCartRepository(ref.watch(supabaseProvider)));
