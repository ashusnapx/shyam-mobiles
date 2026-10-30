import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/notifications/data/notifications.dart';
import 'env.dart';
import 'router.dart';
import 'supabase.dart';

// Phone notifications (FCM), off unless the build has the FIREBASE_* defines (docs/LAUNCH.md). Without them nothing
// here touches Firebase: no google-services.json, no Gradle plugin, and the app shows notifications only inside the
// app. With them: the phone's token goes to register_device after sign-in (once notifications are allowed), a push
// that lands while the app is open shows in the same in-app banner, and tapping one opens its screen.

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
    container.invalidate(pushServiceProvider);
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
  FirebaseMessaging.onMessage.listen((m) {
    container.read(notificationBannerProvider.notifier).show(_fromPush(m));
    unawaited(container.read(unreadCountProvider.notifier).refresh());
  });
  FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(container, m));
  if (await FirebaseMessaging.instance.getInitialMessage() case final m?) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _open(container, m)); // after the router's first page
  }
}

AppNotification _fromPush(RemoteMessage m) => AppNotification(
      id: m.data['id'] as String? ?? '',
      kind: m.data['kind'] as String? ?? '',
      title: m.notification?.title ?? '',
      body: m.notification?.body ?? '',
      link: m.data['link'] as String?,
      createdAt: m.sentTime ?? DateTime.now(),
    );

void _open(ProviderContainer container, RemoteMessage m) =>
    unawaited(container.read(unreadCountProvider.notifier).open(container.read(routerProvider), _fromPush(m)));
