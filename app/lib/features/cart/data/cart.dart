import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart';

const _select =
    'qty, variant:variants(*, product:products(id, slug, name, is_active, images:product_images(path, sort)))';

/// Most of one variant a customer can hold in the cart (DB check allows 1..5).
int maxQtyFor(Variant v) => math.min(v.stock, 5);

final cartProvider = AsyncNotifierProvider<CartNotifier, List<CartLine>>(CartNotifier.new);

final cartCountProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).value?.fold<int>(0, (sum, l) => sum + l.qty) ?? 0,
);

class CartNotifier extends AsyncNotifier<List<CartLine>> {
  SupabaseClient get _db => ref.read(supabaseProvider);

  @override
  Future<List<CartLine>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const [];
    final rows = await _db.from('cart_items').select(_select).order('created_at');
    return [for (final r in rows) CartLine.fromJson(r)];
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
    await future;
  }

  Future<void> setQty(String variantId, int qty) => _optimistic(
        (lines) => [for (final l in lines) l.variant.id == variantId ? l.copyWith(qty: qty) : l],
        () => _db.from('cart_items').update({'qty': qty}).eq('variant_id', variantId),
      );

  Future<void> remove(String variantId) => _optimistic(
        (lines) => lines.where((l) => l.variant.id != variantId).toList(),
        () => _db.from('cart_items').delete().eq('variant_id', variantId),
      );

  Future<void> _optimistic(List<CartLine> Function(List<CartLine>) apply, Future<void> Function() write) async {
    final before = state.value ?? const <CartLine>[];
    state = AsyncData(apply(before));
    try {
      await write();
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }
}
