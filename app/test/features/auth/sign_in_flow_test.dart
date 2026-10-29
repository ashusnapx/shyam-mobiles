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
