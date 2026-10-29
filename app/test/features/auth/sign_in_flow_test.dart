import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/features/auth/screens/sign_in_screen.dart';
import 'package:shyam_mobiles/features/auth/screens/verify_code_screen.dart';

void main() {
  testWidgets('sign in rejects bad input before calling the server', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SignInScreen())));
    final semantics = tester.ensureSemantics();
    expect(tester.getSemantics(find.byType(TextField)).label, startsWith('Mobile number')); // visible label is a separate Text
    semantics.dispose();

    await tester.enterText(find.byType(TextField), '12345');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('Enter a 10-digit mobile number.'), findsOneWidget);

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a 10-digit mobile number.'), findsNothing);
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('phone field: 10 digits after +91, pasted numbers normalised, no 11th digit', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SignInScreen())));
    final field = find.byType(TextField);
    String text() => tester.widget<TextField>(field).controller!.text;

    await tester.enterText(field, '+91 98765-43210 (home)'); // pasted from a contact card
    expect(text(), '98765 43210');
    await tester.enterText(field, '98765 432101'); // an 11th digit typed at the end
    expect(text(), '98765 43210');
    await tester.enterText(field, '098765 43210');
    expect(text(), '98765 43210');
    await tester.enterText(field, '९८७६५४३२१०'); // Devanagari digits from a Hindi keyboard or SMS
    expect(text(), '98765 43210');
    await tester.enterText(field, 'abc');
    expect(text(), '');

    await tester.enterText(field, '51234 67890');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('Mobile numbers start with 6, 7, 8 or 9.'), findsOneWidget);

    final keyboard = tester.widget<TextField>(field);
    expect(keyboard.keyboardType, TextInputType.phone);
    expect(keyboard.autofillHints, [AutofillHints.telephoneNumberNational]);
  });

  testWidgets('email field: no spaces or invisible characters, validated before sending', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SignInScreen())));
    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    await tester.enterText(field, ' asha verma@gmail.com\u200B ');
    expect(tester.widget<TextField>(field).controller!.text, 'ashaverma@gmail.com');
    expect(tester.widget<TextField>(field).autocorrect, isFalse);
    await tester.enterText(field, 'asha@gmail');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('code screen: switch method after 30 s, resend after 60 s', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: VerifyCodeScreen(phone: '+919876543210'))));
    expect(find.textContaining('+91 98765 43210', findRichText: true), findsOneWidget);
    expect(find.text('Resend code in 1:00'), findsOneWidget);
    expect(find.textContaining('Use email instead'), findsNothing);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Resend code in 0:30'), findsOneWidget);
    expect(find.text('Didn’t get it? Use email instead'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Resend code'), findsOneWidget);
  });
}
