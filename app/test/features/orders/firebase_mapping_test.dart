import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/orders/data/orders_repository_firebase.dart';
import 'package:shyam_mobiles/features/orders/data/snake.dart';

// The Firebase docs and callable replies (functions/src/model/orders.ts, orders/contract.ts) map onto today's models.
void main() {
  final at = Timestamp.fromDate(DateTime.utc(2026, 11, 3, 6, 30));

  test('an order doc becomes an Order: online is "Pay online", items keyed by variant id, events by time', () {
    final o = orderFromDoc('o1', {
      'number': 'SM100001', 'uid': 'alice', 'status': 'pending_payment', 'paymentMethod': 'online', 'paymentStatus': 'pending',
      'subtotalPaise': 50000, 'deliveryFeePaise': 4900, 'discountPaise': 0, 'totalPaise': 54900, 'reservedUntil': at, 'createdAt': at,
      'address': {'name': 'Alice', 'phone': '+919876543210', 'line1': '1 MG Road', 'city': 'Waidhan', 'state': 'Madhya Pradesh', 'stateCode': '23', 'pincode': '486886'},
      'items': [
        {'id': 'v1', 'productId': 'phone', 'productName': 'Phone', 'variantName': '8 GB', 'unitPricePaise': 50000, 'qty': 1, 'gstRateBp': 1800, 'discountPaise': 0, 'imeis': <String>[]},
      ],
      'events': [{'status': 'pending_payment', 'by': 'customer', 'at': at}],
    });
    expect((o.number, o.paymentMethod, o.totalPaise, o.canCancel), ('SM100001', PaymentMethod.razorpay, 54900, true));
    expect((o.items.single.id, o.items.single.variantId, o.events.single.createdAt), ('v1', 'v1', at.toDate()));
    expect(o.reservedUntil, at.toDate());
  });

  test('a quote reply and an offer doc parse through snakeMap', () {
    final q = Quote.fromJson(snakeMap({
      'subtotalPaise': 100000, 'deliveryFeePaise': 0, 'discountPaise': 10000, 'totalPaise': 90000,
      'promotion': {'id': 'p1', 'title': 'Welcome', 'code': 'WELCOME', 'kind': 'flat'}, 'couponError': 'COUPON_BETTER_OFFER', 'couponErrorDetail': null,
    }));
    expect((q.totalPaise, q.discountLabel, q.couponError), (90000, 'WELCOME', 'COUPON_BETTER_OFFER'));
    final offer = Offer.fromJson({...snakeMap({'title': 'Sale', 'description': '', 'code': null, 'kind': 'percent', 'value': 10,
      'minSubtotalPaise': 0, 'appliesTo': 'order', 'startsAt': at, 'endsAt': null, 'onlineOnly': false, 'firstOrderOnly': false}, 'p2'), 'automatic': true});
    expect((offer.id, offer.code, offer.minSubtotalPaise), ('p2', null, 0));
    expect(camelMap({'min_subtotal_paise': 1, 'is_active': true}), {'minSubtotalPaise': 1, 'isActive': true});
  });
}
