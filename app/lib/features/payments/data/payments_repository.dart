import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/callable.dart';
import '../../../core/firebase.dart';

/// The backend half of a PhonePe payment: the `createPayment` and `verifyPayment` callables (docs/FIREBASE.md §5).
/// The amount never goes up from the phone; the server prices the order.
abstract interface class PaymentsRepository {
  /// `{merchantId, token, orderId, env}` for the PhonePe SDK (orderId is PhonePe's), or `{paid: true}` when PhonePe
  /// already has the money.
  Future<Map<String, dynamic>> createPayment(String orderId);

  /// The order after the server asked PhonePe's status API: `{status, paymentStatus}`.
  Future<Map<String, dynamic>> verifyPayment(String orderId);

  /// Staff (TOTP session, signed in within 5 minutes): PhonePe refunds everything left, or [itemIds]' lines.
  /// `{refundId, amountPaise, status, retry}`; a retry of an unconfirmed refund re-sends the same one, never a second.
  Future<Map<String, dynamic>> startRefund(String orderId, {List<String>? itemIds, bool restock = false});
}

/// The `createPayment`, `verifyPayment` and `startRefund` callables (firebase/functions/src/payments/contract.ts).
class FirebasePaymentsRepository implements PaymentsRepository {
  const FirebasePaymentsRepository(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, dynamic>> createPayment(String orderId) => callFunction(_functions, 'createPayment', {'orderId': orderId}, true);

  @override
  Future<Map<String, dynamic>> verifyPayment(String orderId) => callFunction(_functions, 'verifyPayment', {'orderId': orderId});

  @override
  Future<Map<String, dynamic>> startRefund(String orderId, {List<String>? itemIds, bool restock = false}) =>
      callFunction(_functions, 'startRefund', {'orderId': orderId, 'itemIds': ?itemIds, 'restock': restock}, true);
}

/// Null on the Supabase build, whose PhonePe path has no backend (choosing PhonePe there says online payment isn't
/// available); the Firebase build pays and refunds through PhonePe only (docs/FIREBASE.md D4).
final paymentsRepositoryProvider = Provider<PaymentsRepository?>(
    (ref) => backend == Backend.firebase ? FirebasePaymentsRepository(ref.watch(functionsProvider)) : null);
