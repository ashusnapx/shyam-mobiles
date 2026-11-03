import 'package:cloud_functions/cloud_functions.dart';

/// What every fake shares: set [error] to make each call fail with it (error and retry states), and [calls] records
/// what the code under test asked for, in order ("cancel o1").
mixin Fake {
  Exception? error;
  final calls = <String>[];

  /// Records [call], then throws [error] if set.
  void record(String call) {
    calls.add(call);
    if (error case final e?) throw e;
  }
}

/// Rows [from]..[from + size − 1] of [all].
List<T> pageOf<T>(List<T> all, int from, int size) => all.skip(from).take(size).toList();

/// A callable refusal as the Firebase build gets it (details.reason), e.g. `reason('ACTIVE_ORDERS')`.
FirebaseFunctionsException reason(String code, [Object? detail]) => FirebaseFunctionsException(
    code: 'failed-precondition', message: code, details: {'reason': code, 'detail': ?detail});
