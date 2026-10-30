// The repair flow on both sides against a fake Supabase backend: the customer approves or declines the quote, staff
// get the next allowed step for each state, and every button sends the RPC the server expects.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_repair_screen.dart';
import 'package:shyam_mobiles/features/admin/widgets/feedback_card.dart';
import 'package:shyam_mobiles/features/feedback/data/feedback.dart';
import 'package:shyam_mobiles/features/repairs/data/repairs.dart';
import 'package:shyam_mobiles/features/repairs/screens/repair_detail_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'layout_harness.dart';

typedef Call = (String fn, Map<String, dynamic> args);

/// A client whose RPCs are recorded in [calls]; [error] makes them fail with that code, as Postgres would.
SupabaseClient _fakeDb(List<Call> calls, {String? error}) => SupabaseClient(
      'http://localhost',
      'sb_publishable_test',
      httpClient: MockClient((r) async {
        calls.add((r.url.pathSegments.last, Map<String, dynamic>.from(jsonDecode(r.body) as Map)));
        return error == null
            ? http.Response('null', 200, request: r, headers: {'content-type': 'application/json'})
            : http.Response(jsonEncode({'code': 'P0001', 'message': error, 'details': null, 'hint': null}), 400,
                request: r, headers: {'content-type': 'application/json'});
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

Future<void> _customer(WidgetTester tester, RepairBooking b, List<Call> calls, {String? error}) => pumpScreen(
      tester,
      const RepairDetailScreen(bookingId: 'b1'),
      overrides: [
        supabaseProvider.overrideWithValue(_fakeDb(calls, error: error)),
        repairProvider.overrideWith((ref, id) => b),
      ],
    );

Future<void> _staff(WidgetTester tester, RepairBooking b, List<Call> calls, {FeedbackEntry? feedback}) => pumpScreen(
      tester,
      const AdminRepairScreen(bookingId: 'b1'),
      overrides: [
        supabaseProvider.overrideWithValue(_fakeDb(calls)),
        repairProvider.overrideWith((ref, id) => b),
        aboutFeedbackProvider.overrideWith((ref, key) => key == (FeedbackKind.repair, 'b1') ? feedback : null),
      ],
      routes: ['/admin/feedback/:id'],
    );

/// Scrolls to [finder] and taps it; the dialog or write after it is pumped through.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await scrollTo(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Records hold maps by identity; lists compare them by value.
List<List<Object?>> _plain(List<Call> calls) => [for (final c in calls) [c.$1, c.$2]];

Finder _dialogButton(String label) => find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()).first)
        .enabled;

void main() {
  group('customer', () {
    testWidgets('approves the price they see', (tester) async {
      final calls = <Call>[];
      await _customer(tester, testBooking(), calls);
      await _tap(tester, find.text('Approve'));
      expect(find.text('Approve ₹2,499?'), findsOneWidget);
      await tester.tap(_dialogButton('Approve'));
      await tester.pumpAndSettle();
      expect(_plain(calls), [['approve_repair_quote', {'p_booking_id': 'b1', 'p_quote_paise': 249900}]]);
      expect(find.text('Price approved'), findsOneWidget);
    });

    testWidgets('"Not now" changes nothing', (tester) async {
      final calls = <Call>[];
      await _customer(tester, testBooking(), calls);
      await _tap(tester, find.text('Approve'));
      await tester.tap(_dialogButton('Not now'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });

    testWidgets('declines with a reason, or without one', (tester) async {
      final calls = <Call>[];
      await _customer(tester, testBooking(), calls);
      await _tap(tester, find.text('Decline'));
      expect(find.text('Keep quote'), findsOneWidget, reason: 'the safe choice is the filled button');
      await tester.enterText(find.widgetWithText(TextField, 'Reason (optional)'), ' Too costly ');
      await tester.tap(_dialogButton('Decline'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Decline'));
      await tester.tap(_dialogButton('Decline'));
      await tester.pumpAndSettle();
      expect(_plain(calls), [
        ['decline_repair_quote', {'p_booking_id': 'b1', 'p_reason': 'Too costly'}],
        ['decline_repair_quote', {'p_booking_id': 'b1', 'p_reason': null}],
      ]);
    });

    testWidgets('a price changed meanwhile is explained', (tester) async {
      await _customer(tester, testBooking(), [], error: 'QUOTE_CHANGED');
      await _tap(tester, find.text('Approve'));
      await tester.tap(_dialogButton('Approve'));
      await tester.pumpAndSettle();
      expect(find.text('The store just changed the price. Check the new quote, then approve it.'), findsOneWidget);
    });

    testWidgets('an answered quote has no buttons, and says what happens next', (tester) async {
      await _customer(tester, testBooking(quoteStatus: RepairQuoteStatus.approved), []);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Price approved. We’ll start the repair soon.'), findsOneWidget);
      await _customer(tester, testBooking(quoteStatus: RepairQuoteStatus.declined), []);
      expect(find.text('Decline'), findsNothing);
      expect(find.textContaining('You declined the price.'), findsOneWidget);
    });
  });

  group('staff', () {
    testWidgets('requested: confirm', (tester) async {
      final calls = <Call>[];
      await _staff(tester, testBooking(status: RepairStatus.requested, quote: null), calls);
      await _tap(tester, find.text('Confirm booking'));
      expect(_plain(calls), [['admin_update_repair', {'p_booking_id': 'b1', 'p_status': 'confirmed', 'p_note': null}]]);
    });

    testWidgets('confirmed, quote waiting: start is off until the customer agrees', (tester) async {
      final calls = <Call>[];
      await _staff(tester, testBooking(), calls);
      expect(_enabled(tester, 'Start repair'), isFalse);
      expect(find.text('Waiting for the customer to approve ₹2,499.'), findsOneWidget);
      await _tap(tester, find.text('Customer agreed in person or by phone'));
      await tester.tap(_dialogButton('They agreed'));
      await tester.pumpAndSettle();
      expect(_plain(calls), [
        ['admin_set_repair_quote', {'p_booking_id': 'b1', 'p_quote_paise': 249900, 'p_note': null, 'p_approved': true}],
      ]);
    });

    testWidgets('confirmed, approved: start the repair', (tester) async {
      final calls = <Call>[];
      await _staff(tester, testBooking(quoteStatus: RepairQuoteStatus.approved), calls);
      expect(find.text('Customer agreed in person or by phone'), findsNothing);
      await _tap(tester, find.text('Start repair'));
      expect(calls.single.$2['p_status'], 'in_progress');
    });

    testWidgets('in repair: ready for pickup; ready: completed after a check', (tester) async {
      final calls = <Call>[];
      await _staff(tester, testBooking(status: RepairStatus.inProgress, quoteStatus: RepairQuoteStatus.approved), calls);
      await _tap(tester, find.text('Ready for pickup'));
      await _staff(tester, testBooking(status: RepairStatus.ready, quoteStatus: RepairQuoteStatus.approved), calls);
      expect(find.text('Change quote'), findsNothing, reason: 'no new price once it is ready');
      await _tap(tester, find.text('Mark completed'));
      await tester.tap(_dialogButton('Mark completed'));
      await tester.pumpAndSettle();
      expect([for (final c in calls) c.$2['p_status']], ['ready', 'completed']);
    });

    testWidgets('the customer\'s rating shows on the repair and opens the inbox entry', (tester) async {
      final calls = <Call>[];
      await _staff(tester, testBooking(status: RepairStatus.completed, quoteStatus: RepairQuoteStatus.approved), calls,
          feedback: FeedbackEntry(
            id: 'f1',
            kind: FeedbackKind.repair,
            status: FeedbackStatus.unread,
            createdAt: DateTime(2026, 10, 31, 12),
            rating: 4,
            message: 'Fixed in an hour, thank you',
            repairId: 'b1',
          ));
      await scrollTo(tester, find.text('Fixed in an hour, thank you'));
      expect(find.text('New'), findsOneWidget);
      await _tap(tester, find.text('Fixed in an hour, thank you'));
      expect(find.text('Page /admin/feedback/f1'), findsOneWidget);
      expect(calls, isEmpty, reason: 'looking at it changes nothing');
    });

    testWidgets('closed bookings offer no steps, only notes', (tester) async {
      for (final s in [RepairStatus.completed, RepairStatus.cancelled]) {
        await _staff(tester, testBooking(status: s, quoteStatus: RepairQuoteStatus.approved), []);
        expect(find.text('Cancel booking'), findsNothing, reason: s.value);
        expect(find.text('Mark completed'), findsNothing, reason: s.value);
        await scrollTo(tester, find.text('Send note'));
      }
    });

    testWidgets('cancel needs a reason, which the customer sees', (tester) async {
      final calls = <Call>[];
      await _staff(tester, testBooking(), calls);
      await _tap(tester, find.text('Cancel booking'));
      await tester.tap(_dialogButton('Cancel booking'));
      await tester.pump();
      expect(find.text('Add a short reason'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'Part not available');
      await tester.tap(_dialogButton('Cancel booking'));
      await tester.pumpAndSettle();
      expect(_plain(calls), [
        ['admin_update_repair', {'p_booking_id': 'b1', 'p_status': 'cancelled', 'p_note': 'Cancelled by the store: Part not available'}],
      ]);
    });

    testWidgets('sends a quote and a note', (tester) async {
      final calls = <Call>[];
      await _staff(tester, testBooking(status: RepairStatus.requested, quote: null), calls);
      await scrollTo(tester, find.widgetWithText(TextFormField, 'Price for the customer'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Price for the customer'), '1500');
      await _tap(tester, find.text('Send quote'));
      await scrollTo(tester, find.widgetWithText(TextField, 'Shown on their timeline'));
      await tester.enterText(find.widgetWithText(TextField, 'Shown on their timeline'), 'Bring the charger, please.');
      await _tap(tester, find.text('Send note'));
      expect(_plain(calls), [
        ['admin_set_repair_quote', {'p_booking_id': 'b1', 'p_quote_paise': 150000, 'p_note': null, 'p_approved': false}],
        ['admin_update_repair', {'p_booking_id': 'b1', 'p_status': 'requested', 'p_note': 'Bring the charger, please.'}],
      ]);
    });
  });
}
