import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/checkout/data/payment.dart';
import 'package:shyam_mobiles/features/payments/data/emi.dart';
import 'package:shyam_mobiles/features/payments/data/payment_gateway.dart';
import 'package:shyam_mobiles/features/payments/data/payments_repository.dart';

class FakePaymentsRepository implements PaymentsRepository {
  final calls = <String>[];
  Exception? createError;
  Exception? checkError;
  Map<String, dynamic> start = {'merchantId': 'PPMERCHANT', 'token': 'tok1', 'orderId': 'OMO1', 'env': 'SANDBOX'};
  Map<String, dynamic> check = {'status': 'confirmed', 'paymentStatus': 'paid'};

  @override
  Future<Map<String, dynamic>> createPayment(String orderId) async {
    calls.add('create $orderId');
    if (createError != null) throw createError!;
    return start;
  }

  @override
  Future<Map<String, dynamic>> verifyPayment(String orderId) async {
    calls.add('check $orderId');
    if (checkError != null) throw checkError!;
    return check;
  }
}

class FakeGateway implements PaymentGateway {
  FakeGateway(this.result);

  PhonePeSheet result;
  Map<String, dynamic>? payment;
  String? flowId;

  @override
  Future<PhonePeSheet> open(Map<String, dynamic> payment, {required String flowId}) async {
    this.payment = payment;
    this.flowId = flowId;
    return result;
  }
}

/// Only place_order is used on the PhonePe path; anything Razorpay is a bug.
class PlaceOnlyApi implements PaymentApi {
  @override
  Future<String> placeOrder(String addressId, PaymentMethod method, {String? couponCode}) async => 'order-1';

  @override
  Future<Map<String, dynamic>> createPayment(String orderId) => throw StateError('Razorpay create-payment called');

  @override
  Future<OrderStatus> verifyPayment(SheetPaid paid) => throw StateError('Razorpay verify-payment called');
}

void main() {
  late FakePaymentsRepository api;
  late FakeGateway sdk;
  late List<PayStage> stages;

  ProviderContainer make({bool wired = true}) {
    final c = ProviderContainer(overrides: [
      onlineGatewayProvider.overrideWithValue(OnlineGateway.phonepe),
      paymentsRepositoryProvider.overrideWithValue(wired ? api : null),
      paymentGatewayProvider.overrideWithValue(sdk),
      paymentApiProvider.overrideWithValue(PlaceOnlyApi()),
      currentUserProvider.overrideWithValue(null),
    ]);
    addTearDown(c.dispose);
    stages = [];
    c.listen(paymentFlowProvider, (_, s) => stages.add(s));
    return c;
  }

  Future<PayResult?> pay(ProviderContainer c) => c.read(paymentFlowProvider.notifier).pay('order-1');

  setUp(() {
    api = FakePaymentsRepository();
    sdk = FakeGateway(PhonePeSheet.returned);
  });

  test('checkout: place the order, PhonePe token from the server, SDK, then the server confirms', () async {
    final c = make();
    final r = await c.read(paymentFlowProvider.notifier).checkout('addr-1', PaymentMethod.razorpay);
    expect(r?.payment?.outcome, PayOutcome.paid);
    expect(api.calls, ['create order-1', 'check order-1']);
    expect(sdk.payment?['token'], 'tok1');
    expect(sdk.flowId, 'guest');
    expect(stages, [PayStage.placing, PayStage.starting, PayStage.paying, PayStage.verifying, PayStage.idle]);
  });

  test('the SDK saying SUCCESS proves nothing: pending at the server is "checking"', () async {
    api.check = {'status': 'pending_payment', 'paymentStatus': 'pending'};
    final r = await pay(make());
    expect(r?.outcome, PayOutcome.unknown);
    expect(r?.message, 'Checking your payment. This can take a minute.');
  });

  test('backed out of PhonePe: cancelled, unless the money arrived anyway', () async {
    sdk.result = PhonePeSheet.cancelled;
    api.check = {'status': 'pending_payment', 'paymentStatus': 'pending'};
    expect((await pay(make()))?.outcome, PayOutcome.cancelled);
    api.check = {'status': 'confirmed', 'paymentStatus': 'paid'};
    expect((await pay(make()))?.outcome, PayOutcome.paid);
    expect(api.calls.where((c) => c.startsWith('check')).length, 2, reason: 'the server is asked every time');
  });

  test('PhonePe failed it: failed; paid after the order expired: paid too late', () async {
    api.check = {'status': 'pending_payment', 'paymentStatus': 'failed'};
    expect((await pay(make()))?.outcome, PayOutcome.failed);
    api.check = {'status': 'cancelled', 'paymentStatus': 'paid'};
    expect((await pay(make()))?.outcome, PayOutcome.paidTooLate);
  });

  test('already paid when we asked for a token: no SDK', () async {
    api.start = {'paid': true};
    expect((await pay(make()))?.outcome, PayOutcome.paid);
    expect(sdk.payment, isNull);
    expect(api.calls, ['create order-1']);
  });

  test('no backend wired, a refused token, a broken reply or no SDK in this build: unavailable', () async {
    expect((await pay(make(wired: false)))?.outcome, PayOutcome.unavailable);
    expect(api.calls, isEmpty);

    api.createError = Exception('ORDER_EXPIRED');
    final refused = await pay(make());
    expect([refused?.outcome, refused?.error], [PayOutcome.unavailable, api.createError]);

    api.createError = null;
    api.start = {'env': 'SANDBOX'};
    expect((await pay(make()))?.outcome, PayOutcome.unavailable);
    expect(sdk.payment, isNull);

    api.start = FakePaymentsRepository().start;
    sdk.result = PhonePeSheet.unavailable;
    final missing = await pay(make());
    expect([missing?.outcome, missing?.message],
        [PayOutcome.unavailable, 'Online payment isn’t available right now. Try again later.']);
    expect(api.calls.where((c) => c.startsWith('check')), isEmpty);
  });

  test('the confirm call fails: unverified (the webhook still settles it)', () async {
    api.checkError = Exception('offline');
    expect((await pay(make()))?.outcome, PayOutcome.unverified);
  });

  test('flowId: letters and digits of the user id', () {
    expect(phonePeFlowId('0b8f5a3e-1111-4222-8333-944445555666'), '0b8f5a3e111142228333944445555666');
    expect(phonePeFlowId(null), 'guest');
    expect(phonePeFlowId('--'), 'guest');
  });

  test('with PhonePe the Razorpay EMI line has no plans, and Razorpay is never asked', () async {
    final c = ProviderContainer(overrides: [onlineGatewayProvider.overrideWithValue(OnlineGateway.phonepe)]);
    addTearDown(c.dispose);
    final plans = c.listen(emiPlansProvider.future, (_, _) {});
    expect(await plans.read(), isEmpty);
  });

  test('Razorpay stays the default gateway', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(onlineGatewayProvider), OnlineGateway.razorpay);
  });
}
