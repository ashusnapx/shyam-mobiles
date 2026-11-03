import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/cart/data/cart_repository.dart';

import 'fake.dart';

/// Seed [lines] per uid; [hidden] variant ids come back as hidden on the next load.
class FakeCartRepository with Fake implements CartRepository {
  final lines = <String, List<CartLine>>{};
  final hidden = <String, List<String>>{};

  @override
  Future<({List<CartLine> lines, List<String> hidden})> load(String uid) async {
    record('load $uid');
    return (lines: [...?lines[uid]], hidden: [...?hidden[uid]]);
  }

  @override
  Future<void> put(String uid, String variantId, int qty) async {
    record('put $variantId $qty');
    final list = lines.putIfAbsent(uid, () => []);
    final i = list.indexWhere((l) => l.variant.id == variantId);
    if (i >= 0) list[i] = list[i].copyWith(qty: qty);
    // a new line needs its variant: tests seed lines they add to
  }

  @override
  Future<void> remove(String uid, List<String> variantIds) async {
    record('remove ${variantIds.join(',')}');
    lines[uid]?.removeWhere((l) => variantIds.contains(l.variant.id));
    hidden[uid]?.removeWhere(variantIds.contains);
  }
}
