import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend.dart';

/// One line of an e-commerce event: ids, a price in paise and a count. Never names or anything about the person.
typedef TelemetryItem = ({String productId, String? variantId, int pricePaise, int qty});

/// Analytics and crash reports behind one boundary (docs/FIREBASE.md §6, docs/SECURITY.md §4.3–4.4). The typed
/// methods are the only events: ids, enums, counts and paise (rupees only at the Analytics boundary), never names,
/// phones, addresses or search terms. Implementations supply [send]. Owner: A.
abstract class Telemetry {
  const Telemetry();

  /// The customer's analytics choice; off until they opt in.
  Future<void> setAnalyticsConsent(bool granted);

  /// Crash reports: on by default (no identifiers), with an off switch in Account → Privacy.
  Future<void> setCrashReports(bool enabled);

  /// An unexpected error, as a non-fatal crash report. [route] is the pattern without ids (`/orders/:id`).
  Future<void> recordError(Object error, StackTrace? stack, {String? route});

  /// The one sink: a GA4 event name, flat String/num params, and the items.
  @protected
  Future<void> send(String name, Map<String, Object> params, [List<TelemetryItem> items = const []]);

  static Map<String, Object> _money(int paise) => {'value': paise / 100, 'currency': 'INR'};
  static int _total(List<TelemetryItem> items) => items.fold(0, (s, i) => s + i.pricePaise * i.qty);

  // GA4 e-commerce events.
  Future<void> viewItemList(String listId, List<TelemetryItem> items) => send('view_item_list', {'item_list_id': listId}, items);
  Future<void> search(int resultCount) => send('search', {'result_count': resultCount}); // never the term
  Future<void> viewItem(TelemetryItem item) => send('view_item', _money(item.pricePaise), [item]);
  Future<void> addToWishlist(TelemetryItem item) => send('add_to_wishlist', _money(item.pricePaise), [item]);
  Future<void> addToCart(TelemetryItem item) => send('add_to_cart', _money(_total([item])), [item]);
  Future<void> removeFromCart(TelemetryItem item) => send('remove_from_cart', _money(_total([item])), [item]);
  Future<void> viewCart(List<TelemetryItem> items) => send('view_cart', _money(_total(items)), items);
  Future<void> beginCheckout(List<TelemetryItem> items, {String? coupon}) =>
      send('begin_checkout', {..._money(_total(items)), 'coupon': ?coupon}, items);
  Future<void> addShippingInfo(List<TelemetryItem> items) => send('add_shipping_info', _money(_total(items)), items);
  Future<void> addPaymentInfo(List<TelemetryItem> items, {required String paymentType}) =>
      send('add_payment_info', {..._money(_total(items)), 'payment_type': paymentType}, items);

  /// After a COD order is placed, or verifyPayment says paid. [orderNumber]: SM100001.
  Future<void> purchase({required String orderNumber, required int totalPaise, required List<TelemetryItem> items, int shippingPaise = 0, String? coupon}) =>
      send('purchase', {
        ..._money(totalPaise),
        'transaction_id': orderNumber,
        'shipping': shippingPaise / 100,
        'coupon': ?coupon,
      }, items);
  Future<void> viewPromotion(String promotionId) => send('view_promotion', {'promotion_id': promotionId});
  Future<void> selectPromotion(String promotionId) => send('select_promotion', {'promotion_id': promotionId});

  // Sign-in (method: google | phone) and the shop's own events.
  Future<void> login(String method) => send('login', {'method': method});
  Future<void> signUp(String method) => send('sign_up', {'method': method});
  Future<void> bookRepair(String issue) => send('book_repair', {'issue': issue});
  Future<void> applyReferral() => send('apply_referral', const {});
  Future<void> sendFeedback(String kind) => send('send_feedback', {'kind': kind});
}

/// Does nothing: the Supabase build and tests.
class NoTelemetry extends Telemetry {
  const NoTelemetry();

  @override
  Future<void> setAnalyticsConsent(bool granted) async {}

  @override
  Future<void> setCrashReports(bool enabled) async {}

  @override
  Future<void> recordError(Object error, StackTrace? stack, {String? route}) async {}

  @override
  Future<void> send(String name, Map<String, Object> params, [List<TelemetryItem> items = const []]) async {}
}

/// GA4 + Crashlytics for BACKEND=firebase. Analytics collection is off in the manifest until consent; Crashlytics
/// collection is off in the manifest too, and [setCrashReports] turns it on at start-up per the customer's switch.
class FirebaseTelemetry extends Telemetry {
  FirebaseTelemetry(this._analytics, this._crashlytics);

  final FirebaseAnalytics _analytics;
  final FirebaseCrashlytics _crashlytics;

  @override
  Future<void> setAnalyticsConsent(bool granted) async {
    await _analytics.setConsent(
      analyticsStorageConsentGranted: granted,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    await _analytics.setAnalyticsCollectionEnabled(granted);
    if (!granted) await _analytics.resetAnalyticsData();
  }

  @override
  Future<void> setCrashReports(bool enabled) => _crashlytics.setCrashlyticsCollectionEnabled(enabled);

  @override
  Future<void> recordError(Object error, StackTrace? stack, {String? route}) async {
    if (route != null) await _crashlytics.setCustomKey('route', route); // allowlist: build, backend, route
    await _crashlytics.recordError(error, stack, fatal: false);
  }

  @override
  Future<void> send(String name, Map<String, Object> params, [List<TelemetryItem> items = const []]) =>
      _analytics.logEvent(
        name: name,
        parameters: params,
        items: items.isEmpty
            ? null
            : [
                for (final i in items)
                  AnalyticsEventItem(itemId: i.productId, itemVariant: i.variantId, price: i.pricePaise / 100, quantity: i.qty),
              ],
      );
}

final telemetryProvider = Provider<Telemetry>((ref) => backend == Backend.firebase
    ? FirebaseTelemetry(FirebaseAnalytics.instance, FirebaseCrashlytics.instance)
    : const NoTelemetry());
