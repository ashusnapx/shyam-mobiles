import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/callable.dart';
import 'package:shyam_mobiles/core/errors.dart';

// Callable failures carry today's reason keys in details.reason (firebase/functions/src/shared/errors.ts), so the
// Firebase build shows the same copy as the Supabase one.
FirebaseFunctionsException fails(String code, [Object? details]) =>
    FirebaseFunctionsException(code: code, message: 'x', details: details);

void main() {
  test('a reason shows its copy, never the server text', () {
    expect(friendlyError(fails('failed-precondition', {'reason': 'OUT_OF_STOCK'})),
        'Some items just went out of stock. Check your cart and try again.');
    expect(friendlyError(fails('internal', {'reason': 'INTERNAL'})), fallbackError);
    expect(friendlyError(fails('internal')), fallbackError);
  });

  test('coupon and promotion details fill in the copy', () {
    expect(friendlyError(fails('failed-precondition', {'reason': 'COUPON_MIN_ORDER', 'detail': 99900})),
        contains('₹999'));
    expect(friendlyError(fails('invalid-argument', {'reason': 'INVALID_PROMOTION', 'detail': 'promotions_window_check'})),
        'The end has to be after the start.');
  });

  test('offline and session errors', () {
    expect(friendlyError(fails('unavailable')), contains('offline'));
    expect(isSessionError(fails('unauthenticated', {'reason': 'UNAUTHORIZED'})), isTrue);
    expect(isSessionError(fails('unauthenticated', {'reason': 'REAUTH_REQUIRED'})), isFalse);
    expect(friendlyError(fails('unauthenticated', {'reason': 'REAUTH_REQUIRED'})), 'For your security, sign in again to do this.');
  });

  test('Firebase Auth offline reads as offline', () {
    expect(friendlyError(FirebaseAuthException(code: 'network-request-failed')), contains('offline'));
  });

  test('reasonOf', () {
    expect(reasonOf(fails('failed-precondition', {'reason': 'CART_EMPTY'})), 'CART_EMPTY');
    expect(reasonOf(StateError('x')), isNull);
  });
}
