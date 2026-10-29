import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/orders/data/orders.dart';

final _t0 = DateTime.utc(2026, 10, 27, 13);

Order _order(OrderStatus status, List<(OrderStatus, String?)> events, {PaymentMethod method = PaymentMethod.razorpay}) => Order(
      id: 'o1',
      number: 'SM100001',
      status: status,
      paymentMethod: method,
      paymentStatus: PaymentStatus.pending,
      subtotalPaise: 100000,
      deliveryFeePaise: 0,
      totalPaise: 100000,
      address: const Address(name: 'A', phone: '+919999999999', line1: 'L', city: 'C', state: 'S', pincode: '800001'),
      createdAt: _t0,
      events: [
        for (final (i, (s, note)) in events.indexed)
          OrderEvent(status: s, note: note, createdAt: _t0.add(Duration(hours: i))),
      ],
    );

List<(String, bool, String?)> _view(Order o) => [for (final s in buildTimeline(o)) (s.title, s.done, s.note)];

void main() {
  test('COD just placed: confirmed, then the rest greyed', () {
    final o = _order(OrderStatus.confirmed, [(OrderStatus.confirmed, null)], method: PaymentMethod.cod);
    expect(_view(o), [
      ('Order confirmed', true, null),
      ('Packed', false, null),
      ('Shipped', false, null),
      ('Delivered', false, 'Usually 2–4 days after shipping'),
    ]);
  });

  test('unpaid online order shows every happy-path step ahead', () {
    final o = _order(OrderStatus.pendingPayment, [(OrderStatus.pendingPayment, null)]);
    expect(_view(o).map((s) => s.$1), ['Order placed', 'Order confirmed', 'Packed', 'Shipped', 'Delivered']);
    expect(_view(o).where((s) => s.$2).length, 1);
  });

  test('shipped: past events keep their notes and times, one step left', () {
    final o = _order(OrderStatus.shipped, [
      (OrderStatus.pendingPayment, null),
      (OrderStatus.confirmed, 'Payment received'),
      (OrderStatus.packed, null),
      (OrderStatus.packed, 'IMEI recorded'),
      (OrderStatus.shipped, null),
    ]);
    final steps = buildTimeline(o);
    expect(_view(o), [
      ('Order placed', true, null),
      ('Order confirmed', true, 'Payment received'),
      ('Packed', true, null),
      ('IMEI recorded', true, null), // a note on the same status becomes its own entry
      ('Shipped', true, null),
      ('Delivered', false, 'Usually 2–4 days after shipping'),
    ]);
    expect(steps[1].at, _t0.add(const Duration(hours: 1)));
  });

  test('cancelled or refunded: no future steps, server notes shown', () {
    const refundNote = 'Cancelled by you. A full refund to your original payment method is on its way; banks usually take 5–7 working days.';
    final cancelled = _order(OrderStatus.cancelled, [(OrderStatus.confirmed, 'Payment received'), (OrderStatus.cancelled, refundNote)]);
    expect(_view(cancelled), [('Order confirmed', true, 'Payment received'), ('Cancelled', true, refundNote)]);

    final refunded = _order(OrderStatus.refunded, [
      (OrderStatus.confirmed, null),
      (OrderStatus.delivered, null),
      (OrderStatus.refunded, null),
      (OrderStatus.refunded, 'Refund issued. Banks usually take 5–7 working days to show it.'),
    ]);
    expect(_view(refunded).last, ('Refund issued. Banks usually take 5–7 working days to show it.', true, null));
    expect(_view(refunded).every((s) => s.$2), isTrue);
  });

  test('no events yet still renders the steps ahead', () {
    expect(buildTimeline(_order(OrderStatus.delivered, [])), isEmpty);
    expect(buildTimeline(_order(OrderStatus.packed, [])).map((s) => s.title), ['Shipped', 'Delivered']);
  });
}
