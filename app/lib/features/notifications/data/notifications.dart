import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/paging.dart';
import '../../../core/router.dart' show safeReturnPath;
import '../../../core/supabase.dart';
import '../../../core/widgets/widgets.dart' show TagTone;
import '../../admin/data/admin.dart';
import '../../feedback/data/feedback.dart' show feedbackNewCountProvider;
import '../../orders/data/orders.dart';
import '../../repairs/data/repairs.dart';

// Notifications (docs/SPEC.md "Notifications"): database triggers write one for every order, payment, repair, coupon,
// feedback and stock event, to the customer it's about and to each admin who has to act. People read, mark read and
// delete their own; nobody writes them from the app.

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    this.body = '',
    this.link,
    this.readAt,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        body: j['body'] as String? ?? '',
        link: j['link'] as String?,
        readAt: j['read_at'] == null ? null : DateTime.parse(j['read_at'] as String),
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  final String id;
  final String kind; // notifications.kind: picks the icon and colour
  final String title;
  final String body;
  final String? link; // an app route
  final DateTime? readAt;
  final DateTime createdAt;

  bool get unread => readAt == null;

  AppNotification markedRead() =>
      AppNotification(id: id, kind: kind, title: title, body: body, link: link, readAt: DateTime.now(), createdAt: createdAt);
}

/// Icon and tone per kind, by meaning: emerald done, gold needs you (or a deal), peacock news, red failed or cancelled.
/// Every kind the database writes (supabase/migrations/20261030000400_notifications.sql) is here; a test checks.
const notificationStyles = <String, (IconData, TagTone)>{
  'order_awaiting_payment': (PhosphorIconsRegular.hourglass, TagTone.deal),
  'order_confirmed': (PhosphorIconsRegular.checkCircle, TagTone.ok),
  'payment_received': (PhosphorIconsRegular.currencyInr, TagTone.ok),
  'payment_failed': (PhosphorIconsRegular.warningCircle, TagTone.bad),
  'order_late_payment': (PhosphorIconsRegular.arrowCounterClockwise, TagTone.info),
  'order_packed': (PhosphorIconsRegular.package, TagTone.info),
  'order_shipped': (PhosphorIconsRegular.truck, TagTone.info),
  'order_tracking': (PhosphorIconsRegular.mapPinLine, TagTone.info),
  'order_update': (PhosphorIconsRegular.chatCircleText, TagTone.info),
  'order_delivered': (PhosphorIconsRegular.sealCheck, TagTone.ok),
  'order_refunded': (PhosphorIconsRegular.arrowCounterClockwise, TagTone.ok),
  'order_cancelled': (PhosphorIconsRegular.xCircle, TagTone.bad),
  'order_expired': (PhosphorIconsRegular.clockCountdown, TagTone.bad),
  'repair_booked': (PhosphorIconsRegular.calendarCheck, TagTone.info),
  'repair_confirmed': (PhosphorIconsRegular.calendarCheck, TagTone.ok),
  'repair_quote': (PhosphorIconsRegular.receipt, TagTone.deal),
  'repair_quote_agreed': (PhosphorIconsRegular.handshake, TagTone.ok),
  'repair_started': (PhosphorIconsRegular.wrench, TagTone.info),
  'repair_update': (PhosphorIconsRegular.chatCircleText, TagTone.info),
  'repair_ready': (PhosphorIconsRegular.storefront, TagTone.deal),
  'repair_completed': (PhosphorIconsRegular.checkCircle, TagTone.ok),
  'repair_cancelled': (PhosphorIconsRegular.xCircle, TagTone.bad),
  'referral_welcome': (PhosphorIconsRegular.gift, TagTone.deal),
  'referral_reward': (PhosphorIconsRegular.gift, TagTone.deal),
  'coupon': (PhosphorIconsRegular.ticket, TagTone.deal),
  'staff_new_order': (PhosphorIconsRegular.shoppingBag, TagTone.deal),
  'staff_order_paid': (PhosphorIconsRegular.currencyInr, TagTone.deal),
  'staff_order_cancelled': (PhosphorIconsRegular.xCircle, TagTone.bad),
  'staff_refund_needed': (PhosphorIconsRegular.arrowCounterClockwise, TagTone.deal),
  'staff_new_repair': (PhosphorIconsRegular.wrench, TagTone.deal),
  'staff_quote_approved': (PhosphorIconsRegular.thumbsUp, TagTone.ok),
  'staff_quote_declined': (PhosphorIconsRegular.thumbsDown, TagTone.bad),
  'staff_repair_cancelled': (PhosphorIconsRegular.xCircle, TagTone.bad),
  'staff_feedback': (PhosphorIconsRegular.chatCircleText, TagTone.info),
  'staff_feedback_low': (PhosphorIconsRegular.star, TagTone.bad),
  'staff_low_stock': (PhosphorIconsRegular.warning, TagTone.deal),
  'staff_out_of_stock': (PhosphorIconsRegular.prohibit, TagTone.bad),
};

(IconData, TagTone) notificationStyle(String kind) => notificationStyles[kind] ?? (PhosphorIconsRegular.bell, TagTone.info);

enum DayGroup {
  today('Today'),
  yesterday('Yesterday'),
  earlier('Earlier');

  const DayGroup(this.label);
  final String label;

  static DayGroup of(DateTime at, DateTime now) {
    final a = at.toLocal(), n = now.toLocal();
    return switch (DateTime(n.year, n.month, n.day).difference(DateTime(a.year, a.month, a.day)).inDays) {
      <= 0 => today,
      1 => yesterday,
      _ => earlier,
    };
  }
}

/// Newest first, split under Today / Yesterday / Earlier (empty groups left out).
List<(DayGroup, List<AppNotification>)> groupByDay(List<AppNotification> items, DateTime now) => [
      for (final g in DayGroup.values)
        if (items.where((n) => DayGroup.of(n.createdAt, now) == g).toList() case final list when list.isNotEmpty) (g, list),
    ];

/// "Just now", "5 min ago", "3 h ago" today; the time yesterday; the date before that.
String timeAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'Just now';
  return switch (DayGroup.of(at, now)) {
    _ when d.inMinutes < 60 => '${d.inMinutes} min ago',
    DayGroup.today => '${d.inHours} h ago',
    DayGroup.yesterday => DateFormat('h:mm a').format(at.toLocal()),
    DayGroup.earlier => DateFormat('d MMM').format(at.toLocal()),
  };
}

class NotificationsApi {
  NotificationsApi(this._db);

  final SupabaseClient _db;

  // RLS: only the caller's own rows, so no user filter (staff don't see other people's either)
  Future<List<AppNotification>> page(int from, int size) async => [
        for (final r in await _db
            .from('notifications')
            .select()
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .range(from, from + size - 1))
          AppNotification.fromJson(r),
      ];

  Future<int> unread() => _db.rpc<int>('unread_notifications');

  Future<AppNotification?> newestUnread() async {
    final row = await _db
        .from('notifications')
        .select()
        .isFilter('read_at', null)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : AppNotification.fromJson(row);
  }

  /// [ids] null: all of mine.
  Future<void> markRead([List<String>? ids]) => _db.rpc<void>('mark_notifications_read', params: {'p_ids': ids});

  Future<void> delete(String id) => _db.from('notifications').delete().eq('id', id);
}

final notificationsApiProvider = Provider<NotificationsApi>((ref) => NotificationsApi(ref.watch(supabaseProvider)));

final notificationsProvider =
    AsyncNotifierProvider.autoDispose<NotificationsNotifier, Paged<AppNotification>>(NotificationsNotifier.new);

class NotificationsNotifier extends PagedNotifier<AppNotification> {
  @override
  Object idOf(AppNotification n) => n.id;

  @override
  Future<Paged<AppNotification>> build() {
    ref.watch(currentUserIdProvider);
    return super.build();
  }

  @override
  Future<List<AppNotification>> fetch(int from, int size) async =>
      ref.read(currentUserIdProvider) == null ? const [] : ref.read(notificationsApiProvider).page(from, size);
}

/// The bell's number, kept fresh while the app is in front: every 45 s, on resume, and right after any write the app
/// sends (an order, a cancel, a booking, a quote answer: TimeoutClient.onWrite). A rise puts the newest one in the
/// banner and refreshes the screen it's about. shortcut: polling, because the local stack runs without Supabase
/// Realtime to save RAM; a Realtime subscription to inserts on `notifications` (`user_id=eq.<me>`) could replace the
/// timer once Realtime is on.
final unreadCountProvider = NotifierProvider<UnreadCount, int>(UnreadCount.new);

class UnreadCount extends Notifier<int> {
  static const every = Duration(seconds: 45);

  Timer? _timer;
  Timer? _soon;
  int? _known; // the last count seen; the first load is never "new"

  @override
  int build() {
    final uid = ref.watch(currentUserIdProvider);
    _known = null;
    ref.onDispose(() {
      _timer?.cancel();
      _soon?.cancel();
      if (TimeoutClient.onWrite == _afterWrite) TimeoutClient.onWrite = null;
    });
    if (uid == null) return 0;
    final life = AppLifecycleListener(
      onResume: () {
        _start();
        unawaited(refresh());
      },
      onHide: () => _timer?.cancel(),
    );
    ref.onDispose(life.dispose);
    TimeoutClient.onWrite = _afterWrite;
    _start();
    Future.microtask(refresh);
    return 0;
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => refresh());
  }

  // The app's own requests: its reads of this, marking read and deleting aren't news.
  void _afterWrite(Uri url) {
    final p = url.path;
    if (!(p.contains('/rest/v1/') || p.contains('/functions/v1/')) ||
        p.contains('notification') ||
        p.endsWith('/register_device')) {
      return;
    }
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 600), refresh);
  }

  Future<void> refresh() async {
    if (ref.read(currentUserIdProvider) == null) return;
    final int n;
    try {
      n = await ref.read(notificationsApiProvider).unread();
    } catch (_) {
      return; // offline: the next tick tries again
    }
    if (!ref.mounted) return;
    final rose = _known != null && n > _known!;
    _known = n;
    state = n;
    if (rose) await _announce();
  }

  /// Opens what [n] is about and marks it read (the list, the banner, a push tap). Only app routes are followed.
  Future<void> open(GoRouter router, AppNotification n) async {
    if (safeReturnPath(n.link) case final link?) unawaited(router.push(link));
    if (!n.unread || n.id.isEmpty) return;
    try {
      await ref.read(notificationsApiProvider).markRead([n.id]);
    } catch (_) {
      return; // stays unread; nothing lost
    }
    await refresh();
  }

  /// After marking read or deleting here: the badge follows without a round trip.
  void set(int n) => state = _known = n < 0 ? 0 : n;

  Future<void> _announce() async {
    ref.invalidate(notificationsProvider);
    final AppNotification? newest;
    try {
      newest = await ref.read(notificationsApiProvider).newestUnread();
    } catch (_) {
      return;
    }
    if (newest == null || !ref.mounted) return;
    _refreshScreen(newest.link);
    ref.read(notificationBannerProvider.notifier).show(newest);
  }

  // the order, repair or admin screen the notification is about shows the new state when opened (or at once)
  void _refreshScreen(String? link) {
    switch (Uri.tryParse(link ?? '')?.pathSegments) {
      case ['orders', final id]:
        ref
          ..invalidate(orderProvider(id))
          ..invalidate(ordersProvider);
      case ['repairs', final id]:
        ref
          ..invalidate(repairProvider(id))
          ..invalidate(myRepairsProvider);
      case ['admin', 'orders', final id]:
        ref
          ..invalidate(adminOrderProvider(id))
          ..invalidate(adminOrdersProvider)
          ..invalidate(adminDashboardProvider)
          ..invalidate(needsActionProvider);
      case ['admin', 'repairs', _]:
        ref
          ..invalidate(adminRepairsProvider)
          ..invalidate(adminDashboardProvider)
          ..invalidate(needsActionProvider);
      case ['admin', 'feedback', _]:
        ref.invalidate(feedbackNewCountProvider);
      case ['admin', 'products', _]:
        ref.invalidate(adminDashboardProvider);
      default:
    }
  }
}

/// The one notification on show at the top of the screen (lib/features/notifications/widgets): never a stack.
final notificationBannerProvider = NotifierProvider<NotificationBanner, AppNotification?>(NotificationBanner.new);

class NotificationBanner extends Notifier<AppNotification?> {
  String? _lastId; // a push and the next poll can bring the same one

  @override
  AppNotification? build() => null;

  void show(AppNotification n) {
    if (n.id.isNotEmpty && n.id == _lastId) return;
    _lastId = n.id;
    state = n;
  }

  void dismiss() => state = null;
}

