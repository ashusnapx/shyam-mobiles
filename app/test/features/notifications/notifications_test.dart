// Notifications: grouping and times, every kind the database writes has its art (and its PNG), the screen (open, mark
// read, delete by button and by swipe, empty, photos), the bell's badge, the live banner (only when Android doesn't
// show notifications), Android notifications drawn by the app, the permission prompt, and the Firebase-off path.
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shyam_mobiles/core/push.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/core/theme/generative.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/core/widgets/widgets.dart' show ProductImage;
import 'package:shyam_mobiles/features/notifications/data/notifications.dart';
import 'package:shyam_mobiles/features/notifications/screens/notifications_screen.dart';
import 'package:shyam_mobiles/features/notifications/widgets/notification_art.dart';
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
  FakePush({this.granted = false});

  bool granted; // notifications allowed on the phone
  bool asked = false;

  @override
  bool get enabled => true;

  @override
  Future<bool> allowed() async => granted;

  @override
  Future<bool> ask() async => asked = true;
}

AppNotification note(String id,
        {String kind = 'order_packed', String title = 'SM1042 is packed', String? link = '/orders/o1', bool read = false,
        DateTime? at, String? image}) =>
    AppNotification(
      id: id,
      kind: kind,
      title: title,
      body: 'It ships soon. We’ll tell you when it’s on the way.',
      link: link,
      readAt: read ? DateTime(2026) : null,
      imagePath: image,
      createdAt: at ?? DateTime.now(),
    );

/// What the app asked Android to show.
class Posted {
  final calls = <({int id, String? title, String? body, AndroidNotificationDetails android, String? payload})>[];

  Future<void> call({required int id, String? title, String? body, NotificationDetails? notificationDetails, String? payload}) async =>
      calls.add((id: id, title: title, body: body, android: notificationDetails!.android!, payload: payload));
}

/// The whole app's frame: [home] at /, stand-in pages at /orders/:id and /notifications, the banner host on top.
Future<(ProviderContainer, GoRouter)> pumpApp(WidgetTester tester, FakeNotificationsApi api,
    {Widget home = const Scaffold(body: Text('Home')), PushService? push, PushAlerts? alerts}) async {
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
      if (alerts != null) pushAlertsProvider.overrideWithValue(alerts),
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

    test('every kind any migration writes has its art, and every art its PNG for Android', () {
      final sql = [
        for (final f in Directory('../supabase/migrations').listSync().whereType<File>()) f.readAsStringSync(),
      ].join();
      final kinds = {
        for (final m in RegExp(r"notify(?:_staff)?\((?:[^,()]+, )?'([a-z_]+)'").allMatches(sql)) m[1]!,
        // kinds picked in a CASE inside the call (coupons, feedback)
        for (final m in RegExp(r"(?:then|else) '((?:order|payment|repair|referral|staff)_[a-z_]+|coupon)'").allMatches(sql)) m[1]!,
      };
      expect(kinds.length, greaterThan(35));
      expect(kinds.difference(notificationArt.keys.toSet()), isEmpty);
      for (final a in {...notificationArt.values, defaultArt}) {
        expect(File(artAsset(a)).existsSync(), isTrue,
            reason: '${artAsset(a)}: render it with ART_OUT=assets/notification_art (test/preview/notification_art_test.dart)');
      }
      expect(artFor('something_new'), defaultArt); // a newer server kind still gets a picture
      expect({for (final g in ArtGroup.values) g.palette.accent}.length, ArtGroup.values.length, reason: 'eight colours');
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

    testWidgets('rows show the product photo when there is one, else the kind\'s illustration', (tester) async {
      api.rows = [note('p', image: 'p1/1730000000000.webp'), ...api.rows];
      await pumpScreen(tester, const NotificationsScreen(), overrides: [notificationsApiProvider.overrideWithValue(api)]);
      expect(find.byType(ProductImage), findsOneWidget);
      expect(tester.widget<ProductImage>(find.byType(ProductImage)).path, 'p1/1730000000000@thumb.webp');
      expect(find.byType(NotificationArt), findsNWidgets(3));
    });

    testWidgets('nothing yet', (tester) async {
      await pumpScreen(tester, const NotificationsScreen(),
          overrides: [notificationsApiProvider.overrideWithValue(FakeNotificationsApi())]);
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(tester.getSize(find.byType(NotificationArt)).width, 112, reason: 'the illustration is the hero');
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

  group('art', () {
    testWidgets('draws with less motion asked for: one still frame, no ticker', (tester) async {
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(textDirection: TextDirection.ltr, child: Center(child: NotificationArt(kind: 'order_refunded'))),
      ));
      expect(find.byType(AuroraBackground), findsOneWidget);
      expect(tester.widget<AuroraBackground>(find.byType(AuroraBackground)).still, isTrue);
      expect(find.byType(StatusBadge), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('Android notifications', () {
    final art = Uint8List.fromList([1, 2, 3]);
    final thumb = Uint8List.fromList([4, 5]);
    final full = Uint8List.fromList([6, 7, 8, 9]);

    test('a product photo: the thumb beside the words, the full photo when expanded', () async {
      final posted = Posted();
      final asked = <String>[];
      await PushAlerts(posted.call,
          download: (url) async {
            asked.add(url);
            return url.endsWith('@thumb.webp') ? thumb : full;
          },
          asset: (_) async => art).show(note('n1', kind: 'order_shipped', image: 'p1/1730000000000.webp'));
      final a = posted.calls.single.android;
      expect(asked.map((u) => u.split('/product-images/').last), ['p1/1730000000000@thumb.webp', 'p1/1730000000000.webp']);
      expect((a.largeIcon! as ByteArrayAndroidBitmap).data, thumb);
      expect(((a.styleInformation! as BigPictureStyleInformation).bigPicture as ByteArrayAndroidBitmap).data, full);
      expect(a.channelId, 'updates');
      expect(a.icon, 'ic_launcher_monochrome');
      expect(a.color, notificationColor('order_shipped'));
    });

    test('no photo: the illustration, and the whole text when expanded', () async {
      final posted = Posted();
      final assets = <String>[];
      await PushAlerts(posted.call, download: (_) async => fail('no photo, no download'), asset: (a) async {
        assets.add(a);
        return art;
      }).show(note('n1', kind: 'repair_quote'));
      final a = posted.calls.single.android;
      expect(assets, [artAsset(artFor('repair_quote'))]);
      expect((a.largeIcon! as ByteArrayAndroidBitmap).data, art);
      expect(a.styleInformation, isA<BigTextStyleInformation>());
    });

    test('a photo that won\'t download: the illustration instead, still one notification', () async {
      final posted = Posted();
      await PushAlerts(posted.call, download: (_) async => null, asset: (_) async => art)
          .show(note('n1', image: 'p1/1730000000000.webp'));
      expect((posted.calls.single.android.largeIcon! as ByteArrayAndroidBitmap).data, art);
      expect(posted.calls.single.android.styleInformation, isA<BigTextStyleInformation>());
    });

    test('a push carries what the notification needs', () {
      final n = notificationFromPush(const RemoteMessage(data: {
        'id': 'n1', 'kind': 'staff_low_stock', 'title': 'Low stock: Galaxy S25', 'body': 'Only 2 left.',
        'link': '/admin/products/p1', 'image_path': 'p1/1.webp',
      }));
      expect([n.id, n.kind, n.title, n.body, n.link, n.imagePath],
          ['n1', 'staff_low_stock', 'Low stock: Galaxy S25', 'Only 2 left.', '/admin/products/p1', 'p1/1.webp']);
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

    testWidgets('the banner shows the illustration', (tester) async {
      final api = FakeNotificationsApi();
      final (container, _) = await pumpApp(tester, api);
      api.rows = [note('n1', kind: 'repair_ready', title: 'Your Galaxy A56 is ready for pickup', link: null)];
      await container.read(unreadCountProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(find.byType(NotificationArt), findsOneWidget);
      expect(tester.getSize(find.byType(NotificationArt)).width, 40);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('with Android notifications on, the in-app banner stays away; the badge still counts', (tester) async {
      final api = FakeNotificationsApi();
      final (container, _) = await pumpApp(tester, api, push: FakePush(granted: true));
      api.rows = [note('n1')];
      await container.read(unreadCountProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(find.text('View'), findsNothing);
      expect(container.read(unreadCountProvider), 1);
    });

    testWidgets('a push while the app is open: an Android notification if allowed, else the banner', (tester) async {
      final api = FakeNotificationsApi();
      final posted = Posted();
      final push = FakePush(granted: true);
      final alerts = PushAlerts(posted.call, download: (_) async => null, asset: (_) async => Uint8List(4));
      final (container, _) = await pumpApp(tester, api, push: push, alerts: alerts);
      const m = RemoteMessage(data: {
        'id': 'n1', 'kind': 'order_shipped', 'title': 'SM1042 is on its way', 'body': 'Delhivery, tracking DL1.',
        'link': '/orders/o1',
      });
      api.rows = [note('n1', title: 'SM1042 is on its way')];
      await onForegroundPush(container, m);
      await tester.pumpAndSettle();
      expect(posted.calls.single.title, 'SM1042 is on its way');
      expect(posted.calls.single.payload, '{"id":"n1","link":"/orders/o1"}');
      expect(find.text('View'), findsNothing, reason: 'one alert per push');

      push.granted = false;
      await onForegroundPush(container, RemoteMessage(data: {...m.data, 'id': 'n2', 'title': 'SM1043 is packed'}));
      await tester.pumpAndSettle();
      expect(posted.calls, hasLength(1));
      expect(find.text('SM1043 is packed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
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

    testWidgets('push on: after the first order, Android asks once, with no dialog of ours first', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeNotificationsApi();
      final push = FakePush();
      final (container, _) = await pumpApp(tester, api, push: push);
      api.rows = [note('n1', kind: 'order_confirmed', title: 'SM1042 is confirmed')];
      await container.read(unreadCountProvider.notifier).refresh();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing, reason: 'one prompt only: Android\'s');
      expect(push.asked, isTrue);

      push.asked = false;
      api.rows = [note('n2', kind: 'repair_booked', title: 'Repair booked for your Galaxy A56'), ...api.rows];
      await container.read(unreadCountProvider.notifier).refresh();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(push.asked, isFalse, reason: 'asked once, whatever the answer');
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
