import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import 'cart_repository.dart';

const _select =
    'qty, variant_id, variant:variants(*, product:products(id, slug, name, is_active, images:product_images(path, sort)))';

/// Today's cart_items queries (RLS: the caller's own rows). Deleted in Phase 2.
class SupabaseCartRepository implements CartRepository {
  const SupabaseCartRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<({List<CartLine> lines, List<String> hidden})> load(String uid) async {
    final rows = await _db.from('cart_items').select(_select).order('created_at');
    // A line whose item the shop hid comes back without its variant (RLS).
    return (
      lines: [for (final r in rows) if (r['variant'] != null) CartLine.fromJson(r)],
      hidden: [for (final r in rows) if (r['variant'] == null) r['variant_id'] as String],
    );
  }

  @override
  Future<void> put(String uid, String variantId, int qty) =>
      _db.from('cart_items').upsert({'user_id': uid, 'variant_id': variantId, 'qty': qty});

  @override
  Future<void> remove(String uid, List<String> variantIds) =>
      _db.from('cart_items').delete().inFilter('variant_id', variantIds);
}
