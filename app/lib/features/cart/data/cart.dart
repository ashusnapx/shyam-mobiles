import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart';

const _select =
    'qty, variant_id, variant:variants(*, product:products(id, slug, name, is_active, images:product_images(path, sort)))';

/// "Galaxy A15 is no longer available and was removed from your cart." for [CartNotifier.takeRemoved]'s names.
String removedNotice(List<String?> names) {
  final known = names.nonNulls.toSet().toList();
  final unknown = names.length - names.nonNulls.length;
  if (known.isEmpty) {
    return unknown == 1
        ? 'An item in your cart is no longer available and was removed.'
        : '$unknown items in your cart are no longer available and were removed.';
  }
  final list = known.length == 1 ? known.first : '${known.take(known.length - 1).join(', ')} and ${known.last}';
  final more = unknown == 0 ? '' : ' (and $unknown more)';
  return '$list$more ${known.length + unknown == 1 ? 'is' : 'are'} no longer available and '
      '${known.length + unknown == 1 ? 'was' : 'were'} removed from your cart.';
}

/// Most of one variant a customer can hold in the cart (DB check allows 1..5).
int maxQtyFor(Variant v) => math.min(v.stock, 5);

/// Σ price × qty, like `place_order` (which refuses the order while any line isn't purchasable).
int cartSubtotalPaise(List<CartLine> lines) => lines.fold(0, (sum, l) => sum + l.lineTotalPaise);

final cartProvider = AsyncNotifierProvider<CartNotifier, List<CartLine>>(CartNotifier.new);

final cartCountProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).value?.fold<int>(0, (sum, l) => sum + l.qty) ?? 0,
);

class CartNotifier extends AsyncNotifier<List<CartLine>> {
  SupabaseClient get _db => ref.read(supabaseProvider);

  final _removed = <String?>[]; // names of lines dropped below, until the cart screen has said so

  /// Lines dropped because the shop hid their item, since the last call, so each is said once. A name is null
  /// when this phone never loaded the line (RLS hides a hidden item's name too).
  List<String?> takeRemoved() {
    final names = [..._removed];
    _removed.clear();
    return names;
  }

  @override
  Future<List<CartLine>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const [];
    final known = {for (final l in state.value ?? const <CartLine>[]) l.variant.id: l.productName};
    final rows = await _db.from('cart_items').select(_select).order('created_at');
    // A line whose item the shop hid comes back without its variant (RLS), yet place_order would still refuse the
    // cart over it, and the customer couldn't see it to remove it: drop it from the cart.
    final hidden = [for (final r in rows) if (r['variant'] == null) r['variant_id'] as String];
    if (hidden.isNotEmpty) {
      await _db.from('cart_items').delete().inFilter('variant_id', hidden);
      _removed.addAll([for (final id in hidden) known[id]]);
    }
    return [for (final r in rows) if (r['variant'] != null) CartLine.fromJson(r)];
  }

  /// Adds [qty] more of [variant], capped by stock and the per-item limit. Requires a signed-in user.
  Future<void> add(Variant variant, {int qty = 1}) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) throw const AuthException('Sign in to add to cart');
    // Wait for the server cart: computing from an unloaded state would upsert qty over the real one.
    final lines = await future;
    final current = lines.where((l) => l.variant.id == variant.id).firstOrNull?.qty ?? 0;
    final next = math.min(current + qty, maxQtyFor(variant));
    if (next <= current) return;
    await _db.from('cart_items').upsert({'user_id': uid, 'variant_id': variant.id, 'qty': next});
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {} // added; the cart screen shows the reload error with a retry
  }

  Future<void> setQty(String variantId, int qty) => _optimistic(
        (lines) => [for (final l in lines) l.variant.id == variantId ? l.copyWith(qty: qty) : l],
        () => _db.from('cart_items').update({'qty': qty}).eq('variant_id', variantId),
      );

  Future<void> remove(String variantId) => _optimistic(
        (lines) => lines.where((l) => l.variant.id != variantId).toList(),
        () => _db.from('cart_items').delete().eq('variant_id', variantId),
      );

  // Quantity taps go to the server one at a time, in tap order. In parallel they can land out of order (3 after
  // 4), leaving the server cart, which place_order charges, different from the qty and total on screen.
  Future<void> _writes = Future.value();

  /// Completes once the queued quantity writes have reached the server (the quote waits for it).
  Future<void> get settled => _writes;

  Future<void> _optimistic(List<CartLine> Function(List<CartLine>) apply, Future<void> Function() write) async {
    final before = state.value ?? const <CartLine>[];
    state = AsyncData(apply(before));
    final run = _writes.then((_) => write());
    _writes = run.then<void>((_) {}, onError: (Object _) {});
    try {
      await run;
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }
}
