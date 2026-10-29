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

  /// Dev-only one-tap sign-in to local test accounts (see scripts/dev_setup.py). Release builds never
  /// get these defines, and kReleaseMode keeps the buttons out even if someone passes them.
  static const devLogin = bool.fromEnvironment('DEV_LOGIN') && !kReleaseMode;
  static const devCustomerEmail = String.fromEnvironment('DEV_CUSTOMER_EMAIL');
  static const devCustomerPassword = String.fromEnvironment('DEV_CUSTOMER_PASSWORD');
  static const devAdminEmail = String.fromEnvironment('DEV_ADMIN_EMAIL');
  static const devAdminPassword = String.fromEnvironment('DEV_ADMIN_PASSWORD');

  static void check() {
    assert(supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty,
        'Missing SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY. Run with --dart-define-from-file=env/dev.json');
  }
}
