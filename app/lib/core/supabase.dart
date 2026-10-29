import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'models/models.dart';
import 'network.dart';

const _secure = FlutterSecureStorage();

/// Keeps the session in Keychain/Keystore instead of SharedPreferences.
class _SecureSessionStorage extends LocalStorage {
  const _SecureSessionStorage();

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() => _secure.containsKey(key: supabasePersistSessionKey);
  @override
  Future<String?> accessToken() => _secure.read(key: supabasePersistSessionKey);
  @override
  Future<void> persistSession(String persistSessionString) =>
      _secure.write(key: supabasePersistSessionKey, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => _secure.delete(key: supabasePersistSessionKey);
}

Future<void> initSupabase() async {
  Env.check();
  // iOS Keychain survives uninstall; don't let a reinstall resurrect the old session.
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('installed') != true) {
    await _secure.deleteAll();
    await prefs.setBool('installed', true);
  }
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(localStorage: _SecureSessionStorage()),
    httpClient: TimeoutClient(http.Client()),
  );
}

/// Bounds every Supabase request (REST, RPC, auth, Edge Functions, storage) so a stalled network ends in a
/// TimeoutException, which screens show as friendlyError with a retry, instead of a spinner forever.
/// The timeout covers sending the request and getting the response headers, so it also bounds photo uploads.
/// shortcut: postgrest still retries a failed table read 3 times (1+2+4 s back-off; supabase 2.16 `from()`
/// ignores PostgrestClientOptions), so a dead network errors after ~70 s at worst; pass the options once it doesn't.
class TimeoutClient extends http.BaseClient {
  TimeoutClient(this._inner, {this.timeout = const Duration(seconds: 15)});

  final http.Client _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request).timeout(timeout);

  @override
  void close() => _inner.close();
}

/// The app's ProviderScope retry policy: none. Riverpod 3 otherwise retries a failed provider up to 10 times
/// (≈40 s of back-off) and keeps it *loading* meanwhile, on top of postgrest's own 3 retries per read, so an
/// offline screen showed its skeleton for minutes before the error and "Try again". Screens retry by hand.
Duration? noAutoRetry(int retryCount, Object error) => null;

/// Keeps an autoDispose provider's data for [d] after its last listener leaves, so going back and forth
/// between screens shows the cached content instead of a fresh skeleton.
void cacheFor(Ref ref, Duration d) {
  final link = ref.keepAlive();
  final timer = Timer(d, link.close);
  ref.onDispose(timer.cancel);
}

String publicImageUrl(String path) => '${Env.supabaseUrl}/storage/v1/object/public/product-images/$path';

/// "p1/1730000000000.webp" → "p1/1730000000000@thumb.webp", the 480 px copy uploaded beside each photo. Null for
/// JPEG/PNG keys (older uploads never had one). Older WebP uploads have none either: ProductImage falls back on error.
String? thumbPathFor(String path) =>
    path.endsWith('.webp') ? '${path.substring(0, path.length - '.webp'.length)}@thumb.webp' : null;

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(supabaseProvider).auth.onAuthStateChange);

/// For UI that shows email/phone. Rebuilds on every auth event, including token refreshes.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});

/// For data that belongs to the user. Only changes on sign-in/sign-out, so data isn't refetched on token refresh.
final currentUserIdProvider = Provider<String?>((ref) => ref.watch(currentUserProvider)?.id);

final isAdminProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return false;
  return await ref.watch(supabaseProvider).rpc<bool>('is_admin');
});

/// Saved on the phone: a cold start (or no signal) shows the last copy at once and refreshes in the background.
final storeSettingsProvider = FutureProvider<StoreSettings>((ref) {
  final db = ref.watch(supabaseProvider);
  return savedOrFetch(
    ref,
    'store_settings',
    () async => await db.from('store_settings').select().single(),
    (json) => StoreSettings.fromJson(json! as Map<String, dynamic>),
  );
});
