import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phonepe_payment_sdk/phonepe_payment_sdk.dart';

import '../../../core/env.dart';

/// Which gateway takes online payments: the PAYMENT_GATEWAY dart-define (docs/PHONEPE.md). Razorpay until PhonePe is
/// verified with real credentials, because the owner's phone runs against a backend that only has Razorpay. At the
/// Firebase cut-over PhonePe is the only one (docs/FIREBASE.md D4) and this goes.
enum OnlineGateway { razorpay, phonepe }

final onlineGatewayProvider =
    Provider<OnlineGateway>((ref) => Env.paymentGateway == 'phonepe' ? OnlineGateway.phonepe : OnlineGateway.razorpay);

/// How the PhonePe screen closed. Only the server knows whether money moved.
enum PhonePeSheet {
  /// The pay page finished, or we came back with no answer: ask the server.
  returned,

  /// The customer backed out (Android's RESULT_CANCELED), or the SDK refused the request.
  cancelled,

  /// The SDK isn't in this build (MissingPluginException until a full rebuild) or wouldn't start.
  unavailable,
}

/// The PhonePe SDK, behind an interface so tests can fake it (docs/FIREBASE.md §2, `PaymentGateway`).
abstract interface class PaymentGateway {
  /// Opens PhonePe's pay page for [start], the backend's `createPayment` reply `{merchantId, token, orderId, env}`.
  /// Never throws; always completes.
  Future<PhonePeSheet> open(Map<String, dynamic> start, {required String flowId});
}

/// PhonePe Standard Checkout through `phonepe_payment_sdk`. On Android it runs in its own activity.
class PhonePePaymentGateway implements PaymentGateway {
  const PhonePePaymentGateway();

  /// How long to wait for the SDK after the app comes back to the foreground: an activity recreated while the
  /// customer was in a UPI app loses the plugin's callback.
  static const callbackGrace = Duration(seconds: 8);

  static String? _ready; // the environment, merchant and flow the SDK was initialised for

  @override
  Future<PhonePeSheet> open(Map<String, dynamic> start, {required String flowId}) async {
    final environment = start['env'] == 'PRODUCTION' ? 'PRODUCTION' : 'SANDBOX';
    final merchantId = start['merchantId'] as String;
    try {
      final key = '$environment|$merchantId|$flowId';
      if (_ready != key) {
        if (!await PhonePePaymentSdk.init(environment, merchantId, flowId, false)) return PhonePeSheet.unavailable;
        _ready = key;
      }
    } catch (_) {
      return PhonePeSheet.unavailable;
    }

    final done = Completer<PhonePeSheet>();
    void finish(PhonePeSheet r) {
      if (!done.isCompleted) done.complete(r);
    }

    Timer? grace;
    final lifecycle = AppLifecycleListener(onResume: () {
      grace?.cancel();
      grace = Timer(callbackGrace, () => finish(PhonePeSheet.returned));
    });
    final request = jsonEncode({
      'orderId': start['orderId'], // PhonePe's order id
      'merchantId': merchantId,
      'token': start['token'],
      'paymentMode': {'type': 'PAY_PAGE'},
    });
    unawaited(PhonePePaymentSdk.startTransaction(request, '').then(
      // SUCCESS only means the pay page finished; FAILURE is the activity coming back cancelled
      (r) => finish(r == null || r['status'] == 'SUCCESS' ? PhonePeSheet.returned : PhonePeSheet.cancelled),
      onError: (Object _) => finish(PhonePeSheet.cancelled),
    ));
    return done.future.whenComplete(() {
      grace?.cancel();
      lifecycle.dispose();
    });
  }
}

final paymentGatewayProvider = Provider<PaymentGateway>((ref) => const PhonePePaymentGateway());

/// PhonePe's flowId: letters and digits only. It ties the SDK's logs to one customer.
String phonePeFlowId(String? userId) {
  final id = (userId ?? '').replaceAll(RegExp('[^A-Za-z0-9]'), '');
  return id.isEmpty ? 'guest' : id;
}
