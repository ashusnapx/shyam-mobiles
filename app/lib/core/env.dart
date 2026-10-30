import 'package:flutter/foundation.dart';

/// Build-time config: `flutter run --dart-define-from-file=env/dev.json`. Everything here is public by design.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  /// Base URL of the published site/ pages (privacy, terms, refunds...), e.g. https://shyammobiles.in
  static const policiesUrl = String.fromEnvironment('POLICIES_URL');
  /// Host of shared links (`https://<host>/open?…`, served by site/open.html), e.g. shyammobiles.in. The Android
  /// build claims it as an App Link (build.gradle.kts reads the same key). Empty: shares carry no link.
  static const linkHost = String.fromEnvironment('LINK_HOST');
  /// The Firebase Android app (console > Project settings > Your apps), for phone notifications (lib/core/push.dart).
  /// Any of them empty: the app never touches Firebase and shows notifications only inside the app.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseMessagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  /// Dev-only one-tap sign-in to local test accounts (see scripts/dev_setup.py). Compile-time false in
  /// release (kReleaseMode is a const), so the buttons are tree-shaken. The credentials are gated the same
  /// way: a release build made with env/dev.json by mistake still holds '' instead of the test passwords.
  /// The one exception is a demo build that also sets DEMO_BUILD=true (a release APK to hand a tester, pointing
  /// at a test backend); Play builds never set it. test/core/release_safety_test.dart pins all of this.
  static const demoBuild = bool.fromEnvironment('DEMO_BUILD');
  static const devLogin = bool.fromEnvironment('DEV_LOGIN') && (!kReleaseMode || demoBuild);
  static const devCustomerEmail = devLogin ? String.fromEnvironment('DEV_CUSTOMER_EMAIL') : '';
  static const devCustomerPassword = devLogin ? String.fromEnvironment('DEV_CUSTOMER_PASSWORD') : '';
  static const devAdminEmail = devLogin ? String.fromEnvironment('DEV_ADMIN_EMAIL') : '';
  static const devAdminPassword = devLogin ? String.fromEnvironment('DEV_ADMIN_PASSWORD') : '';

  static void check() {
    assert(supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty,
        'Missing SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY. Run with --dart-define-from-file=env/dev.json');
  }
}
