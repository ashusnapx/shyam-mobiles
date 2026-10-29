import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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

final _product = Product(
  id: 'p1',
  slug: 'samsung-galaxy-s25',
  name: 'Samsung Galaxy S25 Ultra 5G',
  brand: _brand,
  category: _category,
  description: 'Flagship.',
  specs: const [Spec('Display', '6.9 in Dynamic AMOLED 2X, 120 Hz'), Spec('Battery', '5000 mAh')],
  images: const [ProductPhoto(id: 'im1', path: 'p1/1.jpg')],
  variants: const [
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
      expect(find.text('₹4.82L'), findsOneWidget);
      await scrollTo(tester, find.text('Confirm'));
      expect(find.text('Confirm'), findsOneWidget);
    });

    testWidgets('order detail, needs refund ($theme)', (tester) async {
      await pumpScreen(tester, const AdminOrderScreen(orderId: 'o1'), dark: dark, overrides: [
        adminOrderProvider.overrideWith((ref, id) => _order(OrderStatus.cancelled)),
      ]);
      expect(find.textContaining('Refund due'), findsOneWidget);
      await scrollTo(tester, find.text('Timeline'));
    });

    testWidgets('order detail, packed shows Ship + Cancel ($theme)', (tester) async {
      await pumpScreen(tester, const AdminOrderScreen(orderId: 'o1'), dark: dark, overrides: [
        adminOrderProvider.overrideWith((ref, id) => _order(OrderStatus.packed)),
      ]);
      expect(find.text('Ship'), findsOneWidget);
      await scrollTo(tester, find.text('Cancel order'));
      expect(find.text('Cancel order'), findsOneWidget);
    });

    testWidgets('orders list ($theme)', (tester) async {
      await pumpScreen(tester, const AdminOrdersScreen(status: 'open'), dark: dark, overrides: [
        adminOrdersProvider.overrideWith((ref, f) => [_order(OrderStatus.shipped), _order(OrderStatus.cancelled)]),
      ]);
      expect(find.text('SM100031'), findsNWidgets(2));
    });

    testWidgets('repairs list and detail ($theme)', (tester) async {
      await pumpScreen(tester, const AdminRepairsScreen(), dark: dark, overrides: [
        adminRepairsProvider.overrideWith((ref, f) => [testBooking()]),
      ]);
      expect(find.text('RP100012'), findsOneWidget);
      await pumpScreen(tester, const AdminRepairScreen(bookingId: 'b1'), dark: dark, overrides: [
        repairProvider.overrideWith((ref, id) => testBooking()),
      ]);
      expect(find.text('Mark in repair'), findsOneWidget);
      await scrollTo(tester, find.text('Save quote and note'));
      expect(find.text('Save quote and note'), findsOneWidget);
    });

    testWidgets('products list and editor ($theme)', (tester) async {
      await pumpScreen(tester, const AdminProductsScreen(), dark: dark, overrides: [
        adminProductsProvider.overrideWithValue(const AsyncData([
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
        ])),
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
  }
}
