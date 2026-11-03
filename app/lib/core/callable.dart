import 'package:cloud_functions/cloud_functions.dart';

/// Calls the callable [name] (`firebase/functions/src/<domain>/contract.ts`) and returns its JSON reply. Errors stay
/// [FirebaseFunctionsException]s whose `details.reason` is an errors.dart code, so friendlyError shows the same copy
/// as today. [replayProtected]: the server consumes the App Check token, so a captured request can't be replayed
/// (placeOrder, createPayment, startRefund, setRole, deleteAccount: docs/SECURITY.md §2.1).
Future<Map<String, dynamic>> callFunction(
  FirebaseFunctions functions,
  String name, [
  Map<String, Object?> data = const {},
  bool replayProtected = false,
]) async {
  final callable = functions.httpsCallable(
    name,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 30), limitedUseAppCheckToken: replayProtected),
  );
  final res = await callable.call<Object?>(data);
  return Map<String, dynamic>.from(res.data as Map? ?? const {});
}

/// The business reason of a callable failure (`OUT_OF_STOCK`, `COUPON_MIN_ORDER`…), or null.
String? reasonOf(Object e) => e is FirebaseFunctionsException && e.details is Map ? (e.details as Map)['reason'] as String? : null;
