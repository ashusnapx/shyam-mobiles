import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The backend half of a PhonePe payment: the `createPayment` and `verifyPayment` callables (docs/FIREBASE.md §5).
/// The amount never goes up from the phone; the server prices the order.
abstract interface class PaymentsRepository {
  /// `{merchantId, token, orderId, env}` for the PhonePe SDK (orderId is PhonePe's), or `{paid: true}` when PhonePe
  /// already has the money.
  Future<Map<String, dynamic>> createPayment(String orderId);

  /// The order after the server asked PhonePe's status API: `{status, paymentStatus}`.
  Future<Map<String, dynamic>> verifyPayment(String orderId);
}

/// Null until the Firebase implementation lands (engineer D, after A's `core/callable.dart`); choosing PhonePe then
/// says online payment isn't available.
final paymentsRepositoryProvider = Provider<PaymentsRepository?>((ref) => null);
