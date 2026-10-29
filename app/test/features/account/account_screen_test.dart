// Account at 360x800 dp with large text: signed out, the sign-in button comes first; signing out asks first.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/account/data/profile.dart';
import 'package:shyam_mobiles/features/account/screens/account_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repairs/layout_harness.dart';

void main() {
  testWidgets('signed out: Sign in is on screen without scrolling, store and policies below it', (tester) async {
    await pumpScreen(tester, const AccountScreen(), overrides: [currentUserProvider.overrideWithValue(null)]);
    expect(find.widgetWithText(FilledButton, 'Sign in').hitTestable(), findsOneWidget);
    expect(find.text('Data saver'), findsNothing); // automatic now, never a setting
    await tester.scrollUntilVisible(find.text('About & policies'), 300, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signing out asks first, with staying signed in as the filled choice', (tester) async {
    await pumpScreen(tester, const AccountScreen(), overrides: [
      currentUserProvider.overrideWithValue(const User(
        id: 'user-1',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-10-29T00:00:00Z',
        email: 'rahul@example.com',
      )),
      profileProvider.overrideWithValue(const AsyncData(null)),
    ]);
    expect(find.text('Data saver'), findsNothing);
    await tester.scrollUntilVisible(find.text('Sign out'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Sign out'), findsOneWidget); // the dialog's, in red
    await tester.tap(find.widgetWithText(FilledButton, 'Stay signed in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget); // still signed in
  });
}
