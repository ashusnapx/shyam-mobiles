// Notifications: grouping and times, every kind the database writes has a style, the screen (open, mark read, delete
// by button and by swipe, empty), the bell's badge, the live banner, the push explainer, and the Firebase-off path.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shyam_mobiles/core/push.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/features/notifications/data/notifications.dart';
import 'package:shyam_mobiles/features/notifications/screens/notifications_screen.dart';
import 'package:shyam_mobiles/features/notifications/widgets/notification_widgets.dart';

import '../repairs/layout_harness.dart';

class FakeNotificationsApi implements NotificationsApi {
  FakeNotificationsApi([List<AppNotification>? rows]) : rows = rows ?? [];

  List<AppNotification> rows;
  int? count; // unread_notifications; null: counted from rows
  final marked = <List<String>?>[];
  final deleted = <String>[];
  int counts = 0;

  @override
  Future<List<AppNotification>> page(int from, int size) async => rows.skip(from).take(size).toList();

  @override
  Future<int> unread() async {
    counts++;
    return count ?? rows.where((n) => n.unread).length;
  }

  @override
  Future<AppNotification?> newestUnread() async => rows.where((n) => n.unread).firstOrNull;

  // like the server: what's marked or deleted stays so on the next read
  @override
  Future<void> markRead([List<String>? ids]) async {
    marked.add(ids);
    rows = [for (final n in rows) ids == null || ids.contains(n.id) ? n.markedRead() : n];
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    rows = [for (final n in rows) if (n.id != id) n];
  }
}

class FakePush implements PushService {
  bool asked = false;

  @override
  bool get enabled => true;

  @override
  Future<bool> allowed() async => false;

  @override
  Future<bool> ask() async => asked = true;
}

AppNotification note(String id,
        {String kind = 'order_packed', String title = 'SM1042 is packed', String? link = '/orders/o1', bool read = false,
        DateTime? at}) =>
    AppNotification(
      id: id,
      kind: kind,
      title: title,
      body: 'It ships soon. We’ll tell you when it’s on the way.',
      link: link,
      readAt: read ? DateTime(2026) : null,
      createdAt: at ?? DateTime.now(),
    );

/// The whole app's frame: [home] at /, stand-in pages at /orders/:id and /notifications, the banner host on top.
Future<(ProviderContainer, GoRouter)> pumpApp(WidgetTester tester, FakeNotificationsApi api,
    {Widget home = const Scaffold(body: Text('Home')), PushService? push}) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => home),
    GoRoute(path: '/orders/:id', builder: (_, s) => Scaffold(body: Text('Page ${s.uri}'))),
    GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
  ]);
  // a ProviderScope (not a container we own) so the poll's timer goes with the widget tree
  await tester.pumpWidget(ProviderScope(
    retry: noAutoRetry,
    overrides: [
      currentUserIdProvider.overrideWithValue('user-1'),
      notificationsApiProvider.overrideWithValue(api),
      if (push != null) pushServiceProvider.overrideWithValue(push),
    ],
    child: MaterialApp.router(
      theme: ThemeData(colorScheme: lightScheme),
      routerConfig: router,
      builder: (_, child) => NotificationBannerHost(router: router, child: child!),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return (ProviderScope.containerOf(tester.element(find.byType(NotificationBannerHost))), router);
}

void main() {
  group('grouping and times', () {
    final now = DateTime(2026, 10, 30, 18);

    test('Today, Yesterday, Earlier; empty groups left out', () {
      final rows = [
        note('a', at: DateTime(2026, 10, 30, 9)),
        note('b', at: DateTime(2026, 10, 29, 23, 59)),
        note('c', at: DateTime(2026, 10, 2)),
      ];
      expect([for (final (g, l) in groupByDay(rows, now)) '${g.label} ${l.map((n) => n.id).join()}'],
          ['Today a', 'Yesterday b', 'Earlier c']);
      expect([for (final (g, _) in groupByDay([rows[2]], now)) g], [DayGroup.earlier]);
    });

    test('relative times', () {
      expect(timeAgo(now.subtract(const Duration(seconds: 20)), now), 'Just now');
      expect(timeAgo(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
      expect(timeAgo(DateTime(2026, 10, 30, 15), now), '3 h ago');
      expect(timeAgo(DateTime(2026, 10, 29, 21, 5), now), '9:05 PM');
      expect(timeAgo(DateTime(2026, 10, 2), now), '2 Oct');
    });

    test('every kind the database writes has an icon and a tone', () {
      final sql = File('../supabase/migrations/20261030000400_notifications.sql').readAsStringSync();
      final kinds = {
        for (final m in RegExp(r"'((?:order|payment|repair|referral|staff)_[a-z_]+|coupon)'").allMatches(sql)) m[1]!,
      };
      expect(kinds.length, greaterThan(30));
      expect(kinds.difference(notificationStyles.keys.toSet()), isEmpty);
      expect(notificationStyle('order_cancelled').$2, notificationStyle('staff_out_of_stock').$2); // both red
      expect(notificationStyle('something_new').$1, isNotNull); // a newer server kind still shows
    });
  });

  group('screen', () {
    late FakeNotificationsApi api;
    setUp(() => api = FakeNotificationsApi([
          note('n1', title: 'SM1042 is packed'),
          note('n2', kind: 'repair_quote', title: '₹200 quote for your Galaxy A56 screen: approve to start',
              link: '/repairs/r1', at: DateTime.now().subtract(const Duration(days: 1))),
          note('n3', kind: 'order_cancelled', title: 'SM1001 was cancelled by the shop', read: true,
              at: DateTime.now().subtract(const Duration(days: 9))),
        ]));

    testWidgets('grouped rows; tap marks read and opens the link', (tester) async {
      await pumpScreen(tester, const NotificationsScreen(),
          overrides: [notificationsApiProvider.overrideWithValue(api)], routes: ['/orders/:id']);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Earlier'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Unread')), findsNWidgets(2));
      expect(find.text('Mark all read'), findsOneWidget);
      expect(find.byTooltip('Delete notification'), findsNWidgets(3)); // a button on every row, not swipe only

      await tester.tap(find.text('SM1042 is packed'));
      await tester.pumpAndSettle();
      expect(api.marked, [
        ['n1'],
      ]);
      expect(find.text('Page /orders/o1'), findsOneWidget);
    });

    testWidgets('mark all read', (tester) async {
      await pumpScreen(tester, const NotificationsScreen(), overrides: [notificationsApiProvider.overrideWithValue(api)]);
      await tester.tap(find.text('Mark all read'));
      await tester.pump();
      expect(api.marked, [null]);
      expect(find.bySemanticsLabel(RegExp('Unread')), findsNothing);
      expect(find.text('Mark all read'), findsNothing);
    });

    testWidgets('delete by button and by swipe', (tester) async {
      await pumpScreen(tester, const NotificationsScreen(), overrides: [notificationsApiProvider.overrideWithValue(api)]);
      await tester.tap(find.byTooltip('Delete notification').first);
      await tester.pump();
      expect(api.deleted, ['n1']);
      expect(find.text('SM1042 is packed'), findsNothing);

      await tester.drag(find.text('SM1001 was cancelled by the shop'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(api.deleted, ['n1', 'n3']);
      expect(find.text('SM1001 was cancelled by the shop'), findsNothing);
    });

    testWidgets('nothing yet', (tester) async {
      await pumpScreen(tester, const NotificationsScreen(),
          overrides: [notificationsApiProvider.overrideWithValue(FakeNotificationsApi())]);
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(find.text('Mark all read'), findsNothing);
    });

    testWidgets('a link that isn''t an app route is never followed', (tester) async {
      api.rows = [note('x', link: 'https://example.com/phish')];
      await pumpScreen(tester, const NotificationsScreen(), overrides: [notificationsApiProvider.overrideWithValue(api)]);
      await tester.tap(find.text('SM1042 is packed'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(api.marked, [
        ['x'],
      ]);
    });
  });

  group('live', () {
    testWidgets('the bell shows the unread count in a badge', (tester) async {
      final api = FakeNotificationsApi()..count = 3;
      await pumpApp(tester, api, home: const Scaffold(body: Center(child: NotificationBell())));
      expect(find.byTooltip('Notifications, 3 unread'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(tester.getSize(find.byType(IconButton)).height, greaterThanOrEqualTo(48));

      await tester.tap(find.byType(NotificationBell));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });

    testWidgets('a new one slides in with View, one at a time, and leaves after 5 s', (tester) async {
      final api = FakeNotificationsApi([note('old', read: true)]);
      final (container, _) = await pumpApp(tester, api);
      expect(container.read(unreadCountProvider), 0);
      expect(find.text('View'), findsNothing, reason: 'the first count is never news');

      api.rows = [note('n1', title: 'SM1042 is packed'), ...api.rows];
      await container.read(unreadCountProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(container.read(unreadCountProvider), 1);
      expect(find.text('SM1042 is packed'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);

      api.rows = [note('n2', title: 'SM1043 is on its way'), ...api.rows];
      await container.read(unreadCountProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(find.text('View'), findsOneWidget, reason: 'never a stack');
      expect(find.text('SM1043 is on its way'), findsOneWidget);
      expect(find.text('SM1042 is packed'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('View'), findsNothing);
    });

    testWidgets('View opens it and marks it read', (tester) async {
      final api = FakeNotificationsApi();
      final (container, _) = await pumpApp(tester, api);
      api.rows = [note('n1')];
      await container.read(unreadCountProvider.notifier).refresh();
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.text('Page /orders/o1'), findsOneWidget);
      expect(find.text('View'), findsNothing);
      expect(api.marked, [
        ['n1'],
      ]);
    });

    testWidgets('it checks right after the user does something', (tester) async {
      final api = FakeNotificationsApi();
      await pumpApp(tester, api);
      final before = api.counts;
      TimeoutClient.onWrite!(Uri.parse('http://x/rest/v1/rpc/mark_notifications_read'));
      TimeoutClient.onWrite!(Uri.parse('http://x/auth/v1/token'));
      await tester.pump(const Duration(seconds: 1));
      expect(api.counts, before, reason: 'its own calls and sign-in refreshes are not news');
      TimeoutClient.onWrite!(Uri.parse('http://x/rest/v1/rpc/place_order'));
      await tester.pump(const Duration(seconds: 1));
      expect(api.counts, before + 1);
    });

    testWidgets('Firebase off (no FIREBASE_* defines): no push, no explainer, the app still runs', (tester) async {
      expect(pushConfigured, isFalse);
      final api = FakeNotificationsApi();
      final (container, _) = await pumpApp(tester, api);
      await startPush(container); // returns at once: Firebase is never touched
      expect(container.read(pushServiceProvider).enabled, isFalse);
      api.rows = [note('n1', kind: 'order_confirmed', title: 'SM1042 is confirmed')];
      await container.read(unreadCountProvider.notifier).refresh();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Get updates on your phone?'), findsNothing);
      expect(find.text('SM1042 is confirmed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('push on: after the first order, a short explainer before Android asks, once', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeNotificationsApi();
      final push = FakePush();
      final (container, _) = await pumpApp(tester, api, push: push);
      api.rows = [note('n1', kind: 'order_confirmed', title: 'SM1042 is confirmed')];
      await container.read(unreadCountProvider.notifier).refresh();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Get updates on your phone?'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(push.asked, isTrue);

      push.asked = false;
      api.rows = [note('n2', kind: 'repair_booked', title: 'Repair booked for your Galaxy A56'), ...api.rows];
      await container.read(unreadCountProvider.notifier).refresh();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Get updates on your phone?'), findsNothing, reason: 'asked once, whatever the answer');
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
