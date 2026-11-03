import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/features/feedback/data/feedback.dart';
import 'package:shyam_mobiles/features/repairs/data/repairs.dart';
import 'package:shyam_mobiles/features/repairs/screens/repair_detail_screen.dart';
import 'package:shyam_mobiles/features/repairs/screens/repair_form_screen.dart';
import 'package:shyam_mobiles/features/repairs/screens/repairs_screen.dart';

import 'layout_harness.dart';

void main() {
  for (final dark in [false]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('booking form lays out at 360dp, 1.3x ($theme)', (tester) async {
      await pumpScreen(tester, const RepairFormScreen(),
          dark: dark, overrides: [myPhoneProvider.overrideWithValue(const AsyncData('+919876543210'))]);
      expect(find.text('Book a repair'), findsOneWidget);
      expect(find.text('Speaker / mic'), findsOneWidget);
      expect(find.textContaining('Book for'), findsOneWidget);
      await tester.tap(find.text('Samsung'));
      await tester.tap(find.text('Water damage'));
      await tester.pump();
      // scroll to the bottom so every row gets laid out
      final phone = find.widgetWithText(TextFormField, 'Phone for updates');
      await scrollTo(tester, phone);
      expect(tester.widget<TextFormField>(phone).controller!.text, '98765 43210', reason: 'the 10 digits after a fixed +91');
    });

    testWidgets('booking detail with a quote to approve lays out ($theme)', (tester) async {
      await pumpScreen(tester, const RepairDetailScreen(bookingId: 'b1'),
          dark: dark, overrides: [repairProvider.overrideWith((ref, id) => testBooking())]);
      expect(find.text('Confirmed'), findsWidgets);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      await scrollTo(tester, find.text('Quote sent · ₹2,499'));
      expect(find.text('Bring the charger too, please.'), findsOneWidget, reason: 'staff notes are on the timeline');
      await scrollTo(tester, find.text('Cancel booking'));
      expect(find.text('Cancel booking'), findsOneWidget);
    });

    testWidgets('completed booking asks for a rating ($theme)', (tester) async {
      await pumpScreen(tester, const RepairDetailScreen(bookingId: 'b1'), dark: dark, overrides: [
        repairProvider.overrideWith(
            (ref, id) => testBooking(status: RepairStatus.completed, quoteStatus: RepairQuoteStatus.approved)),
        myFeedbackProvider.overrideWith((ref, key) => null),
      ]);
      expect(find.text('Approve'), findsNothing);
      await scrollTo(tester, find.text('How was your repair?'));
      expect(find.text('Cancel booking'), findsNothing);
    });

    testWidgets('bookings list lays out ($theme)', (tester) async {
      await pumpScreen(tester, const RepairsScreen(), dark: dark, overrides: [
        myRepairsProvider.overrideWithBuild((ref, _) => (items: [testBooking()], hasMore: true, moreFailed: true)),
      ]);
      expect(find.text('RP100012'), findsOneWidget, reason: 'your bookings come first');
      expect(find.text('Awaiting approval'), findsOneWidget);
      expect(find.text('Phone repair at Shyam Mobiles'), findsNothing, reason: 'no pitch above your own bookings');
      await scrollTo(tester, find.text('Couldn’t load more. Try again'));
      await scrollTo(tester, find.text('Book a repair · Free'));
      await scrollTo(tester, find.text('What we fix'));
    });

    testWidgets('signed out, the tab sells the service; a fix opens the form with it picked ($theme)', (tester) async {
      await pumpScreen(tester, const RepairsScreen(), dark: dark, routes: ['/repairs/new'], userId: null);
      expect(find.text('Phone repair at Shyam Mobiles'), findsOneWidget);
      expect(find.text('Book a repair · Free'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing, reason: 'sign-in is asked only when booking');
      for (final text in ['Charging port', 'How it works', 'No surprise price: work starts only after you approve']) {
        await scrollTo(tester, find.text(text));
      }
      expect(find.textContaining('Repair warranty'), findsNothing, reason: 'unconfirmed promises stay hidden');
      expect(find.textContaining('old part'), findsNothing);
      await tester.fling(find.byType(Scrollable).first, const Offset(0, 3000), 3000); // back to the top
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Battery'));
      await tester.tap(find.text('Battery'));
      await tester.pumpAndSettle();
      expect(find.text('Page /repairs/new?issue=battery'), findsOneWidget);
    });

    testWidgets('the form opens with the issue picked on the tab ($theme)', (tester) async {
      await pumpScreen(tester, const RepairFormScreen(issue: 'charging'),
          dark: dark, overrides: [myPhoneProvider.overrideWithValue(const AsyncData('+919876543210'))]);
      final tile = find.ancestor(of: find.text('Charging port'), matching: find.byType(Material)).first;
      expect(tester.widget<Material>(tile).color, lightScheme.primary, reason: 'picked: ink fill');
      expect(find.text('Free · No payment now'), findsOneWidget);
      expect(find.text('Nokia / LAVA'), findsOneWidget, reason: 'keypad phones are common in the shop');
    });
  }
}
