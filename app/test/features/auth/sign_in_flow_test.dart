// Sign-in, the code step and the name step at 360x800 dp with 1.4x text, against the fake AuthRepository.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/account/data/profile.dart';
import 'package:shyam_mobiles/features/auth/data/auth_repository.dart';
import 'package:shyam_mobiles/features/auth/screens/name_screen.dart';
import 'package:shyam_mobiles/features/auth/screens/sign_in_screen.dart';
import 'package:shyam_mobiles/features/auth/screens/verify_code_screen.dart';
import 'package:shyam_mobiles/features/auth/widgets/dev_login.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../fakes/fake_auth_repository.dart';
import '../repairs/layout_harness.dart';

void main() {
  testWidgets('one calm screen that fits: no hero, no offers, nothing promotional', (tester) async {
    await pumpScreen(tester, const SignInScreen(), userId: null);
    await tester.pumpAndSettle(); // the entrance and the mark's ripple
    expect(find.text('Welcome to Shyam Mobiles'), findsOneWidget);
    expect(find.text('Phones, accessories and repairs in Waidhan'), findsOneWidget);
    expect(find.text('Get code'), findsOneWidget);
    expect(find.textContaining('By continuing you agree to the', findRichText: true), findsOneWidget);
    for (final promo in ['₹', 'off', 'Free delivery', 'friend', 'WELCOME', 'Email']) {
      expect(find.textContaining(promo), findsNothing, reason: promo);
    }
    expect(find.text('Try the demo'), findsNothing, reason: 'demo sign-in only in demo and dev builds');
    expect(find.byType(DevLoginButtons), findsNothing);
    expect(tester.takeException(), isNull);

    addTearDown(tester.view.resetViewInsets);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3.0); // the keyboard
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone field: 10 digits after +91, checked before any code is sent', (tester) async {
    final auth = FakeAuthRepository();
    await pumpScreen(tester, const SignInScreen(), userId: null, overrides: [authRepositoryProvider.overrideWithValue(auth)]);
    final semantics = tester.ensureSemantics();
    await tester.pumpAndSettle(); // the entrance fades in from 0, which hides semantics until it starts
    expect(tester.getSemantics(find.byType(TextField)).label, startsWith('Mobile number'));
    semantics.dispose();
    final field = find.byType(TextField);
    String text() => tester.widget<TextField>(field).controller!.text;

    await tester.enterText(field, '+91 98765-43210 (home)'); // pasted from a contact card
    expect(text(), '98765 43210');
    await tester.enterText(field, '98765 432101');
    expect(text(), '98765 43210');
    await tester.enterText(field, '९८७६५४३२१०'); // Devanagari digits
    expect(text(), '98765 43210');

    await tester.enterText(field, '12345');
    await tester.tap(find.text('Get code'));
    await tester.pump();
    expect(find.text('Enter a 10-digit mobile number.'), findsOneWidget);
    await tester.enterText(field, '51234 67890');
    await tester.tap(find.text('Get code'));
    await tester.pump();
    expect(find.text('Mobile numbers start with 6, 7, 8 or 9.'), findsOneWidget);
    expect(auth.calls, isEmpty);
    expect(tester.widget<TextField>(field).keyboardType, TextInputType.phone);
  });

  testWidgets('Get code sends the code and opens the code step; a refusal says so', (tester) async {
    final auth = FakeAuthRepository();
    await pumpScreen(tester, const SignInScreen(from: '/cart'),
        userId: null, routes: ['/sign-in/verify'], overrides: [authRepositoryProvider.overrideWithValue(auth)]);
    await tester.enterText(find.byType(TextField), '98765 43210');
    auth.error = const AuthException('rate limit', statusCode: '429');
    await tester.tap(find.text('Get code'));
    await tester.pump();
    expect(find.text('Too many tries. Wait a minute and try again.'), findsOneWidget);

    auth.error = null;
    await tester.tap(find.text('Get code'));
    await tester.pumpAndSettle();
    expect(auth.calls.last, 'requestPhoneCode +919876543210');
    expect(find.text('Page /sign-in/verify?phone=%2B919876543210&from=%2Fcart'), findsOneWidget);
  });

  testWidgets('code step: the number with Change, auto-check on the 6th digit, wrong code cleared', (tester) async {
    final auth = FakeAuthRepository();
    await pumpScreen(tester, const VerifyCodeScreen(phone: '+919876543210'),
        overrides: [authRepositoryProvider.overrideWithValue(auth)]);
    expect(find.text('+91 98765 43210'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).autofillHints, [AutofillHints.oneTimeCode]);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), '111111');
    await tester.pump();
    expect(auth.calls, ['verifyPhoneCode +919876543210']);
    expect(find.text('That code is wrong or has expired. Check the SMS, or get a new code.'), findsNothing,
        reason: 'the fake throws a FormatException, not a refused code');

    auth.error = const AuthException('Token has expired or is invalid', code: 'otp_expired', statusCode: '403');
    await tester.enterText(find.byType(TextField), '222222');
    await tester.pump();
    expect(find.text('That code is wrong or has expired. Check the SMS, or get a new code.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty, reason: 'boxes cleared');

    auth.error = AuthRetryableFetchException();
    await tester.enterText(find.byType(TextField), '333333');
    await tester.pump();
    expect(find.text('You’re offline. Check your connection and try again.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget, reason: 'offline keeps the code for another go');
    await tester.pumpWidget(const SizedBox()); // stops the countdown
  });

  testWidgets('code step: resend after 60 s', (tester) async {
    final auth = FakeAuthRepository();
    await pumpScreen(tester, const VerifyCodeScreen(phone: '+919876543210'),
        overrides: [authRepositoryProvider.overrideWithValue(auth)]);
    expect(find.text('Resend code in 1:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Resend code in 0:30'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    await tester.tap(find.text('Resend code'));
    await tester.pump();
    expect(auth.calls, ['requestPhoneCode +919876543210']);
    expect(find.text('Resend code in 1:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('name step: a phone sign-up names itself once, then goes back to `from`', (tester) async {
    String? saved;
    final db = SupabaseClient('http://localhost', 'sb_publishable_test',
        httpClient: MockClient((r) async {
          saved = (jsonDecode(r.body) as Map)['full_name'] as String?;
          return http.Response('', 204, request: r);
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    await pumpScreen(tester, const NameScreen(from: '/cart'), routes: [
      '/cart',
    ], overrides: [
      supabaseProvider.overrideWithValue(db),
      profileProvider.overrideWith((ref) async => Profile(id: 'user-1', fullName: saved)),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('What should we call you?'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Enter your name.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ravi kumar');
    await tester.tap(find.text('Continue'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // the fake server
    await tester.pumpAndSettle();
    expect(saved, 'Ravi Kumar');
    expect(find.text('Page /cart'), findsOneWidget);
  });

  testWidgets('name step: a customer with a name passes straight through', (tester) async {
    await pumpScreen(tester, const NameScreen(from: '/cart'), routes: ['/cart'], overrides: [
      profileProvider.overrideWith((ref) async => const Profile(id: 'user-1', fullName: 'Asha')),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Page /cart'), findsOneWidget);
  });

  test('only a phone sign-in stops at the name step', () {
    expect(afterSignInPath('/cart', byPhone: true), '/welcome?from=%2Fcart');
    expect(afterSignInPath('/cart', byPhone: false), '/cart');
    expect(afterSignInPath('https://evil.example', byPhone: false), '/');
    expect(afterSignInPath(null, byPhone: true), '/welcome');
  });

  testWidgets('demo sheet: both test accounts, one tap each', (tester) async {
    final auth = FakeAuthRepository();
    await pumpScreen(tester, const Scaffold(body: DevLoginButtons()),
        overrides: [authRepositoryProvider.overrideWithValue(auth)]);
    await tester.tap(find.text('Use a test account'));
    await tester.pumpAndSettle();
    expect(find.text('DEV BUILD · TEST ACCOUNTS'), findsOneWidget);
    expect(find.text('Continue as test customer'), findsOneWidget);
    expect(find.text('Continue as test admin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
