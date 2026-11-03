import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/callable.dart';
import '../../../core/models/models.dart';
import '../../repairs/data/booking_days.dart' show istMidnight;
import 'orders_repository.dart';
import 'snake.dart';

/// orders/{id} as the app's Order (functions/src/model/orders.ts). Items are keyed by variant id.
Order orderFromDoc(String id, Map<String, dynamic> d) {
  DateTime? at(Object? v) => (v as Timestamp?)?.toDate();
  int paise(String k) => (d[k] as num?)?.toInt() ?? 0;
  final a = Map<String, dynamic>.from(d['address'] as Map);
  return Order(
    id: id,
    number: d['number'] as String,
    userId: d['uid'] as String?,
    status: OrderStatus.parse(d['status'] as String),
    paymentMethod: d['paymentMethod'] == 'cod' ? PaymentMethod.cod : PaymentMethod.razorpay, // razorpay = "Pay online"
    paymentStatus: PaymentStatus.parse(d['paymentStatus'] as String),
    subtotalPaise: paise('subtotalPaise'),
    deliveryFeePaise: paise('deliveryFeePaise'),
    discountPaise: paise('discountPaise'),
    totalPaise: paise('totalPaise'),
    couponCode: d['couponCode'] as String?,
    address: Address(
      name: a['name'] as String, phone: a['phone'] as String, line1: a['line1'] as String, line2: a['line2'] as String?,
      landmark: a['landmark'] as String?, city: a['city'] as String, district: a['district'] as String?,
      state: a['state'] as String, pincode: a['pincode'] as String),
    courier: d['courier'] as String?,
    trackingNumber: d['trackingNumber'] as String?,
    reservedUntil: at(d['reservedUntil']),
    createdAt: at(d['createdAt']) ?? DateTime.now(),
    items: [
      for (final i in (d['items'] as List? ?? const []).cast<Map>())
        OrderItem(
          id: i['id'] as String, variantId: i['id'] as String, productId: i['productId'] as String?,
          productName: i['productName'] as String, variantName: i['variantName'] as String, imagePath: i['imagePath'] as String?,
          unitPricePaise: (i['unitPricePaise'] as num).toInt(), qty: (i['qty'] as num).toInt(),
          imeis: [...(i['imeis'] as List? ?? const [])].cast<String>()),
    ],
    events: [
      for (final e in (d['events'] as List? ?? const []).cast<Map>())
        OrderEvent(status: OrderStatus.parse(e['status'] as String), note: e['note'] as String?, createdAt: at(e['at']) ?? DateTime.now()),
    ],
  );
}

const _paid = ['confirmed', 'packed', 'shipped', 'delivered'];
const _open = ['confirmed', 'packed', 'shipped'];

/// Callables for every change (functions/src/orders), Firestore reads under Rules for the rest.
class FirebaseOrdersRepository implements OrdersRepository {
  const FirebaseOrdersRepository(this._db, this._fn);

  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  CollectionReference<Map<String, dynamic>> get _orders => _db.collection('orders');

  static String _method(PaymentMethod m) => m == PaymentMethod.cod ? 'cod' : 'online';

  // shortcut: Firestore has no offset, so page n reads the n−1 pages before it too; fine at shop volume, use
  // startAfterDocument cursors if order lists grow past a few hundred.
  Future<List<Order>> _page(Query<Map<String, dynamic>> q, int from, int size) async =>
      [for (final d in (await q.limit(from + size).get()).docs.skip(from)) orderFromDoc(d.id, d.data())];

  @override
  Future<Quote> quote({String? couponCode, PaymentMethod? method}) async => Quote.fromJson(snakeMap(await callFunction(
      _fn, 'quoteOrder', {'couponCode': couponCode, 'paymentMethod': method == null ? null : _method(method)})));

  @override
  Future<String> placeOrder(String addressId, PaymentMethod method, {String? couponCode}) async => (await callFunction(
          _fn, 'placeOrder', {'addressId': addressId, 'paymentMethod': _method(method), 'couponCode': couponCode}, true))['orderId']
      as String;

  @override
  Future<List<Order>> myOrders(String uid, int from, int size) =>
      _page(_orders.where('uid', isEqualTo: uid).orderBy('createdAt', descending: true), from, size);

  @override
  Future<Order> order(String id) async {
    final d = await _orders.doc(id).get();
    if (!d.exists) throw FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND', details: const {'reason': 'NOT_FOUND'});
    return orderFromDoc(d.id, d.data()!);
  }

  @override
  Future<void> cancel(String orderId) => callFunction(_fn, 'cancelOrder', {'orderId': orderId});

  @override
  Future<List<Order>> adminOrders(String filter, int from, int size) {
    final q = switch (filter) {
      'all' => _orders,
      'open' => _orders.where('status', whereIn: _open),
      'needs_refund' => _orders.where('status', isEqualTo: 'cancelled').where('paymentStatus', isEqualTo: 'paid'),
      'today' => _orders.where('status', whereIn: _paid).where('createdAt', isGreaterThanOrEqualTo: istMidnight()),
      _ => _orders.where('status', isEqualTo: filter),
    };
    return _page(q.orderBy('createdAt', descending: true), from, size);
  }

  @override
  Future<List<Order>> toFulfil() async {
    final list = await _page(_orders.where('status', whereIn: ['confirmed', 'packed']).orderBy('createdAt'), 0, 30);
    return list..sort((a, b) => a.status.index.compareTo(b.status.index)); // packing comes before shipping
  }

  /// admin_dashboard's tiles from aggregation queries and catalogIndex/staff (one read for low stock).
  @override
  Future<Map<String, int>> dashboard() async {
    final today = _orders.where('status', whereIn: _paid).where('createdAt', isGreaterThanOrEqualTo: istMidnight());
    final openRepairs = _db.collection('repairs').where('status', whereIn: ['requested', 'confirmed', 'in_progress', 'ready']);
    final (t, open, refund, repairs, quotes, index) = await (
      today.aggregate(count(), sum('totalPaise')).get(),
      _orders.where('status', whereIn: _open).count().get(),
      _orders.where('status', isEqualTo: 'cancelled').where('paymentStatus', isEqualTo: 'paid').count().get(),
      openRepairs.count().get(),
      openRepairs.where('quote.status', isEqualTo: 'pending').count().get(),
      _db.doc('catalogIndex/staff').get(),
    ).wait;
    final cards = (index.data()?['cards'] as Map? ?? const {}).values.cast<Map>();
    return {
      'orders_today': t.count ?? 0,
      'revenue_today_paise': (t.getSum('totalPaise') ?? 0).toInt(),
      'open_orders': open.count ?? 0,
      'needs_refund': refund.count ?? 0,
      'low_stock': cards
          .where((c) => c['active'] == true && (c['variants'] as List? ?? const []).any((v) => v[6] == true && (v[5] as num) <= 3))
          .length,
      'open_repairs': repairs.count ?? 0,
      'repairs_awaiting_approval': quotes.count ?? 0,
    };
  }

  @override
  Future<void> updateOrder(String orderId, OrderStatus status, {String? note, String? courier, String? tracking}) =>
      callFunction(_fn, 'adminUpdateOrder',
          {'orderId': orderId, 'status': status.value, 'note': note, 'courier': courier, 'trackingNumber': tracking});

  @override
  Future<void> setImeis(String orderId, String itemId, List<String> imeis) =>
      callFunction(_fn, 'adminSetImeis', {'orderId': orderId, 'itemId': itemId, 'imeis': imeis});
}
