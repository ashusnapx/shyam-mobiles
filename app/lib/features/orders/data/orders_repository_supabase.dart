import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../repairs/data/booking_days.dart' show istMidnight;
import 'orders_repository.dart';

/// Today's RPCs and queries (RLS: the customer's own orders, staff everything). Deleted in Phase 2.
class SupabaseOrdersRepository implements OrdersRepository {
  const SupabaseOrdersRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Quote> quote({String? couponCode, PaymentMethod? method}) async => Quote.fromJson(await _db
      .rpc<Map<String, dynamic>>('quote_order', params: {'p_coupon_code': couponCode, 'p_payment_method': method?.value}));

  @override
  Future<String> placeOrder(String addressId, PaymentMethod method, {String? couponCode}) async => await _db.rpc<String>(
      'place_order', params: {'p_address_id': addressId, 'p_payment_method': method.value, 'p_coupon_code': couponCode});

  @override
  Future<List<Order>> myOrders(String uid, int from, int size) async => [
        // filtered by user_id: RLS also lets admins read everyone's
        for (final r in await _db
            .from('orders')
            .select('*, items:order_items(*)')
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .range(from, from + size - 1))
          Order.fromJson(r),
      ];

  @override
  Future<Order> order(String id) async {
    final row = await _db.from('orders').select('*, items:order_items(*), events:order_events(*)').eq('id', id).maybeSingle();
    if (row == null) throw const PostgrestException(message: 'NOT_FOUND');
    return Order.fromJson(row);
  }

  @override
  Future<void> cancel(String orderId) => _db.rpc<void>('cancel_order', params: {'p_order_id': orderId});

  @override
  Future<List<Order>> adminOrders(String filter, int from, int size) async {
    var q = _db.from('orders').select('*, items:order_items(*)');
    q = switch (filter) {
      'all' => q,
      'open' => q.inFilter('status', ['confirmed', 'packed', 'shipped']),
      'needs_refund' => q.eq('status', 'cancelled').eq('payment_status', 'paid'),
      // the dashboard's "Orders today": placed since IST midnight and not unpaid or cancelled
      'today' => q.gte('created_at', istMidnight().toIso8601String()).inFilter('status', ['confirmed', 'packed', 'shipped', 'delivered']),
      _ => q.eq('status', filter),
    };
    // id breaks created_at ties, so no order repeats or goes missing between pages
    final rows = await q.order('created_at', ascending: false).order('id').range(from, from + size - 1);
    return [for (final r in rows) Order.fromJson(r)];
  }

  @override
  Future<List<Order>> toFulfil() async => [
        for (final r in await _db
            .from('orders')
            .select('*, items:order_items(*)')
            .inFilter('status', ['confirmed', 'packed'])
            .order('created_at')
            .limit(30))
          Order.fromJson(r),
      ];

  @override
  Future<Map<String, int>> dashboard() async =>
      {for (final e in (await _db.rpc<Map<String, dynamic>>('admin_dashboard')).entries) e.key: (e.value as num).toInt()};

  @override
  Future<void> updateOrder(String orderId, OrderStatus status, {String? note, String? courier, String? tracking}) =>
      _db.rpc<void>('admin_update_order', params: {
        'p_order_id': orderId,
        'p_status': status.value,
        'p_note': note,
        'p_courier': courier,
        'p_tracking_number': tracking,
      });

  @override
  Future<void> setImeis(String orderId, String itemId, List<String> imeis) =>
      _db.rpc<void>('admin_set_imeis', params: {'p_order_item_id': itemId, 'p_imeis': imeis});
}
