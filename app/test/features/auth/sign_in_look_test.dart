// The colourful sign-in at 360x800 dp and 1.4x text: the peacock hero, the benefit chips from the shop's settings,
// with and without the keyboard, and still when the phone asks for less motion.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/auth/screens/sign_in_screen.dart';
import 'package:shyam_mobiles/features/auth/screens/verify_code_screen.dart';

import '../repairs/layout_harness.dart';

Widget _still(Widget screen) =>
    Builder(builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: screen));

void main() {
  testWidgets('sign-in fits, with chips from the settings, and folds the hero for the keyboard', (tester) async {
    await pumpScreen(tester, const SignInScreen(), store: testSettings.copyWithReferral());
    await tester.pumpAndSettle(); // the hero's one drift and the mark's ripple
    expect(find.text('Welcome to\nShyam Mobiles'), findsOneWidget);
    expect(find.text('₹200 off your first order with a friend’s code'), findsOneWidget);
    expect(find.text('Free delivery from ₹999'), findsOneWidget);
    expect(find.text('Phone repairs at our shop'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
    expect(tester.takeException(), isNull);

    addTearDown(tester.view.resetViewInsets);
    for (var dp = 50; dp <= 300; dp += 50) {
      tester.view.viewInsets = FakeViewPadding(bottom: dp * 3.0); // the keyboard slides up over ~250 ms
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    expect(find.text('Welcome to\nShyam Mobiles'), findsNothing, reason: 'the compact bar while typing');
    expect(find.text('Free delivery from ₹999'), findsNothing, reason: 'the chips make room for the form');
    expect(find.text('Send code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chips hide when their values are missing', (tester) async {
    await pumpScreen(tester, const SignInScreen()); // referrals off in the test settings
    await tester.pumpAndSettle();
    expect(find.textContaining('friend’s code'), findsNothing);
    expect(find.text('Free delivery from ₹999'), findsOneWidget);

    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [storeSettingsProvider.overrideWith((ref) => Completer<StoreSettings>().future)], // still loading
      child: const MaterialApp(home: SignInScreen()),
    ));
    await tester.pump();
    expect(find.textContaining('Free delivery'), findsNothing);
    expect(find.text('Phone repairs at our shop'), findsNothing, reason: 'no settings: no chips at all');
    expect(find.text('Send code'), findsOneWidget);
  });

  testWidgets('reduced motion: no drift, no ripple, nothing left running', (tester) async {
    await pumpScreen(tester, _still(const SignInScreen()));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('Welcome to\nShyam Mobiles'), findsOneWidget);
  });

  testWidgets('the code screen carries the hero bar and fits', (tester) async {
    await pumpScreen(tester, const VerifyCodeScreen(phone: '+919876543210'));
    await tester.pumpAndSettle();
    expect(find.text('Shyam Mobiles'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Enter the code'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // stops the resend countdown
  });
}

extension on StoreSettings {
  StoreSettings copyWithReferral() => StoreSettings(
        deliveryFeePaise: deliveryFeePaise,
        freeDeliveryMinPaise: freeDeliveryMinPaise,
        codEnabled: codEnabled,
        codMaxPaise: codMaxPaise,
        storePhone: storePhone,
        storeAddress: storeAddress,
        storeHours: storeHours,
        repairNote: repairNote,
        returnsPolicy: returnsPolicy,
        referralEnabled: true,
        referralFriendPaise: 20000,
      );
}
