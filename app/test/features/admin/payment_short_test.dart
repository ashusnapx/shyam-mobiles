// Admin's order lists: a cancelled online order whose payment never came says Not paid, not Pending.
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/widgets/admin_widgets.dart';

Order _order(OrderStatus status, PaymentStatus pay, {PaymentMethod method = PaymentMethod.razorpay}) => Order(
      id: 'o1',
      number: 'SM100002',
      status: status,
      paymentMethod: method,
      paymentStatus: pay,
      subtotalPaise: 149900,
      deliveryFeePaise: 0,
      totalPaise: 134910,
      address: const Address(
          id: 'a1', name: 'Uu', phone: '+916669999999', line1: 'Main Road', city: 'Waidhan', state: 'MP', pincode: '486886'),
      createdAt: DateTime(2026, 10, 31),
    );

void main() {
  test('payment in the admin lists', () {
    expect(paymentShort(_order(OrderStatus.cancelled, PaymentStatus.pending)), 'Not paid');
    expect(paymentShort(_order(OrderStatus.pendingPayment, PaymentStatus.pending)), 'Pending');
    expect(paymentShort(_order(OrderStatus.cancelled, PaymentStatus.paid)), 'Paid', reason: 'paid, then cancelled: a refund is due');
    expect(paymentShort(_order(OrderStatus.cancelled, PaymentStatus.failed)), 'Failed');
    expect(paymentShort(_order(OrderStatus.cancelled, PaymentStatus.pending, method: PaymentMethod.cod)), 'COD');
  });
}
