import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/admin.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_dashboard_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_order_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_orders_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_product_edit_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_products_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_repair_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_repairs_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_settings_screen.dart';
import 'package:shyam_mobiles/features/admin/widgets/feedback_card.dart';
import 'package:shyam_mobiles/features/repairs/data/repairs.dart';

import '../repairs/layout_harness.dart';

Order _order(OrderStatus status, {PaymentStatus pay = PaymentStatus.paid}) => Order(
      id: 'o1',
      number: 'SM100031',
      status: status,
      paymentMethod: PaymentMethod.razorpay,
      paymentStatus: pay,
      subtotalPaise: 7499900,
      deliveryFeePaise: 0,
      totalPaise: 7499900,
      razorpayOrderId: 'order_PZ1x2y3z4a5b6c',
      address: const Address(
        name: 'Asha Verma',
        phone: '+919876543210',
        line1: 'Flat 12B, Shanti Apartments',
        line2: 'Sector 21',
        landmark: 'Near the metro gate',
        city: 'Gurugram',
        state: 'Haryana',
        pincode: '122016',
      ),
      createdAt: DateTime(2026, 10, 29, 18, 42),
      courier: 'Delhivery',
      trackingNumber: '1490 2231 0098',
      items: const [
        OrderItem(id: 'i1', productName: 'Samsung Galaxy S25 Ultra 5G', variantName: '12 GB · 256 GB · Titanium Silverblue', unitPricePaise: 7499900, qty: 2, imeis: ['352099214488120', '352099214488138']),
      ],
      events: [OrderEvent(status: status, createdAt: DateTime(2026, 10, 29, 18, 42), note: 'Payment received')],
    );

const _brand = Brand(id: 'br1', slug: 'samsung', name: 'Samsung');
const _category = Category(id: 'c1', slug: 'phones', name: 'Phones', kind: CategoryKind.phone);

const _product = Product(
  id: 'p1',
  slug: 'samsung-galaxy-s25',
  name: 'Samsung Galaxy S25 Ultra 5G',
  brand: _brand,
  category: _category,
  description: 'Flagship.',
  specs: [Spec('Display', '6.9 in Dynamic AMOLED 2X, 120 Hz'), Spec('Battery', '5000 mAh')],
  images: [ProductPhoto(id: 'im1', path: 'p1/1.jpg')],
  variants: [
    Variant(
      id: 'v1',
      productId: 'p1',
      sku: 'SAM-S25U-12-256-SLV',
      name: '12 GB · 256 GB · Titanium Silverblue',
      pricePaise: 12999900,
      mrpPaise: 13499900,
      stock: 2,
      attributes: {'ram': '12 GB', 'storage': '256 GB', 'color': 'Silverblue', 'color_hex': '#9FB4C7'},
    ),
  ],
);

void main() {
  for (final dark in [false]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('dashboard ($theme)', (tester) async {
      await pumpScreen(tester, const AdminDashboardScreen(), dark: dark, overrides: [
        adminDashboardProvider.overrideWithValue(const AsyncData({
          'orders_today': 12,
          'revenue_today_paise': 48200000,
          'open_orders': 7,
          'open_repairs': 5,
          'low_stock': 3,
          'needs_refund': 1,
        })),
        needsActionProvider.overrideWithValue(AsyncData((
          orders: [_order(OrderStatus.confirmed), _order(OrderStatus.packed)],
          repairs: [testBooking(status: RepairStatus.requested)],
        ))),
      ]);
      expect(find.text('Today at the shop'), findsOneWidget);
      await tester.pumpAndSettle(); // the stat numbers count up
      expect(find.text('₹4.82L'), findsOneWidget);
      await scrollTo(tester, find.text('Confirm'));
      expect(find.text('Confirm'), findsOneWidget);
    });

    testWidgets('order detail, needs refund ($theme)', (tester) async {
      await pumpScreen(tester, const AdminOrderScreen(orderId: 'o1'), dark: dark, overrides: [
        adminOrderProvider.overrideWith((ref, id) => _order(OrderStatus.cancelled)),
        aboutFeedbackProvider.overrideWith((ref, key) => null),
      ]);
      expect(find.textContaining('Refund due'), findsOneWidget);
      expect(find.text('Mark refunded'), findsOneWidget, reason: 'staff can close a refund the webhook missed');
      await scrollTo(tester, find.text('Timeline'));
    });

    testWidgets('order detail, packed shows Ship + Cancel ($theme)', (tester) async {
      await pumpScreen(tester, const AdminOrderScreen(orderId: 'o1'), dark: dark, overrides: [
        adminOrderProvider.overrideWith((ref, id) => _order(OrderStatus.packed)),
        aboutFeedbackProvider.overrideWith((ref, key) => null),
      ]);
      expect(find.text('Ship'), findsOneWidget);
      await scrollTo(tester, find.text('Edit courier & tracking'));
      await scrollTo(tester, find.text('Cancel order'));
      expect(find.text('Cancel order'), findsOneWidget);
    });

    testWidgets('orders list ($theme)', (tester) async {
      await pumpScreen(tester, const AdminOrdersScreen(status: 'open'), dark: dark, overrides: [
        adminOrdersProvider.overrideWithBuild(
            (ref, _) => (items: [_order(OrderStatus.shipped), _order(OrderStatus.cancelled)], hasMore: true, moreFailed: true)),
      ]);
      expect(find.text('SM100031'), findsNWidgets(2));
      expect(find.text('Couldn’t load more. Try again'), findsOneWidget, reason: 'a failed next page offers a retry');
    });

    testWidgets('repairs list and detail ($theme)', (tester) async {
      await pumpScreen(tester, const AdminRepairsScreen(), dark: dark, overrides: [
        adminRepairsProvider.overrideWithBuild((ref, _) => (items: [testBooking()], hasMore: false, moreFailed: false)),
      ]);
      expect(find.text('RP100012'), findsOneWidget);
      expect(find.text('Awaiting approval'), findsWidgets, reason: 'the filter chip and the card tag');
      await pumpScreen(tester, const AdminRepairScreen(bookingId: 'b1'), dark: dark, overrides: [
        repairProvider.overrideWith((ref, id) => testBooking()),
        aboutFeedbackProvider.overrideWith((ref, key) => null),
      ]);
      expect(find.text('Start repair'), findsOneWidget);
      expect(find.text('Waiting for the customer to approve ₹2,499.'), findsOneWidget);
      await scrollTo(tester, find.text('Change quote'));
      await scrollTo(tester, find.text('Timeline'));
    });

    testWidgets('products list and editor ($theme)', (tester) async {
      await pumpScreen(tester, const AdminProductsScreen(), dark: dark, overrides: [
        adminProductPagesProvider.overrideWithBuild((ref, _) => (items: const [
          AdminProductRow(
            id: 'p1',
            name: 'Samsung Galaxy S25 Ultra 5G',
            brandName: 'Samsung',
            categoryName: 'Phones',
            isActive: false,
            isFeatured: true,
            coverPath: null,
            activeVariants: 1,
            stock: 2,
            lowStock: true,
          ),
        ], hasMore: false, moreFailed: false)),
      ]);
      expect(find.text('Hidden'), findsOneWidget);
      await pumpScreen(tester, const AdminProductEditScreen(productId: 'p1'), dark: dark, overrides: [
        adminBrandsProvider.overrideWithValue(const AsyncData([_brand])),
        adminCategoriesProvider.overrideWithValue(const AsyncData([_category])),
        adminProductProvider.overrideWith((ref, id) => _product),
      ]);
      expect(find.text('Save details'), findsOneWidget);
      await scrollTo(tester, find.text('SAM-S25U-12-256-SLV · 2 in stock'));
      expect(find.text('SAM-S25U-12-256-SLV · 2 in stock'), findsOneWidget);
    });

    testWidgets('new product hides photos/variants until saved ($theme)', (tester) async {
      await pumpScreen(tester, const AdminProductEditScreen(), dark: dark, overrides: [
        adminBrandsProvider.overrideWithValue(const AsyncData([_brand])),
        adminCategoriesProvider.overrideWithValue(const AsyncData([_category])),
      ]);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Galaxy S25+');
      await tester.pump();
      expect(find.text('galaxy-s25-plus'), findsOneWidget);
      expect(find.text('Create product'), findsOneWidget);
    });

    testWidgets('settings ($theme)', (tester) async {
      await pumpScreen(tester, const AdminSettingsScreen(), dark: dark);
      expect(find.text('Save settings'), findsOneWidget);
      await scrollTo(tester, find.text('Returns and warranty policy'));
      expect(find.text('Returns and warranty policy'), findsOneWidget);
    });

    testWidgets('settings: shop pin and photos ($theme)', (tester) async {
      const withPin = StoreSettings(
        deliveryFeePaise: 4900,
        freeDeliveryMinPaise: 99900,
        codEnabled: true,
        codMaxPaise: 2500000,
        storePhone: '+917987559272',
        storeAddress: 'Rajeev Complex, Waidhan',
        storeLat: 24.0670269,
        storeLng: 82.6307508,
        storePhotos: ['store/1.jpg', 'store/2.jpg', 'store/3.jpg'],
        repairNote: 'Final price is confirmed after inspection at the store.',
        returnsPolicy: 'Unopened items can be returned within 7 days of delivery.',
      );
      await pumpScreen(tester, const AdminSettingsScreen(), dark: dark, store: withPin);
      await scrollTo(tester, find.text('Open in Google Maps'));
      expect(find.text('Pin: 24.0670269, 82.6307508'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Shop location'), 'https://maps.app.goo.gl/AbCdEf123');
      await tester.tap(find.text('Save settings'));
      await tester.pump();
      expect(find.textContaining('No pin in India found'), findsOneWidget);
      expect(find.text('Open in Google Maps'), findsNothing);

      await scrollTo(tester, find.byTooltip('Remove photo 1'));
      expect(find.textContaining('3 of 8'), findsOneWidget);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, PhosphorIconsRegular.arrowLeft).first).onPressed, isNull);

      await tester.tap(find.byTooltip('Remove photo 1'));
      await tester.pumpAndSettle();
      expect(find.text('Remove this photo?'), findsOneWidget);
      await tester.tap(find.text('Keep photo'));
      await tester.pumpAndSettle();
      expect(find.text('Remove this photo?'), findsNothing);
    });
  }
}
