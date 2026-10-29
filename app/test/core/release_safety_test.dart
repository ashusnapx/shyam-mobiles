// Client-security invariants of the shipped app that a unit test can't reach at runtime (release mode, the
// Android manifest, the build script), pinned by reading the sources. `flutter test` runs in the app root.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/env.dart';
import 'package:shyam_mobiles/core/format.dart';

String _read(String path) => File(path).readAsStringSync();

Iterable<File> _files(String dir, bool Function(String path) keep) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => !f.path.contains('/build/') && !f.path.contains('/.gradle/') && keep(f.path));

void main() {
  test('dev sign-in is compiled out of release builds, credentials included', () {
    final env = _read('lib/core/env.dart');
    // kReleaseMode is a const, so in release devLogin is the constant false and everything behind it is tree-shaken.
    expect(env, contains("static const devLogin = bool.fromEnvironment('DEV_LOGIN') && !kReleaseMode;"));
    for (final key in ['DEV_CUSTOMER_EMAIL', 'DEV_CUSTOMER_PASSWORD', 'DEV_ADMIN_EMAIL', 'DEV_ADMIN_PASSWORD']) {
      expect(env, contains("devLogin ? String.fromEnvironment('$key') : ''"), reason: key);
    }
    // Tests run in debug mode without --dart-define, so all of it is off here too.
    expect((Env.devLogin, Env.devCustomerPassword, Env.devAdminPassword), (false, '', ''));

    // The buttons are only ever built behind the flag.
    final users = _files('lib', (p) => p.endsWith('.dart') && !p.endsWith('dev_login.dart'))
        .where((f) => f.readAsStringSync().contains('DevLoginButtons'));
    expect([for (final f in users) f.path], ['lib/features/auth/screens/sign_in_screen.dart']);
    expect(_read('lib/features/auth/screens/sign_in_screen.dart'), contains('if (Env.devLogin) const DevLoginButtons()'));
  });

  test('no secrets or service keys in Dart, Gradle, Android resources or assets', () {
    final secret = RegExp(
      r'sb_secret_|service_role|eyJ[A-Za-z0-9_-]{20,}\.|rzp_(live|test)_[A-Za-z0-9]{8,}|-----BEGIN [A-Z ]*PRIVATE KEY|'
      r'RAZORPAY_KEY_SECRET|WEBHOOK_SECRET|AIza[0-9A-Za-z_-]{30,}',
    );
    final sources = [
      ..._files('lib', (p) => p.endsWith('.dart')),
      ..._files('android', (p) => RegExp(r'\.(kts|gradle|properties|xml|kt|java|pro)$').hasMatch(p) &&
          !p.endsWith('local.properties') && !p.endsWith('key.properties')),
      ..._files('assets', (_) => true),
      File('pubspec.yaml'),
    ];
    expect(sources.length, greaterThan(50));
    final hits = [
      for (final f in sources)
        if (!f.path.endsWith('.png') && !f.path.endsWith('.webp') && !f.path.endsWith('.ttf'))
          if (secret.firstMatch(f.readAsStringSync()) case final m?) '${f.path}: ${m[0]}',
    ];
    expect(hits, isEmpty);
  });

  test('no logging of any kind in app code (tokens and personal data never reach logcat)', () {
    final log = RegExp(r'\b(print|debugPrint|debugPrintStack)\(|\blog\(|dart:developer');
    final hits = [
      for (final f in _files('lib', (p) => p.endsWith('.dart')))
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (log.hasMatch(line)) '${f.path}:${i + 1}',
    ];
    expect(hits, isEmpty);
  });

  test('session lives in secure storage only', () {
    final s = _read('lib/core/supabase.dart');
    expect(s, contains('authOptions: const FlutterAuthClientOptions(localStorage: _SecureSessionStorage())'));
    expect(RegExp(r'_secure\.(write|read)\(key: supabasePersistSessionKey').allMatches(s).length, 2);
  });

  group('links handed to other apps', () {
    test('only tel, https and upi', () {
      for (final ok in ['tel:+919876543210', 'https://wa.me/919876543210?text=Hi', 'https://www.google.com/maps/dir/?api=1',
          'upi://pay?pa=shop@upi&am=10']) {
        expect(isAllowedExternalUri(Uri.parse(ok)), isTrue, reason: ok);
      }
      for (final bad in ['http://wa.me/91', 'intent://scan/#Intent;scheme=zxing;end', 'javascript:alert(1)',
          'file:///data/data/com.shyammobiles.app/shared_prefs/x.xml', 'content://media/external', 'market://details?id=x',
          'whatsapp://send?phone=91', 'sms:+919876543210', 'mailto:a@b.c', 'https:///nohost', '/orders/1', '']) {
        expect(isAllowedExternalUri(Uri.parse(bad)), isFalse, reason: bad);
      }
    });

    test('every url_launcher call goes through the allowlist', () {
      final users = [
        for (final f in _files('lib', (p) => p.endsWith('.dart')))
          if (f.readAsStringSync().contains('launchUrl(')) f.path,
      ];
      expect(users, ['lib/core/widgets/widgets.dart']);
    });
  });

  group('release Android build', () {
    final main = _read('android/app/src/main/AndroidManifest.xml');

    test('no backups, no cleartext, only the launcher activity exported', () {
      expect(main, contains('android:allowBackup="false"'));
      expect(main, contains('android:fullBackupContent="false"'));
      expect(main, contains('android:usesCleartextTraffic="false"'));
      expect(RegExp('android:exported="true"').allMatches(main).length, 1);
      expect(main, isNot(contains('android:scheme="http"')));
      expect(main, isNot(contains('android:debuggable')));
      // cleartext (the local stack) is switched on only by the debug and profile overlays
      for (final type in ['debug', 'profile']) {
        expect(_read('android/app/src/$type/AndroidManifest.xml'),
            contains('android:usesCleartextTraffic="true" tools:replace="android:usesCleartextTraffic"'));
      }
    });

    test('runtime permissions are only the ones we ask for', () {
      final perms = [for (final m in RegExp(r'uses-permission android:name="([^"]+)"').allMatches(main)) m[1]];
      expect(perms, [
        'android.permission.INTERNET',
        'android.permission.ACCESS_COARSE_LOCATION', // address form, asked on tap
        'android.permission.ACCESS_FINE_LOCATION',
      ]);
    });

    test('R8 shrinks and obfuscates release, signed with the upload key when present', () {
      final gradle = _read('android/app/build.gradle.kts');
      expect(gradle, contains('isMinifyEnabled = true'));
      expect(gradle, contains('isShrinkResources = true'));
      expect(gradle, contains('signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")'));
      expect(_read('README.md'), contains('--obfuscate --split-debug-info='));
    });
  });
}
