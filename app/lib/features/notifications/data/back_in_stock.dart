import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../../core/backend.dart';
import '../../../core/firebase.dart';
import '../../../core/supabase.dart' show currentUserIdProvider;
import '../../wishlist/data/wishlist.dart' show wishlistProvider;
import '../../wishlist/data/wishlist_repository.dart';

/// What the product page says after Notify me.
const backInStockSaved = 'Saved. We’ll tell you when it’s back in stock.';

/// Notify me on a sold-out variant (docs/FIREBASE.md §6): the product goes on the wishlist with the back-in-stock mark,
/// [waitFor] the variant id, or '*' when every variant is sold out; the restock trigger clears it once it has told
/// them. The Supabase build has no alerts, so there it only saves the product.
/// shortcut: lives here, not on WishlistRepository, while engineer B's wishlist files are being written; move it to
/// `WishlistRepository.notifyWhenBack` once they land.
Future<void> notifyWhenBack(WidgetRef ref, String productId, String waitFor) async {
  final uid = ref.read(currentUserIdProvider);
  if (uid == null) throw const AuthException('Sign in to hear when it’s back in stock');
  if (backend == Backend.firebase) {
    final doc = ref.read(firestoreProvider).doc('users/$uid/wishlist/$productId');
    // Rules: a new entry is stamped with the server's time; an existing one may change only its mark
    (await doc.get()).exists
        ? await doc.update({'waitVariant': waitFor})
        : await doc.set({'productId': productId, 'addedAt': FieldValue.serverTimestamp(), 'waitVariant': waitFor});
  } else {
    await ref.read(wishlistRepositoryProvider).add(uid, productId);
  }
  ref.invalidate(wishlistProvider);
}
