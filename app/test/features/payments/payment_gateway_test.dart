import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/features/payments/data/payment_gateway.dart';

const _channel = MethodChannel('phonepe_payment_sdk');

/// A `createPayment` reply.
Map<String, dynamic> _start(String merchant) => {'env': 'SANDBOX', 'merchantId': merchant, 'orderId': 'OMO1', 'token': 'tok1'};

/// Mocks the plugin; records every call. [transaction] answers startTransaction (never completing = still paying).
List<MethodCall> _mock(WidgetTester tester, {Object init = true, required Future<Object?> Function() transaction}) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
    calls.add(call);
    if (call.method != 'init') return await transaction();
    if (init is Exception) throw init;
    return init;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
  return calls;
}

Future<PhonePeSheet?> _run(WidgetTester tester, String merchant, [Future<void> Function()? during]) async {
  PhonePeSheet? result;
  unawaited(const PhonePePaymentGateway().open(_start(merchant), flowId: 'u1').then((r) => result = r));
  await tester.pump();
  await during?.call();
  await tester.pump();
  return result;
}

void main() {
  testWidgets('init once, then PAY_PAGE with the server\'s order id and token; SUCCESS means "ask the server"', (tester) async {
    final calls = _mock(tester, transaction: () async => {'status': 'SUCCESS'});
    expect(await _run(tester, 'M1'), PhonePeSheet.returned);
    expect(calls.first.method, 'init');
    expect(calls.first.arguments, {'environment': 'SANDBOX', 'merchantId': 'M1', 'flowId': 'u1', 'enableLogs': false});
    expect(jsonDecode((calls[1].arguments as Map)['request'] as String),
        {'orderId': 'OMO1', 'merchantId': 'M1', 'token': 'tok1', 'paymentMode': {'type': 'PAY_PAGE'}});

    expect(await _run(tester, 'M1'), PhonePeSheet.returned);
    expect(calls.where((c) => c.method == 'init').length, 1, reason: 'initialised once for the same merchant and user');
  });

  testWidgets('FAILURE (backed out) or a platform error: cancelled', (tester) async {
    _mock(tester, transaction: () async => {'status': 'FAILURE', 'error': 'RESULT_CANCELED'});
    expect(await _run(tester, 'M2'), PhonePeSheet.cancelled);
    _mock(tester, transaction: () async => throw PlatformException(code: 'x'));
    expect(await _run(tester, 'M2'), PhonePeSheet.cancelled);
  });

  testWidgets('no plugin in this build, or init refused: unavailable, no transaction', (tester) async {
    _mock(tester, init: MissingPluginException(), transaction: () async => {'status': 'SUCCESS'});
    expect(await _run(tester, 'M3'), PhonePeSheet.unavailable, reason: 'MissingPluginException before a full rebuild');
    final calls = _mock(tester, init: false, transaction: () async => {'status': 'SUCCESS'});
    expect(await _run(tester, 'M4'), PhonePeSheet.unavailable);
    expect(calls.map((c) => c.method), ['init']);
  });

  testWidgets('back from a UPI app with no callback: "ask the server" after the grace period', (tester) async {
    _mock(tester, transaction: () => Completer<Object?>().future);
    final r = await _run(tester, 'M5', () async {
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
        AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump(PhonePePaymentGateway.callbackGrace);
    });
    expect(r, PhonePeSheet.returned);
  });
}
