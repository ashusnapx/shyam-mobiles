import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../wishlist/data/wishlist.dart' show wishlistProvider;

/// What the product page says after Notify me.
const backInStockSaved = 'Saved. We’ll tell you when it’s back in stock.';

/// Notify me on a sold-out variant (docs/FIREBASE.md §6): the product goes on the wishlist with the back-in-stock mark,
/// [waitFor] the variant id, or '*' when every variant is sold out; the restock trigger clears it once it has told
/// them. The Supabase build has no alerts, so there it only saves the product.
Future<void> notifyWhenBack(WidgetRef ref, String productId, String waitFor) =>
    ref.read(wishlistProvider.notifier).notifyWhenBack(productId, waitFor);
