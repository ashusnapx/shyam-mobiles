import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shyam_mobiles/core/format.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/router.dart';
import 'package:shyam_mobiles/core/theme/theme.dart';
import 'package:shyam_mobiles/core/widgets/widgets.dart';

void main() {
  group('money', () {
    test('formats paise as Indian rupees', () {
      expect(formatInr(12999900), '₹1,29,999');
      expect(formatInr(109900), '₹1,099');
      expect(formatInr(4950), '₹49.50');
      expect(formatInr(0), '₹0');
    });

    test('discount rounds down and never goes negative', () {
      expect(discountPercent(7499900, 8099900), 7);
      expect(discountPercent(100, 100), 0);
      expect(discountPercent(200, 100), 0);
    });

    test('delivery fee and COD follow store settings', () {
      const s = StoreSettings(
        deliveryFeePaise: 4900,
        freeDeliveryMinPaise: 99900,
        codEnabled: true,
        codMaxPaise: 2500000,
        storePhone: '+919999999999',
        storeAddress: '',
        storeHours: '',
        repairNote: '',
        returnsPolicy: '',
      );
      expect(s.deliveryFeeFor(99899), 4900);
      expect(s.deliveryFeeFor(99900), 0);
      expect(s.codAllowedFor(2500000), isTrue);
      expect(s.codAllowedFor(2500001), isFalse);
    });
  });

  group('store location', () {
    final json = {
      'delivery_fee_paise': 4900, 'free_delivery_min_paise': 99900, 'cod_enabled': true, 'cod_max_paise': 2500000,
      'store_phone': '+917987559272', 'store_address': 'Rajeev Complex, Waidhan',
      'store_lat': 24.0670269, 'store_lng': 82.6307508, 'store_maps_url': 'https://maps.google.com/?cid=3396347197360889573',
      'store_photos': ['store/1.jpg', 'store/2.webp'],
      'store_hours': '10 am – 9 pm', 'repair_note': 'x', 'returns_policy': 'y',
      'referral_enabled': true, 'referral_friend_paise': 15000, 'referral_reward_paise': 25000,
      'referral_min_order_paise': 99900, 'referral_monthly_cap': 5,
    };

    test('JSON round trip keeps the pin, link and photo order', () {
      final s = StoreSettings.fromJson(json);
      expect(s.storePhotos, ['store/1.jpg', 'store/2.webp']);
      expect(s.toJson(), json);
      // a copy saved on the phone before referrals existed still loads, with them off
      final old = StoreSettings.fromJson({...json}..removeWhere((k, _) => k.startsWith('referral_')));
      expect((old.referralEnabled, old.referralFriendPaise, old.referralMonthlyCap), (false, 20000, 10));
    });

    test('directions and the Maps link use the pin, else the address', () {
      final s = StoreSettings.fromJson(json);
      expect(s.mapsDestination, '24.0670269,82.6307508');
      expect(directionsUri(s.mapsDestination).queryParameters['destination'], '24.0670269,82.6307508');
      expect(s.mapsListingUri.toString(), 'https://maps.google.com/?cid=3396347197360889573');

      final noLink = StoreSettings.fromJson({...json, 'store_maps_url': null});
      expect(noLink.mapsListingUri!.queryParameters['query'], '24.0670269,82.6307508');

      final noPin = StoreSettings.fromJson({...json, 'store_lat': null, 'store_lng': null, 'store_maps_url': null, 'store_photos': null});
      expect(noPin.mapsDestination, 'Rajeev Complex, Waidhan');
      expect(noPin.mapsListingUri, isNull);
      expect(noPin.storePhotos, isEmpty);
    });
  });

  test('normalizes Indian mobile numbers to E.164', () {
    for (final input in ['98765 43210', '+91 98765 43210', '098765-43210', '919876543210']) {
      expect(normalizeIndianPhone(input), '+919876543210', reason: input);
    }
    for (final bad in ['12345', '58765 43210', '+1 415 555 0100', '']) {
      expect(normalizeIndianPhone(bad), isNull, reason: bad);
    }
    expect(displayPhone('+919876543210'), '+91 98765 43210');
  });

  test('sign-in return path stays inside the app', () {
    expect(safeReturnPath('/product/samsung-galaxy-s25'), '/product/samsung-galaxy-s25');
    expect(safeReturnPath('//evil.example'), isNull);
    expect(safeReturnPath('https://evil.example'), isNull);
    expect(safeReturnPath('/sign-in/verify'), isNull);
    expect(safeReturnPath(null), isNull);
  });

  test('order JSON maps statuses and the address snapshot', () {
    final o = Order.fromJson({
      'id': 'o1', 'number': 'SM100001', 'user_id': 'u1', 'status': 'pending_payment', 'payment_method': 'razorpay',
      'payment_status': 'pending', 'subtotal_paise': 100, 'delivery_fee_paise': 0, 'total_paise': 100,
      'address': {'name': 'A', 'phone': '+919876543210', 'line1': 'x', 'city': 'Gaya', 'state': 'Bihar', 'pincode': '823001'},
      'reserved_until': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      'created_at': '2026-10-29T10:00:00Z',
    });
    expect(o.status, OrderStatus.pendingPayment);
    expect(o.canRetryPayment, isTrue);
    expect(o.canCancel, isTrue);
    expect(o.address.oneLine, 'x, Gaya, Bihar 823001');
  });

  testWidgets('shared widgets render with Phosphor icons', (tester) async {
    for (final theme in [lightTheme]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(children: [
            const BrandMark(),
            const Icon(PhosphorIconsRegular.house),
            const Icon(PhosphorIconsFill.shoppingBag),
            const PriceTag(pricePaise: 7499900, mrpPaise: 8099900),
            const SizedBox(width: 120, child: ProductImage(null)),
            QtyStepper(value: 1, onChanged: (_) {}),
          ]),
        ),
      ));
      expect(find.text('₹74,999'), findsOneWidget);
      expect(find.text('7% off'), findsOneWidget);
      expect(find.bySemanticsLabel('Shyam Mobiles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
