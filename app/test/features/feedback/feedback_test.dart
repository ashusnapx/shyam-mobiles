// Feedback at 360x800 dp with 1.4x text: the sheet (Account → Send feedback), the order rating card, the listing
// report link, the staff inbox and detail, and the dashboard tile. FakeFeedbackApi records every call: no network.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/paging.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/account/data/profile.dart';
import 'package:shyam_mobiles/features/account/screens/account_screen.dart';
import 'package:shyam_mobiles/features/admin/data/admin.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_dashboard_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_feedback_screen.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/screens/product_screen.dart';
import 'package:shyam_mobiles/features/feedback/data/feedback.dart';
import 'package:shyam_mobiles/features/orders/data/orders.dart';
import 'package:shyam_mobiles/features/orders/screens/order_detail_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repairs/layout_harness.dart';

class _Api implements FeedbackApi {
  final sent = <Map<String, Object?>>[];
  final updates = <String>[];
  Exception? sendError;
  FeedbackEntry? mineRow;
  List<FeedbackEntry> rows = const [];

  @override
  Future<String> send({
    required FeedbackKind kind,
    int? rating,
    String message = '',
    String? orderId,
    String? repairId,
    String? productId,
    String? screen,
  }) async {
    if (sendError case final e?) throw e;
    sent.add({'kind': kind, 'rating': rating, 'message': message, 'order': orderId, 'product': productId, 'screen': screen});
    return 'f-new';
  }

  @override
  Future<FeedbackEntry?> mine(String userId, FeedbackKind kind, String id) async => mineRow;

  @override
  Future<List<FeedbackEntry>> inbox(FeedbackFilter f, int from, int size) async =>
      rows
          .where((r) => (f.status == null || r.status == f.status) && (f.productId == null || r.productId == f.productId))
          .skip(from)
          .take(size)
          .toList();

  @override
  Future<int> listingReports(String productId) async =>
      rows.where((r) => r.kind == FeedbackKind.product && r.productId == productId).length;

  @override
  Future<FeedbackEntry> entry(String id) async => rows.firstWhere((r) => r.id == id);

  @override
  Future<void> update(String id, {FeedbackStatus? status, String? adminNote}) async =>
      updates.add('$id ${status?.value ?? '-'} ${adminNote ?? '-'}');

  @override
  Future<int> newCount() async => rows.where((r) => r.status == FeedbackStatus.unread).length;
}

const _user = User(id: 'user-1', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-10-29T00:00:00Z', email: 'asha@example.com');

Order _delivered() => Order(
      id: 'o1',
      number: 'SM100023',
      status: OrderStatus.delivered,
      paymentMethod: PaymentMethod.cod,
      paymentStatus: PaymentStatus.paid,
      subtotalPaise: 1299900,
      deliveryFeePaise: 0,
      totalPaise: 1299900,
      address: const Address(name: 'Asha Verma', phone: '+919876543210', line1: 'Ward 4', city: 'Waidhan', state: 'MP', pincode: '486886'),
      createdAt: DateTime(2026, 10, 27),
      items: const [OrderItem(id: 'i1', productName: 'Samsung Galaxy A15', variantName: '8 GB · 128 GB', unitPricePaise: 1299900, qty: 1)],
      events: [OrderEvent(status: OrderStatus.delivered, createdAt: DateTime(2026, 10, 29))],
    );

FeedbackEntry _entry(String id, {FeedbackStatus status = FeedbackStatus.unread, int? rating = 2, String message = 'The case came scratched.\nPlease swap it.'}) =>
    FeedbackEntry(
      id: id,
      kind: FeedbackKind.order,
      status: status,
      rating: rating,
      message: message,
      orderId: 'o1',
      orderNumber: 'SM100023',
      customerName: 'Asha Verma',
      customerPhone: '+919876543210',
      screen: '/orders/o1',
      createdAt: DateTime(2026, 10, 29, 18, 5),
    );

void main() {
  test('the screen sent along fits the DB rule: allowed characters only, at most 200', () {
    expect(feedbackScreen(Uri.parse('/product/galaxy-s25?add=v1')), '/product/galaxy-s25?add=v1');
    expect(feedbackScreen(Uri.parse('/search?q=redmi note')), '/search?q=redmi%20note');
    expect(feedbackScreen(Uri.parse('/x/${'a' * 300}'))!.length, 200);
    expect(feedbackScreen(Uri.parse('no-slash')), isNull);
    expect(feedbackScreen(null), isNull);
    expect(RegExp(r'^/[A-Za-z0-9/_?=&.%-]*$').hasMatch(feedbackScreen(Uri.parse('/a#b?c=ü'))!), isTrue);
  });

  test('a row reads its order, repair or product and who sent it', () {
    final e = FeedbackEntry.fromJson({
      'id': 'f1', 'kind': 'repair', 'rating': 5, 'message': 'Fast', 'repair_id': 'r1', 'status': 'seen',
      'created_at': '2026-10-29T10:00:00Z', 'order': null, 'product': null,
      'repair': {'number': 'RP100012', 'contact_phone': '+919876543210'},
    });
    expect((e.kind, e.status, e.repairNumber, e.customerPhone), (FeedbackKind.repair, FeedbackStatus.seen, 'RP100012', '+919876543210'));
    expect(feedbackFrom(e), 'RP100012 · +91 98765 43210');
  });

  testWidgets('send feedback from Account: a star or words needed, kind choice, a plain limit error, then thanks', (tester) async {
    final api = _Api();
    await pumpScreen(tester, const AccountScreen(), overrides: [
      currentUserProvider.overrideWithValue(_user),
      profileProvider.overrideWithValue(const AsyncData(null)),
      feedbackApiProvider.overrideWithValue(api),
    ]);
    await scrollTo(tester, find.text('Send feedback'));
    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pump();
    expect(find.text('Pick a star or write a few words.'), findsOneWidget);

    await tester.tap(find.text('An idea or a comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Something isn’t working').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  The search keeps spinning on Jio  ');
    api.sendError = const PostgrestException(message: 'FEEDBACK_LIMIT', code: 'P0001');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('all the feedback we can take from you today'), findsOneWidget);

    api.sendError = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(api.sent.single, {
      'kind': FeedbackKind.bug,
      'rating': null,
      'message': 'The search keeps spinning on Jio',
      'order': null,
      'product': null,
      'screen': '/',
    });
    expect(find.text('Thank you. The shop reads every message.'), findsOneWidget);
  });

  testWidgets('order detail: delivered orders ask for stars; a rating given shows and can be changed', (tester) async {
    final api = _Api();
    await pumpScreen(tester, const OrderDetailScreen(orderId: 'o1'), overrides: [
      orderProvider('o1').overrideWith((ref) async => _delivered()),
      feedbackApiProvider.overrideWithValue(api),
    ]);
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('How was your order?'));
    expect(find.textContaining('Tap a star'), findsOneWidget);
    await tester.tap(find.byTooltip('4 stars'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Quick delivery');
    api.mineRow = _entry('f1', rating: 4, message: 'Quick delivery');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect((api.sent.single['kind'], api.sent.single['rating'], api.sent.single['order']), (FeedbackKind.order, 4, 'o1'));
    expect(find.text('Thanks for rating. Tap to change it.'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets('product page: “Report a problem with this listing” sends a product report', (tester) async {
    final api = _Api();
    const product = Product(
      id: 'p1',
      slug: 'galaxy-a15',
      name: 'Samsung Galaxy A15',
      brand: Brand(id: 'b', slug: 'samsung', name: 'Samsung'),
      category: Category(id: 'c', slug: 'smartphones', name: 'Phones', kind: CategoryKind.phone),
      variants: [Variant(id: 'v1', productId: 'p1', sku: 'A15', name: '8 GB', pricePaise: 1299900, mrpPaise: 1399900, stock: 4)],
    );
    await pumpScreen(tester, const ProductScreen(slug: 'galaxy-a15'), overrides: [
      productProvider.overrideWith((ref, slug) async => product),
      feedbackApiProvider.overrideWithValue(api),
    ]);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000)); // the foot of the page
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report a problem with this listing'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Price is old');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect((api.sent.single['kind'], api.sent.single['product']), (FeedbackKind.product, 'p1'));
  });

  testWidgets('staff inbox: stars, kind, first line, who and when; opening marks it seen; note and resolve', (tester) async {
    final api = _Api()..rows = [_entry('f1'), _entry('f2', status: FeedbackStatus.resolved, rating: null, message: 'Thanks!')];
    await pumpScreen(tester, const AdminFeedbackScreen(), routes: ['/admin/feedback/:id'], overrides: [
      feedbackApiProvider.overrideWithValue(api),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('The case came scratched.'), findsOneWidget, reason: 'first line only');
    expect(find.textContaining('Asha Verma · +91 98765 43210'), findsOneWidget);
    expect(find.text('Thanks!'), findsNothing, reason: 'New is the default filter');
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Thanks!'), findsOneWidget);

    await pumpScreen(tester, const AdminFeedbackDetailScreen(feedbackId: 'f1'), routes: ['/admin/orders/:id'], overrides: [
      feedbackApiProvider.overrideWithValue(api),
    ]);
    await tester.pumpAndSettle();
    expect(api.updates, ['f1 seen -'], reason: 'opened, so seen');
    expect(find.text('Order SM100023'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Called her, sending a new case');
    await scrollTo(tester, find.text('Mark resolved'));
    await tester.tap(find.text('Mark resolved'));
    await tester.pumpAndSettle();
    expect(api.updates.last, 'f1 resolved Called her, sending a new case');
    expect(find.text('Marked resolved'), findsOneWidget);
  });

  testWidgets('dashboard: a tile counts the new feedback', (tester) async {
    final api = _Api()..rows = [_entry('f1'), _entry('f2'), _entry('f3', status: FeedbackStatus.seen)];
    await pumpScreen(tester, const AdminDashboardScreen(), overrides: [
      feedbackApiProvider.overrideWithValue(api),
      adminDashboardProvider.overrideWithValue(const AsyncData({'orders_today': 1})),
      needsActionProvider.overrideWithValue(const AsyncData((orders: <Order>[], repairs: <RepairBooking>[]))),
    ]);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('New feedback, 2'), findsOneWidget);
  });

  testWidgets('a listing’s reports: the editor row counts them and opens the inbox filtered to that product', (tester) async {
    final report = FeedbackEntry(
      id: 'f9',
      kind: FeedbackKind.product,
      status: FeedbackStatus.seen,
      message: 'Wrong price on the 256 GB',
      productId: 'p1',
      productName: 'Samsung Galaxy A15',
      createdAt: DateTime(2026, 10, 29),
    );
    final api = _Api()..rows = [_entry('f1'), report];
    await pumpScreen(tester, const Scaffold(body: ListingReportsRow(productId: 'p1')), routes: ['/admin/feedback'], overrides: [
      feedbackApiProvider.overrideWithValue(api),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Reports about this listing'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.text('Reports about this listing'));
    await tester.pumpAndSettle();
    expect(find.text('Page /admin/feedback?product=p1'), findsOneWidget);

    await pumpScreen(tester, const AdminFeedbackScreen(productId: 'p1'), overrides: [feedbackApiProvider.overrideWithValue(api)]);
    await tester.pumpAndSettle();
    expect(find.text('Wrong price on the 256 GB'), findsOneWidget, reason: 'seen ones too: all statuses');
    expect(find.text('The case came scratched.'), findsNothing);
    await tester.tap(find.byTooltip('Show feedback about everything'));
    await tester.pumpAndSettle();
    expect(find.text('The case came scratched.'), findsOneWidget);
  });

  test('the inbox pages like every list', () async {
    final api = _Api()..rows = [for (var i = 0; i < 45; i++) _entry('f$i')];
    final c = ProviderContainer(retry: noAutoRetry, overrides: [feedbackApiProvider.overrideWithValue(api)]);
    addTearDown(c.dispose);
    const all = (status: null, kind: null, productId: null);
    c.listen(adminFeedbackProvider(all), (_, _) {});
    final first = await c.read(adminFeedbackProvider(all).future);
    expect((first.items.length, first.hasMore), (30, true));
    await c.read(adminFeedbackProvider(all).notifier).loadMore();
    final Paged<FeedbackEntry> both = c.read(adminFeedbackProvider(all)).value!;
    expect((both.items.length, both.hasMore), (45, false));
  });
}
