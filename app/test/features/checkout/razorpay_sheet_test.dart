import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/features/checkout/data/payment.dart';

const _channel = MethodChannel('razorpay_flutter');
const _options = {'key': 'rzp_test', 'order_id': 'order_rzp1', 'amount': 100, 'currency': 'INR'};

Map<String, Object?> _success(String orderId) => {
      'type': 0,
      'data': {'razorpay_payment_id': 'pay_1', 'razorpay_order_id': orderId, 'razorpay_signature': 'sig_1'},
    };

/// Mocks the plugin: `open` answers with [open] (a never-completing future = sheet still up), `resync` with [resync].
void _mock(WidgetTester tester, {required Future<Object?> Function() open, Object? Function()? resync}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
    if (call.method == 'open') return open();
    if (call.method == 'resync') return resync?.call();
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
}

Future<SheetResult?> _run(WidgetTester tester, Future<void> Function() during) async {
  SheetResult? result;
  unawaited(const RazorpaySheet().open(Map.of(_options)).then((r) => result = r));
  await tester.pump();
  await during();
  await tester.pump();
  return result;
}

void _lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void main() {
  testWidgets('success with the signature', (tester) async {
    _mock(tester, open: () async => _success('order_rzp1'));
    final r = await _run(tester, () async {});
    expect(r, isA<SheetPaid>().having((p) => p.paymentId, 'paymentId', 'pay_1').having((p) => p.orderId, 'orderId', 'order_rzp1'));
  });

  testWidgets('Android back / dismiss: code 2 is a cancel', (tester) async {
    _mock(tester, open: () async => {'type': 1, 'data': {'code': 2, 'message': 'Payment cancelled'}});
    expect(await _run(tester, () async {}), isA<SheetClosed>().having((c) => c.cancelled, 'cancelled', true));
  });

  testWidgets('other errors are a failure, not a cancel', (tester) async {
    _mock(tester, open: () async => {'type': 1, 'data': {'code': 0, 'message': 'Network error'}});
    expect(await _run(tester, () async {}), isA<SheetClosed>().having((c) => c.cancelled, 'cancelled', false));
  });

  testWidgets('external wallet: unknown, the webhook decides', (tester) async {
    _mock(tester, open: () async => {'type': 2, 'data': {'external_wallet': 'paytm'}});
    expect(await _run(tester, () async {}), isA<SheetUnknown>());
  });

  testWidgets('a replayed success for an older order is ignored', (tester) async {
    var replayed = false;
    _mock(
      tester,
      resync: () {
        if (replayed) return null; // native clears its pending reply once delivered
        replayed = true;
        return _success('order_old');
      },
      open: () async => _success('order_rzp1'),
    );
    expect(await _run(tester, () async {}), isA<SheetPaid>().having((p) => p.orderId, 'orderId', 'order_rzp1'));
  });

  testWidgets('back from a UPI app with no callback: unknown after the grace period', (tester) async {
    final never = Completer<Object?>();
    _mock(tester, open: () => never.future);
    final r = await _run(tester, () async {
      _lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
      await tester.pump(const Duration(minutes: 3)); // paying in the UPI app: no timeout while we're away
      _lifecycle(tester, [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
      await tester.pump(RazorpaySheet.callbackGrace - const Duration(seconds: 1));
      expect(never.isCompleted, isFalse);
      await tester.pump(const Duration(seconds: 2));
    });
    expect(r, isA<SheetUnknown>());
  });

  testWidgets('sheet never shows (plugin did nothing): closed after 10 s, not stuck', (tester) async {
    _mock(tester, open: () => Completer<Object?>().future);
    final r = await _run(tester, () => tester.pump(const Duration(seconds: 11)));
    expect(r, isA<SheetClosed>());
  });

  testWidgets('platform error opening the sheet: closed', (tester) async {
    _mock(tester, open: () async => throw PlatformException(code: 'boom'));
    expect(await _run(tester, () async {}), isA<SheetClosed>());
  });
}
