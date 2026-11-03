import 'package:shyam_mobiles/core/telemetry.dart';

/// Records events so tests can check what was sent, and that nothing personal was.
class FakeTelemetry extends Telemetry {
  bool consent = false;
  bool crashReports = true;
  final events = <(String, Map<String, Object>)>[];
  final errors = <Object>[];

  @override
  Future<void> setAnalyticsConsent(bool granted) async => consent = granted;

  @override
  Future<void> setCrashReports(bool enabled) async => crashReports = enabled;

  @override
  Future<void> send(String name, Map<String, Object> params, [List<TelemetryItem> items = const []]) async =>
      events.add((name, params));

  @override
  Future<void> recordError(Object error, StackTrace? stack, {String? route}) async => errors.add(error);
}
