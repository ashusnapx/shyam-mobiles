import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import 'orders_repository_firebase.dart';
import 'orders_repository_supabase.dart';

/// Checkout and orders, the customer's and the staff side (docs/FIREBASE.md §5). The app never sends a price: the
/// server prices the cart. Errors carry today's reason codes (OUT_OF_STOCK, COUPON_*, PENDING_LIMIT…). Owner: C.
abstract interface class OrdersRepository {
  /// The server's price of the caller's cart. A refused [couponCode] comes back in Quote.couponError, not a throw.
  Future<Quote> quote({String? couponCode, PaymentMethod? method});

  /// Places the order from the server cart; returns its id.
  Future<String> placeOrder(String addressId, PaymentMethod method, {String? couponCode});

  /// The customer's orders, newest first, rows [from]..[from + size − 1].
  Future<List<Order>> myOrders(String uid, int from, int size);

  /// One order with its items and timeline (the customer's own, or any for staff). NOT_FOUND when missing.
  Future<Order> order(String id);

  /// The customer cancels while pending payment or confirmed.
  Future<void> cancel(String orderId);

  // Staff ------------------------------------------------------------------------------------------------------

  /// [filter]: a status value, or `all`, `today`, `open`, `needs_refund` (admin.dart orderFilters). Newest first.
  Future<List<Order>> adminOrders(String filter, int from, int size);

  /// Confirmed orders to pack and packed ones to ship, oldest first (≤ 30).
  Future<List<Order>> toFulfil();

  /// The dashboard tiles: orders_today, revenue_today_paise, open_orders, low_stock, open_repairs, needs_refund…
  Future<Map<String, int>> dashboard();

  /// One step forward, a cancel, or (same status) a courier/tracking edit with [note] on the timeline.
  Future<void> updateOrder(String orderId, OrderStatus status, {String? note, String? courier, String? tracking});

  /// The IMEIs of one line: exactly qty distinct 15-digit values, or [] to clear (INVALID_IMEIS).
  Future<void> setImeis(String orderId, String itemId, List<String> imeis);
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) => backend == Backend.firebase
    ? FirebaseOrdersRepository(ref.watch(firestoreProvider), ref.watch(functionsProvider))
    : SupabaseOrdersRepository(ref.watch(supabaseProvider)));
