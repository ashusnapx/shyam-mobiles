// Campaign calendar screen at 360x800 dp with large text: the month grid (today ringed, event dots, offer bars,
// spoken labels), the day agenda with "Create offer" and the offers that day, the upcoming list, the dashboard nudge.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/campaign_calendar.dart';
import 'package:shyam_mobiles/features/admin/data/offers_admin.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_calendar_screen.dart';

import '../repairs/layout_harness.dart';

void main() {
  final feed = parseIcs(File('test/fixtures/holidays_in_india_2026.ics').readAsStringSync());
  final now = DateTime.utc(2026, 11, 19, 4, 30); // 10:00 IST, Men’s Day
  final menSale = Promotion(id: 'm1', title: 'Men’s Day sale', code: 'MEN5', kind: OfferKind.percent, value: 5,
      startsAt: DateTime.utc(2026, 11, 18, 18, 30), endsAt: DateTime.utc(2026, 11, 19, 18, 29), autoApply: true);
  Future<void> pump(WidgetTester tester, Widget screen, List<Promotion> offers) => pumpScreen(tester, screen,
      routes: ['/admin/offers/new', '/admin/calendar'],
      overrides: [
        holidayFeedProvider.overrideWith((ref) async => feed),
        calendarNowProvider.overrideWithValue(now),
        adminPromotionsProvider.overrideWith((ref) async => offers),
      ]);
  Finder cell(String label) => find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith(label));

  testWidgets('the month: events as dots, offers as bars, every day spoken', (tester) async {
    await pump(tester, const AdminCalendarScreen(), [menSale]);
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    final men = tester.widget<Semantics>(cell('Thursday 19 November'));
    expect(men.properties.label, 'Thursday 19 November, today, Men’s Day, 1 offer on');
    expect(tester.widget<Semantics>(cell('Sunday 8 November')).properties.label,
        'Sunday 8 November, Diwali/Deepavali, Naraka Chaturdasi, no offer planned');
    expect(find.descendant(of: cell('Thursday 19 November'), matching: find.byKey(const ValueKey('bar 0'))), findsOneWidget);
    expect(find.descendant(of: cell('Sunday 8 November'), matching: find.byKey(const ValueKey('dot Diwali/Deepavali'))), findsOneWidget);
    expect(find.descendant(of: cell('Friday 20 November'), matching: find.byKey(const ValueKey('bar 0'))), findsNothing);
    expect(tester.getSize(cell('Friday 20 November')).height, greaterThanOrEqualTo(48));
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('December 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a day’s agenda: its events with Create offer, and the offers on it', (tester) async {
    await pump(tester, const AdminCalendarScreen(), [menSale]);
    await tester.pumpAndSettle();
    await tester.tap(cell('Thursday 19 November'));
    await tester.pumpAndSettle();
    expect(find.text('Thursday, 19 November'), findsOneWidget);
    expect(find.text('Men’s Day sale'), findsOneWidget);
    expect(find.text('MEN5 · 5% off · applies itself'), findsOneWidget);
    expect(find.byTooltip('Pause Men’s Day sale'), findsOneWidget);
    expect(find.byTooltip('Delete Men’s Day sale'), findsOneWidget);
    expect(find.descendant(of: find.byType(DaySheet), matching: find.text('Wedding season')), findsOneWidget); // seasons: agenda, not dots
    await tester.tap(find.text('Create offer').first);
    await tester.pumpAndSettle();
    expect(find.text('Page /admin/offers/new'), findsOneWidget);
  });

  testWidgets('upcoming: the next 45 days, planned or not', (tester) async {
    await pump(tester, const AdminCalendarScreen(), [menSale]);
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Guru Nanak Jayanti'));
    expect(find.text('Offer planned'), findsWidgets);
    await scrollTo(tester, find.text('Christmas'));
    expect(find.text('Christmas'), findsOneWidget);
    expect(find.textContaining('Republic Day'), findsNothing); // past 45 days
  });

  testWidgets('dashboard nudge only when a big day ≤ 7 days away has no offer', (tester) async {
    await pump(tester, const Scaffold(body: NextEventCard()), const []);
    await tester.pumpAndSettle();
    expect(find.text('Next: Men’s Day today'), findsOneWidget);
    await tester.tap(find.text('Next: Men’s Day today'));
    await tester.pumpAndSettle();
    expect(find.text('Page /admin/calendar'), findsOneWidget);
    await pump(tester, const Scaffold(body: NextEventCard()), [menSale]);
    await tester.pumpAndSettle();
    expect(find.text('Next: Guru Nanak Jayanti in 5 days'), findsOneWidget);
  });
}
