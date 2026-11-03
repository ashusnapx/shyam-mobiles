// Telemetry sends GA4 names with ids, counts and rupees only (docs/SECURITY.md §4.3): no key or value about a person.
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/features/account/data/address_form.dart';

import '../fakes/fake_telemetry.dart';

void main() {
  test('every event is a GA4 name with no personal keys', () async {
    final t = FakeTelemetry();
    const item = (productId: 'p1', variantId: 'v1', pricePaise: 1299900, qty: 2);
    await Future.wait([
      t.viewItemList('home_new', [item]), t.search(3), t.viewItem(item), t.addToWishlist(item), t.addToCart(item),
      t.removeFromCart(item), t.viewCart([item]), t.beginCheckout([item], coupon: 'WELCOME'), t.addShippingInfo([item]),
      t.addPaymentInfo([item], paymentType: 'cod'),
      t.purchase(orderNumber: 'SM100001', totalPaise: 2599800, items: [item], shippingPaise: 4900),
      t.viewPromotion('pr1'), t.selectPromotion('pr1'), t.login('phone'), t.signUp('google'), t.bookRepair('screen'),
      t.applyReferral(), t.sendFeedback('order'),
    ]);
    expect(t.events, hasLength(18));
    const pii = {'name', 'phone', 'email', 'address', 'gstin', 'pincode', 'search_term', 'user_id', 'uid'};
    for (final (name, params) in t.events) {
      expect(name, matches(RegExp(r'^[a-z_]{1,40}$')));
      expect(params.keys.where(pii.contains), isEmpty, reason: name);
    }
    expect(t.events.firstWhere((e) => e.$1 == 'purchase').$2, containsPair('value', 25998.0));
    expect(t.events.firstWhere((e) => e.$1 == 'search').$2, {'result_count': 3});
  });

  test('every state the address form offers has its GST state code', () {
    expect(indianStates.where((s) => gstStateCodes[s] == null), isEmpty);
    expect(gstStateCodes, hasLength(indianStates.length));
    expect(gstStateCodes['Madhya Pradesh'], '23');
  });
}
