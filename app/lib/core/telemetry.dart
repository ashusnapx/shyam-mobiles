import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Analytics and crash reports behind one boundary (docs/FIREBASE.md §6, docs/SECURITY.md §4.3–4.4). Typed parameters
/// only: ids, prices in paise, counts, route patterns; never names, phones, addresses or search terms. Owner: A.
abstract interface class Telemetry {
  /// The customer's analytics choice; off until they opt in.
  Future<void> setAnalyticsConsent(bool granted);

  /// GA4 e-commerce and app events (`view_item`, `add_to_cart`, `purchase`, `book_repair`…). [params] values are
  /// ids, enums and numbers; paise become rupees only at the Analytics boundary.
  Future<void> event(String name, [Map<String, Object> params = const {}]);

  /// An unexpected error behind friendlyError, as a non-fatal crash report (no user id, allowlisted keys only).
  Future<void> recordError(Object error, StackTrace? stack, {String? route});
}

/// Does nothing: the Supabase build and tests. Phase 1 adds the Firebase one.
class NoTelemetry implements Telemetry {
  const NoTelemetry();

  @override
  Future<void> setAnalyticsConsent(bool granted) async {}

  @override
  Future<void> event(String name, [Map<String, Object> params = const {}]) async {}

  @override
  Future<void> recordError(Object error, StackTrace? stack, {String? route}) async {}
}

final telemetryProvider = Provider<Telemetry>((ref) => const NoTelemetry());
