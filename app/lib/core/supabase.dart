import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'models/models.dart';

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
  );
}

/// Keeps an autoDispose provider's data for [d] after its last listener leaves, so going back and forth
/// between screens shows the cached content instead of a fresh skeleton.
void cacheFor(Ref ref, Duration d) {
  final link = ref.keepAlive();
  final timer = Timer(d, link.close);
  ref.onDispose(timer.cancel);
}

String publicImageUrl(String path) => '${Env.supabaseUrl}/storage/v1/object/public/product-images/$path';

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

final storeSettingsProvider = FutureProvider<StoreSettings>((ref) async {
  final row = await ref.watch(supabaseProvider).from('store_settings').select().single();
  return StoreSettings.fromJson(row);
});
