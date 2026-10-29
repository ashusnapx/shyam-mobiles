import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/errors.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/checkout/data/payment.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeApi implements PaymentApi {
  final calls = <String>[];
  Object? placeError;
  Object? createError;
  Object? verifyError;
  Completer<String>? placeGate;
  OrderStatus verifyStatus = OrderStatus.confirmed;
  SheetPaid? verified;
  Map<String, dynamic> payment = {
    'key_id': 'rzp_test_key',
    'razorpay_order_id': 'order_rzp1',
    'amount': 7739700,
    'currency': 'INR',
    'order_number': 'SM100001',
  };

  @override
  Future<String> placeOrder(String addressId, PaymentMethod method) async {
    calls.add('place $addressId ${method.value}');
    if (placeGate != null) return placeGate!.future;
    if (placeError != null) throw placeError!;
    return 'order-1';
  }

  @override
  Future<Map<String, dynamic>> createPayment(String orderId) async {
    calls.add('create $orderId');
    if (createError != null) throw createError!;
    return payment;
  }

  @override
  Future<OrderStatus> verifyPayment(SheetPaid paid) async {
    calls.add('verify');
    verified = paid;
    if (verifyError != null) throw verifyError!;
    return verifyStatus;
  }
}

class FakeSheet implements PaymentSheet {
  FakeSheet(this.result);

  SheetResult result;
  Map<String, dynamic>? options;

  @override
  Future<SheetResult> open(Map<String, dynamic> options) async {
    this.options = options;
    return result;
  }
}

const _paid = SheetPaid(orderId: 'order_rzp1', paymentId: 'pay_1', signature: 'sig_1');

void main() {
  late FakeApi api;
  late FakeSheet sheet;
  late ProviderContainer container;
  late List<PayStage> stages;

  setUp(() {
    api = FakeApi();
    sheet = FakeSheet(_paid);
    container = ProviderContainer(overrides: [
      paymentApiProvider.overrideWithValue(api),
      paymentSheetProvider.overrideWithValue(sheet),
      currentUserProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);
    stages = [];
    container.listen(paymentFlowProvider, (_, s) => stages.add(s));
  });

  PaymentFlow flow() => container.read(paymentFlowProvider.notifier);

  test('COD places the order and never opens the sheet', () async {
    final r = await flow().checkout('addr-1', PaymentMethod.cod);
    expect(r?.orderId, 'order-1');
    expect(r?.payment, isNull);
    expect(api.calls, ['place addr-1 cod']);
    expect(sheet.options, isNull);
    expect(stages, [PayStage.placing, PayStage.idle]);
  });

  test('online: place, create, sheet, verify with the sheet’s ids', () async {
    final r = await flow().checkout('addr-1', PaymentMethod.razorpay);
    expect(r?.payment?.outcome, PayOutcome.paid);
    expect(r?.payment?.message, isNull);
    expect(api.calls, ['place addr-1 razorpay', 'create order-1', 'verify']);
    expect(api.verified, same(_paid));
    expect(sheet.options?['order_id'], 'order_rzp1');
    expect(sheet.options?['amount'], 7739700, reason: 'amount comes from the server response');
    expect(stages, [PayStage.placing, PayStage.starting, PayStage.paying, PayStage.verifying, PayStage.idle]);
  });

  test('verify says cancelled: paid too late', () async {
    api.verifyStatus = OrderStatus.cancelled;
    expect((await flow().pay('order-1'))?.outcome, PayOutcome.paidTooLate);
  });

  test('sheet cancelled (Android back / code 2) or failed: no verify, retry copy', () async {
    sheet.result = const SheetClosed(cancelled: true);
    final cancelled = await flow().pay('order-1');
    expect(cancelled?.outcome, PayOutcome.cancelled);
    expect(cancelled?.message, isNotNull);

    sheet.result = const SheetClosed();
    expect((await flow().pay('order-1'))?.outcome, PayOutcome.failed);
    expect(api.calls.where((c) => c == 'verify'), isEmpty);
    expect(container.read(paymentFlowProvider), PayStage.idle);
  });

  test('no callback from the UPI app / external wallet: unknown', () async {
    sheet.result = const SheetUnknown();
    expect((await flow().pay('order-1'))?.outcome, PayOutcome.unknown);
  });

  test('create-payment refused: unavailable with the server’s reason, sheet not opened', () async {
    api.createError = const FunctionsHttpException(status: 409, details: {'error': 'ORDER_EXPIRED', 'message': 'x'});
    final r = await flow().checkout('addr-1', PaymentMethod.razorpay);
    expect(r?.orderId, 'order-1', reason: 'the order exists, so the caller still goes to its result');
    expect(r?.payment?.outcome, PayOutcome.unavailable);
    expect(r?.payment?.message, friendlyError(api.createError!));
    expect(sheet.options, isNull);
  });

  test('no Razorpay key anywhere: unavailable', () async {
    api.payment = {...api.payment, 'key_id': ''};
    final r = await flow().pay('order-1');
    expect(r?.outcome, PayOutcome.unavailable);
    expect(r?.message, isNotNull);
    expect(sheet.options, isNull);
  });

  test('verify fails after a successful sheet: unverified; quiet on network errors', () async {
    api.verifyError = const FunctionsFetchException(details: 'socket closed');
    final offline = await flow().pay('order-1');
    expect(offline?.outcome, PayOutcome.unverified);
    expect(offline?.message, isNull, reason: 'the webhook still confirms it; the result screen polls');

    api.verifyError = const FunctionsHttpException(
      status: 409,
      details: {'error': 'PAYMENT_MISMATCH', 'message': 'Payment does not match this order. Contact the store.'},
    );
    expect((await flow().pay('order-1'))?.message, friendlyError(api.verifyError!));
  });

  test('place_order error is rethrown and nothing else runs', () async {
    api.placeError = const PostgrestException(message: 'OUT_OF_STOCK', details: 'v1');
    await expectLater(flow().checkout('addr-1', PaymentMethod.razorpay), throwsA(isA<PostgrestException>()));
    expect(api.calls, ['place addr-1 razorpay']);
    expect(container.read(paymentFlowProvider), PayStage.idle);
  });

  test('double tap: a second checkout or pay while one runs is ignored', () async {
    api.placeGate = Completer<String>();
    final first = flow().checkout('addr-1', PaymentMethod.cod);
    expect(await flow().checkout('addr-1', PaymentMethod.cod), isNull);
    expect(await flow().pay('order-1'), isNull);
    api.placeGate!.complete('order-1');
    expect((await first)?.orderId, 'order-1');
    expect(api.calls, ['place addr-1 cod']);
  });

  group('razorpayOptions', () {
    test('uses the server key, amount and order; prefills an E.164 contact', () {
      final o = razorpayOptions(FakeApi().payment, phone: '919876543210', email: 'a@b.in')!;
      expect(o['key'], 'rzp_test_key');
      expect(o['order_id'], 'order_rzp1');
      expect(o['amount'], 7739700);
      expect(o['currency'], 'INR');
      expect(o['name'], 'Shyam Mobiles');
      expect(o['description'], 'Order SM100001');
      expect(o['prefill'], {'contact': '+919876543210', 'email': 'a@b.in'});
      expect(o['theme'], {'color': '#0A0A0A'});
      expect(o['retry'], {'enabled': true});
    });

    test('timeout = seconds left on the stock hold (min 60), only when the server sends it', () {
      final now = DateTime.utc(2026, 10, 29, 12);
      Map<String, dynamic> withHold(Duration left) =>
          {...FakeApi().payment, 'reserved_until': now.add(left).toIso8601String()};
      expect(razorpayOptions(withHold(const Duration(minutes: 14)), now: now)!['timeout'], 840);
      expect(razorpayOptions(withHold(const Duration(seconds: 20)), now: now)!['timeout'], 60);
      expect(razorpayOptions(withHold(const Duration(minutes: -1)), now: now)!['timeout'], 60);
      expect(razorpayOptions(FakeApi().payment, now: now)!.containsKey('timeout'), isFalse);
    });

    test('drops prefill it can’t use; null without an order id or key', () {
      expect(razorpayOptions(FakeApi().payment, phone: '', email: '')!['prefill'], isEmpty);
      expect(razorpayOptions({...FakeApi().payment, 'razorpay_order_id': null}), isNull);
      expect(razorpayOptions({...FakeApi().payment, 'key_id': null}), isNull, reason: 'no RAZORPAY_KEY_ID define in tests');
    });
  });
}
