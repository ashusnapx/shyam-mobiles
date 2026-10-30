// Payments at 360x800 dp with 1.4x text (layout_harness.dart): EMI on the product page, staff refunds and payment
// links, the customer's refunds; plus the EMI maths and the refund rules the screens follow.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/format.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/checkout/data/payment.dart';
import 'package:shyam_mobiles/features/payments/data/emi.dart';
import 'package:shyam_mobiles/features/payments/data/payments.dart';
import 'package:shyam_mobiles/features/payments/screens/admin_payment_links_screen.dart';
import 'package:shyam_mobiles/features/payments/widgets/admin_payments.dart';
import 'package:shyam_mobiles/features/payments/widgets/emi_line.dart';
import 'package:shyam_mobiles/features/payments/widgets/order_refunds.dart';

import '../repairs/layout_harness.dart';

const _plans = [
  EmiPlan(bank: 'HDFC', name: 'HDFC Bank', months: 3, rate: 15, minPaise: 300000),
  EmiPlan(bank: 'HDFC', name: 'HDFC Bank', months: 12, rate: 0, minPaise: 1000000, noCost: true),
  EmiPlan(bank: 'KKBK', name: 'Kotak Mahindra Bank', months: 6, rate: 13.5, minPaise: 300000),
];

Order _order(OrderStatus status, {PaymentStatus pay = PaymentStatus.paid, PaymentMethod method = PaymentMethod.razorpay}) => Order(
      id: 'o1',
      number: 'SM100031',
      status: status,
      paymentMethod: method,
      paymentStatus: pay,
      subtotalPaise: 9500000,
      deliveryFeePaise: 4900,
      discountPaise: 500000,
      totalPaise: 9004900,
      address: const Address(name: 'Asha Verma', phone: '+919876543210', line1: '12B', city: 'Waidhan', state: 'MP', pincode: '486886'),
      createdAt: DateTime(2026, 10, 29, 18, 42),
    );

const _lines = [
  RefundLine(id: 'i1', name: 'Samsung Galaxy S25 Ultra 5G · 12 GB · 256 GB · Titanium Silverblue', qty: 1, paidPaise: 7000000),
  RefundLine(id: 'i2', name: 'Samsung 45W Super Fast Charger with a very long accessory name', qty: 2, paidPaise: 2000000),
];

Refund _refund(RefundStatus s, int paise, {List<String> items = const [], bool full = false}) =>
    Refund(id: 'r$paise', amountPaise: paise, full: full, status: s, createdAt: DateTime(2026, 10, 30, 11), items: items);

PaymentLink _link(String status, {DateTime? until}) => PaymentLink(
      id: 'l-$status',
      orderId: null,
      amountPaise: 2500000,
      description: '10 × Redmi 13C 5G, wholesale for the Baidhan market',
      customerName: 'Ravi Traders and Mobile Accessories',
      customerPhone: '+919812345678',
      status: status,
      shortUrl: 'https://rzp.io/rzp/abc123',
      expiresAt: until ?? DateTime.now().add(const Duration(days: 2)),
    );

void main() {
  group('EMI maths', () {
    test('reducing-balance EMI to the rupee; no-cost splits the price', () {
      expect(const EmiPlan(bank: 'X', name: 'X', months: 12, rate: 12, minPaise: 0).monthlyPaise(10000000), 888500,
          reason: '₹1,00,000 at 12% for a year is ₹8,884.88 a month');
      expect(_plans[1].monthlyPaise(2499900), 208300, reason: '₹24,999 / 12 = ₹2,083.25');
    });

    test('the cheapest plan the price qualifies for; none below every minimum', () {
      final offer = emiOffer(_plans, 2499900)!;
      expect((offer.monthlyPaise, offer.months, offer.noCost, offer.plans.length), (208300, 12, true, 3));
      final small = emiOffer(_plans, 500000)!;
      expect((small.months, small.noCost, small.plans.length), (6, false, 2), reason: 'no-cost needs ₹10,000');
      expect(emiOffer(_plans, 299900), isNull);
      expect(emiOffer(const [], 2499900), isNull);
    });
  });

  group('refund rules', () {
    test('what is left, and which refunds staff may start', () {
      expect(refundablePaise(_order(OrderStatus.delivered), [_refund(RefundStatus.processed, 2000000), _refund(RefundStatus.failed, 7000000)]),
          7004900);
      expect(refundChoices(_order(OrderStatus.delivered), const []), (full: true, items: true));
      expect(refundChoices(_order(OrderStatus.packed), const []), (full: false, items: true));
      expect(refundChoices(_order(OrderStatus.cancelled), const []), (full: true, items: false));
      expect(refundChoices(_order(OrderStatus.delivered), [_refund(RefundStatus.pending, 100)]), (full: false, items: false),
          reason: 'one refund at a time');
      expect(refundChoices(_order(OrderStatus.delivered, method: PaymentMethod.cod), const []), (full: false, items: false));
      expect(canSendLink(_order(OrderStatus.confirmed, pay: PaymentStatus.pending, method: PaymentMethod.cod)), isTrue);
      expect(canSendLink(_order(OrderStatus.confirmed)), isFalse);
      expect(canSendLink(_order(OrderStatus.cancelled, pay: PaymentStatus.pending)), isFalse);
    });

    test('WhatsApp text for a link, and Checkout gets the saved-cards customer', () {
      final until = DateTime(2026, 11, 2, 15, 30);
      expect(paymentLinkText(_link('created', until: until)),
          'Hi Ravi, here’s your Shyam Mobiles payment link for 10 × Redmi 13C 5G, wholesale for the Baidhan market: ₹25,000.\n'
          'Pay by UPI, card or netbanking. It works until ${formatDateTime(until)}.\nhttps://rzp.io/rzp/abc123');
      final options = razorpayOptions({'key_id': 'rzp_test_x', 'razorpay_order_id': 'order_1', 'customer_id': 'cust_1'})!;
      expect((options['customer_id'], options['remember_customer']), ('cust_1', true));
      expect(razorpayOptions({'key_id': 'rzp_test_x', 'razorpay_order_id': 'order_1', 'customer_id': null})!.containsKey('customer_id'), isFalse);
    });
  });

  testWidgets('EmiLine: from the cheapest plan, no-cost flagged, tap for every bank; hidden below the minimum', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(body: Column(children: [EmiLine(pricePaise: 2499900), EmiLine(pricePaise: 100000)])),
      overrides: [emiPlansProvider.overrideWith((ref) async => _plans)],
    );
    expect(find.text('EMI from ₹2,083/month · No-cost EMI available'), findsOneWidget);
    expect(find.textContaining('EMI from'), findsOneWidget, reason: '₹1,000 is below every minimum');
    await tester.tap(find.textContaining('EMI from'));
    await tester.pumpAndSettle();
    expect(find.text('EMI on ₹24,999'), findsOneWidget);
    expect(find.text('Kotak Mahindra Bank'), findsOneWidget);
    expect(find.text('No-cost'), findsOneWidget);
    expect(find.text('15% a year'), findsOneWidget);
    expect(find.text('13.5% a year'), findsOneWidget);
  });

  testWidgets('EmiLine takes no space when EMI is off or the plans fail', (tester) async {
    await pumpScreen(tester, const Scaffold(body: EmiLine(pricePaise: 2499900)),
        overrides: [emiPlansProvider.overrideWith((ref) async => throw Exception('offline'))]);
    expect(tester.getSize(find.byType(EmiLine)), Size.zero);
  });

  testWidgets('staff: refund items with restock and instant, confirm with the safe choice on the right', (tester) async {
    final order = _order(OrderStatus.delivered);
    await pumpScreen(tester, Scaffold(body: ListView(children: [OrderPaymentsSection(order: order)])), overrides: [
      orderPaymentsProvider.overrideWith((ref, id) async => (
            lines: _lines,
            refunds: [_refund(RefundStatus.failed, 2000000, items: ['Charger'])],
            links: <PaymentLink>[],
            disputes: [Dispute(id: 'disp_1', amountPaise: 9004900, status: 'open', reason: 'Card holder says they didn’t buy it',
                respondBy: DateTime(2026, 11, 6, 16))],
          )),
    ]);
    expect(find.textContaining('Dispute: ₹90,049, open'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    await tester.tap(find.text('Refund ₹90,049'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Some items'));
    await tester.pumpAndSettle();
    expect(find.text('Pick what to refund'), findsOneWidget);
    await tester.tap(find.textContaining('Samsung 45W'));
    await tester.pump();
    await tester.ensureVisible(find.text('Instant refund'));
    await tester.tap(find.text('Instant refund'));
    await tester.pump();
    await tester.ensureVisible(find.text('Refund ₹20,000'));
    await tester.tap(find.text('Refund ₹20,000'));
    await tester.pumpAndSettle();
    expect(find.text('Refund ₹20,000?'), findsOneWidget);
    final keep = tester.getCenter(find.text('Don’t refund'));
    final go = tester.getCenter(find.widgetWithText(TextButton, 'Refund ₹20,000'));
    expect(keep.dx > go.dx, isTrue, reason: 'safe choice filled, on the right');
    await tester.tap(find.text('Don’t refund'));
    await tester.pumpAndSettle();
  });

  testWidgets('staff: an unpaid COD order offers a payment link', (tester) async {
    final order = _order(OrderStatus.confirmed, pay: PaymentStatus.pending, method: PaymentMethod.cod);
    await pumpScreen(tester, Scaffold(body: ListView(children: [OrderPaymentsSection(order: order)])), overrides: [
      orderPaymentsProvider.overrideWith((ref, id) async =>
          (lines: _lines, refunds: <Refund>[], links: [_link('expired', until: DateTime(2026, 10, 1))], disputes: <Dispute>[])),
    ]);
    expect(find.text('Send payment link'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.textContaining('Refund'), findsNothing);
  });

  testWidgets('customer: refunds on the order, by status', (tester) async {
    await pumpScreen(tester, const Scaffold(body: SingleChildScrollView(child: OrderRefunds(orderId: 'o1'))), overrides: [
      orderRefundsProvider.overrideWith((ref, id) async => [
            _refund(RefundStatus.processed, 2000000, items: ['Samsung 45W Super Fast Charger with a very long accessory name']),
            _refund(RefundStatus.pending, 7004900, full: true),
          ]),
    ]);
    expect(find.text('Refund of ₹70,049'), findsOneWidget);
    expect(find.text('On its way'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);
  });

  testWidgets('staff: payment links list and the new-link form', (tester) async {
    await pumpScreen(tester, const AdminPaymentLinksScreen(), overrides: [
      paymentLinksProvider.overrideWith((ref) async => [_link('created'), _link('paid'), _link('cancelled')]),
    ]);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    await tester.tap(find.text('New link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make link and send on WhatsApp'));
    await tester.pump();
    expect(find.text('₹1 to ₹50,00,000'), findsOneWidget);
    expect(find.text('A 10-digit mobile number'), findsOneWidget);
  });
}
