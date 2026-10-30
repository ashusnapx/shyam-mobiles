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

  /// Dev-only one-tap sign-in to local test accounts (see scripts/dev_setup.py). Compile-time false in
  /// release (kReleaseMode is a const), so the buttons are tree-shaken. The credentials are gated the same
  /// way: a release build made with env/dev.json by mistake still holds '' instead of the test passwords.
  /// test/core/release_safety_test.dart pins both.
  static const devLogin = bool.fromEnvironment('DEV_LOGIN') && !kReleaseMode;
  static const devCustomerEmail = devLogin ? String.fromEnvironment('DEV_CUSTOMER_EMAIL') : '';
  static const devCustomerPassword = devLogin ? String.fromEnvironment('DEV_CUSTOMER_PASSWORD') : '';
  static const devAdminEmail = devLogin ? String.fromEnvironment('DEV_ADMIN_EMAIL') : '';
  static const devAdminPassword = devLogin ? String.fromEnvironment('DEV_ADMIN_PASSWORD') : '';

  static void check() {
    assert(supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty,
        'Missing SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY. Run with --dart-define-from-file=env/dev.json');
  }
}
