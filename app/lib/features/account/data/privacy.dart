import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase.dart' show crashReportsKey;
import '../../../core/telemetry.dart';

/// Account → Privacy's two switches (docs/SECURITY.md §4.2): usage analytics, off until the customer opts in, and
/// crash reports, on by default. Kept on the phone, since collection must follow them before anyone signs in.
typedef PrivacyChoices = ({bool analytics, bool crashReports});

const _analyticsKey = 'analytics_consent';

final privacyProvider = AsyncNotifierProvider<PrivacyNotifier, PrivacyChoices>(PrivacyNotifier.new);

class PrivacyNotifier extends AsyncNotifier<PrivacyChoices> {
  @override
  Future<PrivacyChoices> build() async {
    final p = await SharedPreferences.getInstance();
    return (analytics: p.getBool(_analyticsKey) ?? false, crashReports: p.getBool(crashReportsKey) ?? true);
  }

  Future<void> setAnalytics(bool on) async {
    await ref.read(telemetryProvider).setAnalyticsConsent(on);
    await (await SharedPreferences.getInstance()).setBool(_analyticsKey, on);
    state = AsyncData((analytics: on, crashReports: (await future).crashReports));
  }

  Future<void> setCrashReports(bool on) async {
    await ref.read(telemetryProvider).setCrashReports(on);
    await (await SharedPreferences.getInstance()).setBool(crashReportsKey, on);
    state = AsyncData((analytics: (await future).analytics, crashReports: on));
  }
}
