import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart' show firestoreProvider;
import '../../../core/supabase.dart' show supabaseProvider;
import 'wishlist_repository_firebase.dart';
import 'wishlist_repository_supabase.dart';

/// The signed-in customer's saved products (Firebase: users/{uid}/wishlist/{productId}). Owner: engineer B.
abstract interface class WishlistRepository {
  /// Newest first.
  Future<List<String>> productIds(String uid);

  /// No-op when already saved.
  Future<void> add(String uid, String productId);

  Future<void> remove(String uid, String productId);
}

final wishlistRepositoryProvider = Provider<WishlistRepository>((ref) => backend == Backend.firebase
    ? FirebaseWishlistRepository(ref.watch(firestoreProvider))
    : SupabaseWishlistRepository(ref.watch(supabaseProvider)));
