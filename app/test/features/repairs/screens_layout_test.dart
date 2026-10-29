import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
      await scrollTo(tester, find.text('+91 98765 43210'));
      expect(find.text('+91 98765 43210'), findsOneWidget);
    });

    testWidgets('booking detail with quote lays out ($theme)', (tester) async {
      await pumpScreen(tester, const RepairDetailScreen(bookingId: 'b1'),
          dark: dark, overrides: [repairProvider.overrideWith((ref, id) => testBooking())]);
      expect(find.text('Confirmed'), findsWidgets);
      expect(find.text('Approve on WhatsApp'), findsOneWidget);
      await scrollTo(tester, find.text('Cancel booking'));
      expect(find.text('Cancel booking'), findsOneWidget);
    });

    testWidgets('bookings list lays out ($theme)', (tester) async {
      await pumpScreen(tester, const RepairsScreen(),
          dark: dark, overrides: [myRepairsProvider.overrideWithValue(AsyncData([testBooking()]))]);
      expect(find.text('RP100012'), findsOneWidget);
      expect(find.text('Book a repair'), findsOneWidget);
    });
  }
}
