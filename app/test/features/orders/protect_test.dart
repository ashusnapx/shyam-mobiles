// "Protect your new phone" (docs/GROWTH.md §2e) on a delivered phone order: in-stock accessories that fit, never
// added to the cart for the customer; nothing before delivery.
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/catalog/data/rails.dart';
import 'package:shyam_mobiles/features/orders/data/orders.dart';
import 'package:shyam_mobiles/features/orders/screens/order_detail_screen.dart';
import 'package:shyam_mobiles/features/reviews/data/reviews_repository.dart';

import '../../fakes/fake_reviews_repository.dart';
import '../repairs/layout_harness.dart';

Order _order(OrderStatus status) => Order(
      id: 'o1',
      number: 'SM100023',
      status: status,
      paymentMethod: PaymentMethod.cod,
      paymentStatus: PaymentStatus.paid,
      subtotalPaise: 1299900,
      deliveryFeePaise: 0,
      totalPaise: 1299900,
      address: const Address(name: 'Asha Verma', phone: '+919876543210', line1: 'Ward 4', city: 'Waidhan', state: 'MP', pincode: '486886'),
      createdAt: DateTime(2026, 10, 27),
      items: const [
        OrderItem(id: 'i1', productId: 'galaxy-a15', productName: 'Samsung Galaxy A15', variantName: '8 GB', unitPricePaise: 1299900, qty: 1),
      ],
      events: [OrderEvent(status: status, createdAt: DateTime(2026, 10, 29))],
    );

ProductCard _card(String id, {bool inStock = true}) => ProductCard(id: id, slug: id, name: 'Case $id', brandName: 'B',
    categorySlug: 'cases', minPricePaise: 29900, mrpPaise: 49900, inStock: inStock);

void main() {
  Future<void> pump(WidgetTester tester, OrderStatus status) => pumpScreen(tester, const OrderDetailScreen(orderId: 'o1'), overrides: [
        orderProvider('o1').overrideWith((ref) async => _order(status)),
        fitsProvider('galaxy-a15').overrideWith((ref) async => [_card('c1'), _card('c2', inStock: false)]),
        reviewsRepositoryProvider.overrideWithValue(FakeReviewsRepository()..canReview = {'galaxy-a15'}),
      ]);

  testWidgets('delivered: the fitting, in-stock accessories and a way to rate the phone', (tester) async {
    await pump(tester, OrderStatus.delivered);
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Protect your new phone'));
    expect(find.text('Case c1'), findsOneWidget);
    expect(find.text('Case c2'), findsNothing);
    expect(find.text('Rate this product'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('not before delivery', (tester) async {
    await pump(tester, OrderStatus.shipped);
    await tester.pumpAndSettle();
    expect(find.text('Protect your new phone'), findsNothing);
    expect(find.text('Rate this product'), findsNothing);
  });
}
