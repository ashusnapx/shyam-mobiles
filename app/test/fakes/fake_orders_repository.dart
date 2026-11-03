import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/orders/data/orders_repository.dart';

import 'fake.dart';

/// Seed [orders] (newest first) and [nextQuote]; placeOrder returns [placedId] and records the call.
class FakeOrdersRepository with Fake implements OrdersRepository {
  var orders = <Order>[];
  var nextQuote = const Quote(subtotalPaise: 0, deliveryFeePaise: 0, discountPaise: 0, totalPaise: 0);
  var dashboardTiles = <String, int>{};
  String placedId = 'o1';
  final updates = <({String orderId, OrderStatus status, String? note, String? courier, String? tracking})>[];
  final imeis = <String, List<String>>{}; // "orderId/itemId" → imeis

  @override
  Future<Quote> quote({String? couponCode, PaymentMethod? method}) async {
    record('quote ${couponCode ?? '-'} ${method?.value ?? '-'}');
    return nextQuote;
  }

  @override
  Future<String> placeOrder(String addressId, PaymentMethod method, {String? couponCode}) async {
    record('placeOrder $addressId ${method.value} ${couponCode ?? '-'}');
    return placedId;
  }

  @override
  Future<List<Order>> myOrders(String uid, int from, int size) async {
    record('myOrders $uid $from');
    return pageOf(orders, from, size);
  }

  @override
  Future<Order> order(String id) async {
    record('order $id');
    return orders.where((o) => o.id == id).firstOrNull ?? (throw reason('NOT_FOUND'));
  }

  @override
  Future<void> cancel(String orderId) async => record('cancel $orderId');

  @override
  Future<List<Order>> adminOrders(String filter, int from, int size) async {
    record('adminOrders $filter $from');
    final hits = filter == 'all' ? orders : orders.where((o) => o.status.value == filter).toList();
    return pageOf(hits, from, size);
  }

  @override
  Future<List<Order>> toFulfil() async {
    record('toFulfil');
    return orders.where((o) => o.status == OrderStatus.confirmed || o.status == OrderStatus.packed).toList();
  }

  @override
  Future<Map<String, int>> dashboard() async {
    record('dashboard');
    return dashboardTiles;
  }

  @override
  Future<void> updateOrder(String orderId, OrderStatus status, {String? note, String? courier, String? tracking}) async {
    record('updateOrder $orderId ${status.value}');
    updates.add((orderId: orderId, status: status, note: note, courier: courier, tracking: tracking));
  }

  @override
  Future<void> setImeis(String orderId, String itemId, List<String> imeis) async {
    record('setImeis $orderId $itemId');
    this.imeis['$orderId/$itemId'] = [...imeis];
  }
}
