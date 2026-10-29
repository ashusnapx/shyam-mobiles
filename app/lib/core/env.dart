/// Build-time config: `flutter run --dart-define-from-file=env/dev.json`. Everything here is public by design.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static void check() {
    assert(supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty,
        'Missing SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY. Run with --dart-define-from-file=env/dev.json');
  }
}
