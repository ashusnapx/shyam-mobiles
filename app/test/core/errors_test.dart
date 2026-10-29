import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/errors.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/core/theme/theme.dart';
import 'package:shyam_mobiles/core/widgets/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _offline = 'You’re offline. Check your connection and try again.';
const _session = 'Your session has ended. Sign in again to continue.';
const _notFound = 'We couldn’t find that. It may have been removed.';

void main() {
  test('friendlyError: every failure gets plain copy, never raw server text', () {
    final cases = <(Object, Object)>[
      // RPC business errors (P0001, bare code in message)
      (const PostgrestException(message: 'OUT_OF_STOCK', code: 'P0001', details: 'v1,v2'), 'Some items just went out of stock. Check your cart and try again.'),
      (const PostgrestException(message: 'COD_UNAVAILABLE', code: 'P0001'), 'Cash on delivery isn’t available for this order. Pay online instead.'),
      (const PostgrestException(message: 'ADDRESS_LIMIT', code: 'P0001'), 'You can save up to 10 addresses. Delete one to add another.'),
      (const PostgrestException(message: 'permission denied for table orders', code: '42501'), 'You don’t have access to this.'),
      // /orders/garbage, /repairs/garbage: a malformed uuid; .single() on a missing row
      (const PostgrestException(message: 'invalid input syntax for type uuid: "garbage"', code: '22P02'), _notFound),
      (const PostgrestException(message: 'JSON object requested, multiple (or no) rows returned', code: 'PGRST116'), _notFound),
      // an expired access token that couldn't be refreshed
      (const PostgrestException(message: 'JWT expired', code: 'PGRST303'), _session),
      (const PostgrestException(message: 'JWSError', code: 'PGRST301'), _session),
      (const PostgrestException(message: 'duplicate key value violates unique constraint "x"', code: '23505'), fallbackError),
      // Edge Functions
      (const FunctionsFetchException(details: 'SocketException: Failed host lookup'), _offline),
      (const FunctionsHttpException(status: 401, details: {'msg': 'Invalid JWT'}), _session),
      (const FunctionsHttpException(status: 409, details: {'error': 'ORDER_EXPIRED', 'message': 'x'}), contains('payment window closed')),
      (const FunctionsHttpException(status: 409, details: {'error': 'NEW_CODE', 'message': 'Short human text.'}), 'Short human text.'),
      (const FunctionsHttpException(status: 500, details: 'boom'), fallbackError),
      // Auth
      (AuthRetryableFetchException(message: 'ClientException with SocketException: Network is unreachable'), _offline),
      (AuthSessionMissingException(), _session),
      (const AuthApiException('Token has expired or is invalid', statusCode: '403', code: 'otp_expired'), 'That code is wrong or has expired. Request a new one.'),
      (const AuthApiException('For security purposes, you can only request this after 42 seconds.', statusCode: '429', code: 'over_sms_send_rate_limit'), 'Too many attempts. Wait a minute and try again.'),
      (const AuthApiException('Email rate limit exceeded', statusCode: '400', code: 'over_email_send_rate_limit'), 'Too many attempts. Wait a minute and try again.'),
      (const AuthApiException('Invalid Refresh Token: Refresh Token Not Found', statusCode: '400', code: 'refresh_token_not_found'), _session),
      (const AuthApiException('Unable to validate email address: invalid format', statusCode: '400', code: 'validation_failed'), 'Check the number or email and try again.'),
      (const AuthApiException('Error sending sms: provider said no', statusCode: '500', code: 'unexpected_failure'), fallbackError),
      (const AuthException('Sign in to add to cart'), 'Sign in to add to cart'), // the app's own guard copy
      // Network
      (TimeoutException('Request timed out'), 'That took too long. Check your connection and try again.'),
      (const SocketException('Failed host lookup'), _offline),
      (http.ClientException('Connection closed before full header was received'), _offline),
      (const HandshakeException('CERTIFICATE_VERIFY_FAILED'), _offline),
      (StateError('bug'), fallbackError),
      // A check constraint the app's own rules should have caught: name the field when the constraint says it
      (const PostgrestException(message: 'new row for relation "addresses" violates check constraint "addresses_city_check"', code: '23514'), 'Check the city and try again.'),
      (const PostgrestException(message: 'new row for relation "profiles" violates check constraint "profiles_full_name_check"', code: '23514'), 'Check the name and try again.'),
      (const PostgrestException(message: 'value for domain in_phone violates check constraint "in_phone_check"', code: '23514'), 'Check the mobile number and try again.'),
      (const PostgrestException(message: 'new row for relation "variants" violates check constraint "variants_check"', code: '23514'), 'The MRP can’t be below the price.'),
      (const PostgrestException(message: 'new row for relation "x" violates check constraint "x_mystery"', code: '23514'), 'One of the fields isn’t valid. Check it and try again.'),
    ];
    for (final (error, copy) in cases) {
      expect(friendlyError(error), copy, reason: '$error');
    }
  });

  test('session errors are told apart from ones a retry can fix', () {
    for (final dead in <Object>[
      const PostgrestException(message: 'JWT expired', code: 'PGRST303'),
      const FunctionsHttpException(status: 401, details: {'msg': 'Invalid JWT'}),
      AuthSessionMissingException(),
      const AuthApiException('Session not found', statusCode: '403', code: 'session_not_found'),
    ]) {
      expect(isSessionError(dead), isTrue, reason: '$dead');
    }
    for (final other in <Object>[
      const PostgrestException(message: 'OUT_OF_STOCK', code: 'P0001'),
      const PostgrestException(message: 'x', code: '42501'),
      const FunctionsHttpException(status: 409, details: {'error': 'ORDER_EXPIRED'}),
      const AuthApiException('Token has expired or is invalid', statusCode: '403', code: 'otp_expired'),
      TimeoutException('x'),
    ]) {
      expect(isSessionError(other), isFalse, reason: '$other');
    }
  });

  testWidgets('ErrorView: "Sign in again" for a dead session, "Try again" otherwise', (tester) async {
    Future<void> pump(Object error) => tester.pumpWidget(MaterialApp(
          theme: lightTheme,
          home: Scaffold(body: ErrorView(error: error, onRetry: () {})),
        ));
    await pump(const PostgrestException(message: 'JWT expired', code: 'PGRST303'));
    expect(find.text('Sign in again'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text(_session), findsOneWidget);
    await pump(const SocketException('offline'));
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text(_offline), findsOneWidget);
  });

  group('TimeoutClient', () {
    test('a stalled request fails with TimeoutException instead of hanging', () async {
      final never = Completer<http.StreamedResponse>();
      final client = TimeoutClient(
        MockClient.streaming((_, _) => never.future),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(client.get(Uri.parse('http://localhost/rest/v1/orders')), throwsA(isA<TimeoutException>()));
      expect(friendlyError(TimeoutException('x')), contains('took too long'));
    });

    test('normal responses pass through', () async {
      final client = TimeoutClient(MockClient((r) async => http.Response('[]', 200, request: r)));
      final res = await client.get(Uri.parse('http://localhost/rest/v1/orders'));
      expect((res.statusCode, res.body), (200, '[]'));
    });
  });
}
