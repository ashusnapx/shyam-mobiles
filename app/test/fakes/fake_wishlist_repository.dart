import 'package:shyam_mobiles/features/wishlist/data/wishlist_repository.dart';

import 'fake.dart';

class FakeWishlistRepository with Fake implements WishlistRepository {
  final saved = <String, List<String>>{}; // uid → product ids, newest first

  @override
  Future<List<String>> productIds(String uid) async {
    record('productIds $uid');
    return [...?saved[uid]];
  }

  final marks = <String, String>{}; // productId → waitVariant

  @override
  Future<void> add(String uid, String productId, {String? waitFor}) async {
    record('add $productId${waitFor == null ? '' : ' wait $waitFor'}');
    if (waitFor != null) marks[productId] = waitFor;
    final ids = saved.putIfAbsent(uid, () => []);
    if (!ids.contains(productId)) ids.insert(0, productId);
  }

  @override
  Future<void> remove(String uid, String productId) async {
    record('remove $productId');
    saved[uid]?.remove(productId);
  }
}
