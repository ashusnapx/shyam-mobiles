import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/checkout/data/payment.dart';
import 'package:shyam_mobiles/features/checkout/screens/checkout_result_screen.dart';
import 'package:shyam_mobiles/features/checkout/screens/checkout_screen.dart';

const _settings = StoreSettings(
  deliveryFeePaise: 4900,
  freeDeliveryMinPaise: 99900,
  codEnabled: true,
  codMaxPaise: 2500000,
  storePhone: '+919999999999',
  storeAddress: '',
  storeHours: '',
  repairNote: '',
);

Order _order(OrderStatus status, {PaymentMethod method = PaymentMethod.razorpay, PaymentStatus pay = PaymentStatus.pending, DateTime? reservedUntil}) =>
    Order(
      id: 'o1',
      number: 'SM100001',
      status: status,
      paymentMethod: method,
      paymentStatus: pay,
      subtotalPaise: 100000,
      deliveryFeePaise: 0,
      totalPaise: 100000,
      address: const Address(name: 'A', phone: '+919999999999', line1: 'L', city: 'C', state: 'S', pincode: '800001'),
      createdAt: DateTime(2026, 10, 27),
      reservedUntil: reservedUntil,
    );

void main() {
  group('checkoutButton', () {
    ({String label, bool enabled}) button({
      PaymentMethod method = PaymentMethod.razorpay,
      bool hasAddress = true,
      bool cartOk = true,
      PayStage stage = PayStage.idle,
    }) =>
        checkoutButton(method: method, totalPaise: 7739700, hasAddress: hasAddress, cartOk: cartOk, stage: stage);

    test('labels by payment method', () {
      expect(button(), (label: 'Pay ₹77,397', enabled: true));
      expect(button(method: PaymentMethod.cod), (label: 'Place order · ₹77,397', enabled: true));
    });

    test('disabled with a reason', () {
      expect(button(cartOk: false), (label: 'Fix your cart to continue', enabled: false));
      expect(button(hasAddress: false), (label: 'Add an address to continue', enabled: false));
    });

    test('busy wins and shows the stage', () {
      expect(button(stage: PayStage.placing), (label: 'Placing order…', enabled: false));
      expect(button(stage: PayStage.verifying, cartOk: false).label, 'Confirming payment…');
    });
  });

  test('codUnavailableReason mirrors place_order', () {
    expect(codUnavailableReason(_settings, 2500000), isNull);
    expect(codUnavailableReason(_settings, 2500001), 'Not available for orders above ₹25,000');
    const off = StoreSettings(
      deliveryFeePaise: 0,
      freeDeliveryMinPaise: 0,
      codEnabled: false,
      codMaxPaise: 2500000,
      storePhone: '',
      storeAddress: '',
      storeHours: '',
      repairNote: '',
    );
    expect(codUnavailableReason(off, 100), 'Not available right now');
  });

  group('resultView', () {
    final later = DateTime.now().add(const Duration(minutes: 10));
    final earlier = DateTime.now().subtract(const Duration(minutes: 1));

    test('paid online or COD confirmed: success', () {
      expect(resultView(_order(OrderStatus.confirmed, pay: PaymentStatus.paid), polling: true), ResultView.success);
      expect(resultView(_order(OrderStatus.confirmed, method: PaymentMethod.cod), polling: false), ResultView.success);
    });

    test('unpaid: wait while polling, then retry inside the hold, else expired', () {
      final o = _order(OrderStatus.pendingPayment, reservedUntil: later);
      expect(resultView(o, polling: true), ResultView.waiting);
      expect(resultView(o, polling: false), ResultView.retry);
      expect(resultView(_order(OrderStatus.pendingPayment, reservedUntil: earlier), polling: false), ResultView.expired);
      expect(
        resultView(_order(OrderStatus.pendingPayment, pay: PaymentStatus.failed, reservedUntil: later), polling: false),
        ResultView.retry,
        reason: 'payment.failed keeps the order payable until expiry',
      );
    });

    test('cancelled, and paid after cancellation', () {
      expect(resultView(_order(OrderStatus.cancelled), polling: true), ResultView.cancelled);
      expect(resultView(_order(OrderStatus.cancelled, pay: PaymentStatus.paid), polling: true), ResultView.refundDue);
    });
  });
}
