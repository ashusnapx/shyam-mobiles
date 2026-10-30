import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/notifications/data/notifications.dart';
import '../features/notifications/widgets/notification_art.dart';
import 'env.dart';
import 'router.dart';
import 'supabase.dart';
import 'theme/generative.dart' show seedHash;

// Phone notifications (FCM), off unless the build has the FIREBASE_* defines (docs/LAUNCH.md). Without them nothing
// here touches Firebase: no google-services.json, no Gradle plugin, and the app shows notifications only inside the
// app (the slide-in banner). With them: the phone's token goes to register_device after sign-in (once notifications
// are allowed). Pushes are data-only (supabase/functions/send-push), so the app draws every Android notification
// itself, in the foreground and in the background handler: the product photo or the kind's illustration, its colour,
// and a tap opens its screen. While Android shows them, the in-app banner stays away; it's for phones that said no.

const pushConfigured = Env.firebaseApiKey != '' &&
    Env.firebaseAppId != '' &&
    Env.firebaseMessagingSenderId != '' &&
    Env.firebaseProjectId != '';

/// What the permission explainer needs; NoPush when Firebase is off (and in tests).
abstract class PushService {
  bool get enabled;

  /// Notifications already allowed on this phone (Android 12 and older: always).
  Future<bool> allowed();

  /// The system prompt (Android 13+); true when allowed. Registers the phone if so.
  Future<bool> ask();
}

class NoPush implements PushService {
  const NoPush();

  @override
  bool get enabled => false;

  @override
  Future<bool> allowed() async => false;

  @override
  Future<bool> ask() async => false;
}

class _FirebasePush implements PushService {
  _FirebasePush(this._db);

  final SupabaseClient _db;
  final _fcm = FirebaseMessaging.instance;

  @override
  bool get enabled => true;

  @override
  Future<bool> allowed() async =>
      (await _fcm.getNotificationSettings()).authorizationStatus == AuthorizationStatus.authorized;

  @override
  Future<bool> ask() async {
    final ok = (await _fcm.requestPermission()).authorizationStatus == AuthorizationStatus.authorized;
    if (ok) await register();
    return ok;
  }

  /// This phone's token for the signed-in user; the server moves it here if someone else had it.
  /// shortcut: FCM registration tokens, deprecated in firebase_messaging 17 for FID registration (register() /
  /// onRegistered); move over once send-push targets installation IDs instead of `message.token`.
  Future<void> register([String? token]) async {
    if (_db.auth.currentSession == null || !await allowed()) return;
    token ??= await _fcm.getToken(); // ignore: deprecated_member_use
    if (token != null) await _db.rpc<void>('register_device', params: {'p_token': token});
  }
}

PushService _push = const NoPush();

final pushServiceProvider = Provider<PushService>((ref) => _push);

typedef PostNotification = Future<void> Function({
  required int id,
  String? title,
  String? body,
  NotificationDetails? notificationDetails,
  String? payload,
});

/// Draws one notification on Android: the product photo beside the words (the full photo when expanded), else the
/// kind's illustration, in the kind's colour with the monochrome feather in the status bar. A photo that doesn't
/// download in 5 s leaves the illustration, never a missing notification.
class PushAlerts {
  PushAlerts(this._post, {Future<Uint8List?> Function(String url)? download, Future<Uint8List?> Function(String asset)? asset})
      : _download = download ?? _get,
        _asset = asset ?? _load;

  final PostNotification _post;
  final Future<Uint8List?> Function(String url) _download;
  final Future<Uint8List?> Function(String asset) _asset;

  static const channel = AndroidNotificationChannel('updates', 'Updates',
      description: 'Your orders, repairs, quotes and offers', importance: Importance.high);

  static Future<Uint8List?> _get(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      return r.statusCode == 200 && r.bodyBytes.isNotEmpty ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _load(String asset) async {
    try {
      return (await rootBundle.load(asset)).buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> show(AppNotification n) async {
    final path = n.imagePath;
    final thumb = path == null ? null : await _download(publicImageUrl(thumbPathFor(path) ?? path));
    final photo = path == null || thumbPathFor(path) == null ? thumb : await _download(publicImageUrl(path)) ?? thumb;
    final icon = thumb ?? await _asset(artAsset(artFor(n.kind)));
    final large = icon == null ? null : ByteArrayAndroidBitmap(icon);
    await _post(
      id: seedHash(n.id) & 0x7fffffff, // the same notification again replaces it
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_launcher_monochrome',
          color: notificationColor(n.kind),
          largeIcon: large,
          styleInformation: photo == null
              ? BigTextStyleInformation(n.body)
              : BigPictureStyleInformation(ByteArrayAndroidBitmap(photo),
                  largeIcon: large, hideExpandedLargeIcon: true, contentTitle: n.title, summaryText: n.body),
        ),
      ),
      payload: jsonEncode({'id': n.id, 'link': n.link}),
    );
  }
}

PushAlerts? _alerts;

/// Null while push is off.
final pushAlertsProvider = Provider<PushAlerts?>((ref) => _alerts);

const _androidSettings = InitializationSettings(android: AndroidInitializationSettings('ic_launcher_monochrome'));

/// A push while the app is closed or in the background: FCM wakes this in its own isolate.
@pragma('vm:entry-point')
Future<void> showPushInBackground(RemoteMessage m) async {
  try {
    WidgetsFlutterBinding.ensureInitialized(); // the illustration comes from the asset bundle
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: _androidSettings);
    await PushAlerts(plugin.show).show(notificationFromPush(m));
  } catch (_) {} // no logging (release_safety_test); the notification is still in the app's list
}

/// A push while the app is open: Android shows it the same way if notifications are allowed, else the in-app banner.
@visibleForTesting
Future<void> onForegroundPush(ProviderContainer c, RemoteMessage m) async {
  final n = notificationFromPush(m);
  final alerts = c.read(pushAlertsProvider);
  if (alerts != null && await c.read(pushServiceProvider).allowed().catchError((Object _) => false)) {
    await alerts.show(n).catchError((Object _) {});
  } else {
    c.read(notificationBannerProvider.notifier).show(n);
  }
  await c.read(unreadCountProvider.notifier).refresh();
}

AppNotification notificationFromPush(RemoteMessage m) => AppNotification(
      id: m.data['id'] as String? ?? '',
      kind: m.data['kind'] as String? ?? '',
      title: m.data['title'] as String? ?? m.notification?.title ?? '',
      body: m.data['body'] as String? ?? m.notification?.body ?? '',
      link: m.data['link'] as String?,
      imagePath: m.data['image_path'] as String?,
      createdAt: m.sentTime ?? DateTime.now(),
    );

/// A tap on one of our notifications: open its screen and mark it read.
void _openPayload(ProviderContainer c, String? payload) {
  try {
    final p = jsonDecode(payload ?? '') as Map<String, dynamic>;
    final n = AppNotification(
        id: p['id'] as String? ?? '', kind: '', title: '', link: p['link'] as String?, createdAt: DateTime.now());
    unawaited(c.read(unreadCountProvider.notifier).open(c.read(routerProvider), n));
  } catch (_) {} // not ours
}

/// Called once from main after runApp. Any Firebase failure leaves push off; it never stops the app.
Future<void> startPush(ProviderContainer container) async {
  if (!pushConfigured) return;
  final _FirebasePush push;
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: Env.firebaseApiKey,
        appId: Env.firebaseAppId,
        messagingSenderId: Env.firebaseMessagingSenderId,
        projectId: Env.firebaseProjectId,
      ),
    );
    _push = push = _FirebasePush(container.read(supabaseProvider));
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: _androidSettings,
      onDidReceiveNotificationResponse: (r) => _openPayload(container, r.payload),
    );
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(PushAlerts.channel);
    _alerts = PushAlerts(plugin.show);
    container
      ..invalidate(pushServiceProvider)
      ..invalidate(pushAlertsProvider);
    FirebaseMessaging.onBackgroundMessage(showPushInBackground);
    // opened by tapping one of ours while the app was closed
    if (await plugin.getNotificationAppLaunchDetails() case final d? when d.didNotificationLaunchApp) {
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => _openPayload(container, d.notificationResponse?.payload))
        ..scheduleFrame(); // after the router's first page, even if nothing else asks for a frame
    }
  } catch (_) {
    return; // push stays off; the in-app notifications still work
  }
  // no logging (test/core/release_safety_test.dart): a failed registration is retried on the next sign-in or launch
  void quietly(Future<void> f) => unawaited(f.catchError((Object _) {}));

  container.read(supabaseProvider).auth.onAuthStateChange.listen((s) {
    if (s.event == AuthChangeEvent.signedIn || s.event == AuthChangeEvent.initialSession) quietly(push.register());
    // the next account on this phone must not get the last one's pushes; send-push forgets the dead token
    if (s.event == AuthChangeEvent.signedOut) quietly(FirebaseMessaging.instance.deleteToken()); // ignore: deprecated_member_use
  });
  FirebaseMessaging.instance.onTokenRefresh.listen((t) => quietly(push.register(t))); // ignore: deprecated_member_use
  // data-only messages: FCM shows nothing itself, so each push is exactly one Android notification, ours
  FirebaseMessaging.onMessage.listen((m) => unawaited(onForegroundPush(container, m)));
}
