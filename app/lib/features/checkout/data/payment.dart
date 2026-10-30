import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env.dart';
import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../cart/data/cart.dart';
import '../../offers/data/offers.dart';

/// Server calls on the money path. The client never sends an amount: the server prices everything.
abstract interface class PaymentApi {
  /// `place_order` RPC → order id. Throws PostgrestException with a bare code (CART_EMPTY, OUT_OF_STOCK, a
  /// COUPON_* refusal of [couponCode], ...).
  Future<String> placeOrder(String addressId, PaymentMethod method, {String? couponCode});

  /// `create-payment` → `{key_id, razorpay_order_id, amount, currency, order_number, reserved_until, customer_id}`.
  Future<Map<String, dynamic>> createPayment(String orderId);

  /// `verify-payment` → the order status afterwards (`confirmed`, or `cancelled` when it was paid too late).
  Future<OrderStatus> verifyPayment(SheetPaid paid);
}

class SupabasePaymentApi implements PaymentApi {
  const SupabasePaymentApi(this._db);

  final SupabaseClient _db;

  @override
  Future<String> placeOrder(String addressId, PaymentMethod method, {String? couponCode}) async =>
      await _db.rpc<String>('place_order', params: {
        'p_address_id': addressId,
        'p_payment_method': method.value,
        'p_coupon_code': couponCode,
      });

  @override
  Future<Map<String, dynamic>> createPayment(String orderId) async {
    final res = await _db.functions.invoke('create-payment', body: {'order_id': orderId});
    return Map<String, dynamic>.from(res.data as Map);
  }

  @override
  Future<OrderStatus> verifyPayment(SheetPaid paid) async {
    final res = await _db.functions.invoke('verify-payment', body: {
      'razorpay_order_id': paid.orderId,
      'razorpay_payment_id': paid.paymentId,
      'razorpay_signature': paid.signature,
    });
    return OrderStatus.parse((res.data as Map)['status']);
  }
}

/// How the Razorpay sheet closed.
sealed class SheetResult {
  const SheetResult();
}

final class SheetPaid extends SheetResult {
  const SheetPaid({required this.orderId, required this.paymentId, required this.signature});

  final String orderId; // razorpay order id
  final String paymentId;
  final String signature;
}

/// Payment error or the customer closed the sheet (`cancelled`, Razorpay code 2, also the Android back button).
final class SheetClosed extends SheetResult {
  const SheetClosed({this.cancelled = false});

  final bool cancelled;
}

/// External wallet, or we came back from a UPI app with no callback. Only the server (webhook) knows.
final class SheetUnknown extends SheetResult {
  const SheetUnknown();
}

abstract interface class PaymentSheet {
  /// Never throws; always completes.
  Future<SheetResult> open(Map<String, dynamic> options);
}

/// Razorpay Standard Checkout. On Android it runs in its own activity, so our app resumes when it closes.
class RazorpaySheet implements PaymentSheet {
  const RazorpaySheet();

  /// How long to wait for the SDK callback after the app comes back to the foreground.
  static const callbackGrace = Duration(seconds: 8);

  @override
  Future<SheetResult> open(Map<String, dynamic> options) {
    final rzp = Razorpay();
    final done = Completer<SheetResult>();
    final expected = options['order_id'] as String;
    Timer? grace;
    void finish(SheetResult r) {
      if (!done.isCompleted) done.complete(r);
    }

    rzp
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
        // The SDK can replay a reply that an earlier sheet lost; the webhook settles that one.
        if (r.orderId != null && r.orderId != expected) return;
        final paymentId = r.paymentId, signature = r.signature;
        finish(paymentId == null || signature == null
            ? const SheetUnknown()
            : SheetPaid(orderId: expected, paymentId: paymentId, signature: signature));
      })
      ..on(Razorpay.EVENT_PAYMENT_ERROR,
          (PaymentFailureResponse r) => finish(SheetClosed(cancelled: r.code == Razorpay.PAYMENT_CANCELLED)))
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse _) => finish(const SheetUnknown()));

    // A UPI app can hand control back with no callback at all; don't leave the customer on a spinner.
    var left = false;
    final lifecycle = AppLifecycleListener(
      onInactive: () => left = true,
      onResume: () {
        grace?.cancel();
        grace = Timer(callbackGrace, () => finish(const SheetUnknown()));
      },
    );
    // The plugin silently does nothing on some misconfigurations (e.g. package name); then the sheet never shows.
    final shown = Timer(const Duration(seconds: 10), () {
      if (!left) finish(const SheetClosed());
    });
    // open() is fire-and-forget; catch its async platform errors here.
    runZonedGuarded(() => rzp.open(options), (_, _) => finish(const SheetClosed()));

    return done.future.whenComplete(() {
      grace?.cancel();
      shown.cancel();
      lifecycle.dispose();
      rzp.clear();
    });
  }
}

/// Razorpay Standard Checkout options from a `create-payment` response. Null when no key is configured.
/// With `reserved_until` the sheet closes when the stock hold ends, so nobody pays for an expired order.
Map<String, dynamic>? razorpayOptions(Map<String, dynamic> payment, {String? phone, String? email, DateTime? now}) {
  final serverKey = payment['key_id'];
  final key = serverKey is String && serverKey.isNotEmpty ? serverKey : Env.razorpayKeyId;
  if (key.isEmpty || payment['razorpay_order_id'] is! String) return null;
  final contact = phone == null ? null : normalizeIndianPhone(phone);
  final until = payment['reserved_until'] is String ? DateTime.tryParse(payment['reserved_until']) : null;
  return {
    'key': key,
    'order_id': payment['razorpay_order_id'],
    'amount': payment['amount'],
    'currency': payment['currency'],
    'name': 'Shyam Mobiles',
    'description': 'Order ${payment['order_number']}',
    'prefill': {'contact': ?contact, if (email != null && email.isNotEmpty) 'email': email},
    'theme': {'color': '#${(BrandColors.ink.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}'},
    'retry': {'enabled': true},
    if (until != null) 'timeout': math.max(60, until.difference(now ?? DateTime.now()).inSeconds),
    // saved cards: the account's Razorpay customer (create-payment makes it); the card tokens stay with Razorpay
    if (payment['customer_id'] is String) ...{'customer_id': payment['customer_id'], 'remember_customer': true},
  };
}

enum PayStage {
  idle(''),
  placing('Placing order…'),
  starting('Opening payment…'),
  paying('Waiting for payment…'),
  verifying('Confirming payment…');

  const PayStage(this.label);
  final String label;
}

enum PayOutcome { paid, paidTooLate, cancelled, failed, unknown, unavailable, unverified }

/// What happened when the customer tried to pay. The order row stays the truth; this only picks the message.
class PayResult {
  const PayResult(this.outcome, [this.error]);

  final PayOutcome outcome;
  final Object? error;

  /// Snackbar copy, or null when the next screen says it all.
  String? get message => switch (outcome) {
        PayOutcome.paid || PayOutcome.paidTooLate => null,
        PayOutcome.cancelled => 'Payment cancelled. You can try again.',
        PayOutcome.failed => 'Payment didn’t go through. You can try again.',
        PayOutcome.unknown => 'Checking your payment. This can take a minute.',
        PayOutcome.unavailable =>
          error == null ? 'Online payment isn’t available right now. Try again later.' : friendlyError(error!),
        // Network trouble after the sheet: the webhook will still confirm it, so stay calm.
        PayOutcome.unverified =>
          error is FunctionException && error is! FunctionsFetchException ? friendlyError(error!) : null,
      };
}

final paymentApiProvider = Provider<PaymentApi>((ref) => SupabasePaymentApi(ref.watch(supabaseProvider)));
final paymentSheetProvider = Provider<PaymentSheet>((ref) => const RazorpaySheet());

/// One checkout or payment at a time, app-wide. The state drives button labels and the double-tap guard.
final paymentFlowProvider = NotifierProvider<PaymentFlow, PayStage>(PaymentFlow.new);

class PaymentFlow extends Notifier<PayStage> {
  @override
  PayStage build() => PayStage.idle;

  PaymentApi get _api => ref.read(paymentApiProvider);

  /// Places the order and, for online payment, takes it. Null if a flow is already running.
  /// `place_order` errors are rethrown (no order exists); anything later is reported in `payment`.
  Future<({String orderId, PayResult? payment})?> checkout(String addressId, PaymentMethod method, {String? couponCode}) async {
    if (state != PayStage.idle) return null;
    state = PayStage.placing;
    try {
      final orderId = await _api.placeOrder(addressId, method, couponCode: couponCode);
      ref.read(couponCodeProvider.notifier).set(null); // used up by this order
      return (orderId: orderId, payment: method == PaymentMethod.cod ? null : await _pay(orderId));
    } finally {
      state = PayStage.idle;
      ref.invalidate(cartProvider); // the server removes the ordered lines on success; stale stock on OUT_OF_STOCK
    }
  }

  /// Retry for an unpaid online order. Null if a flow is already running.
  Future<PayResult?> pay(String orderId) async {
    if (state != PayStage.idle) return null;
    try {
      return await _pay(orderId);
    } finally {
      state = PayStage.idle;
    }
  }

  Future<PayResult> _pay(String orderId) async {
    state = PayStage.starting;
    final Map<String, dynamic> payment;
    try {
      payment = await _api.createPayment(orderId);
    } catch (e) {
      return PayResult(PayOutcome.unavailable, e);
    }
    final user = ref.read(currentUserProvider);
    final options = razorpayOptions(payment, phone: user?.phone, email: user?.email);
    if (options == null) return const PayResult(PayOutcome.unavailable);

    state = PayStage.paying;
    final SheetResult sheet;
    try {
      sheet = await ref.read(paymentSheetProvider).open(options);
    } catch (e) {
      return PayResult(PayOutcome.failed, e);
    }
    switch (sheet) {
      case SheetClosed(:final cancelled):
        return PayResult(cancelled ? PayOutcome.cancelled : PayOutcome.failed);
      case SheetUnknown():
        return const PayResult(PayOutcome.unknown);
      case SheetPaid():
        state = PayStage.verifying;
        try {
          final status = await _api.verifyPayment(sheet);
          return PayResult(status == OrderStatus.cancelled ? PayOutcome.paidTooLate : PayOutcome.paid);
        } catch (e) {
          return PayResult(PayOutcome.unverified, e);
        }
    }
  }
}
