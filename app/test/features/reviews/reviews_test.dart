// Verified-purchase reviews (docs/GROWTH.md §2a) at 360x800 dp with large text: the product page section, the tile
// badge (3+ reviews only), the review sheet and the staff hide switch. FakeReviewsRepository records every write.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_reviews_screen.dart';
import 'package:shyam_mobiles/features/catalog/widgets/product_tile.dart';
import 'package:shyam_mobiles/features/reviews/data/reviews.dart';
import 'package:shyam_mobiles/features/reviews/data/reviews_repository.dart';
import 'package:shyam_mobiles/features/reviews/widgets/review_widgets.dart';

import '../../fakes/fake_reviews_repository.dart';
import '../repairs/layout_harness.dart';

Review _r(String id, int rating, {String text = '', List<String> photos = const [], int day = 1, bool hidden = false}) =>
    Review(id: id, productId: 'p1', uid: id, name: 'Ravi S.', rating: rating, text: text, photos: photos,
        hidden: hidden, updatedAt: DateTime(2026, 11, day));

void main() {
  late FakeReviewsRepository repo;
  setUp(() => repo = FakeReviewsRepository());
  List<Override> fakes() => [reviewsRepositoryProvider.overrideWithValue(repo)];
  Widget page(Widget child) => Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [child]));

  test('top reviews: photos, then words, then newest; never by rating', () {
    final all = [_r('a', 5, day: 9), _r('b', 1, text: 'Bad', day: 2), _r('c', 2, photos: ['x'], day: 1), _r('d', 5, text: 'Ok', day: 5)];
    expect(topReviews(all).map((r) => r.id), ['c', 'd', 'b']);
    expect(ratingLabel(43), '4.3');
    expect(ratingLabel(50), '5.0');
  });

  testWidgets('the section shows the average, the breakdown and verified reviews', (tester) async {
    repo
      ..statsOf = {'p1': const ProductStats(ratingCount: 4, ratingSum: 15, stars: [0, 1, 0, 0, 3])}
      ..list = [_r('a', 5, text: 'Great phone'), _r('b', 2, text: 'Battery meh'), _r('c', 4), _r('d', 4), _r('h', 1, hidden: true)];
    await pumpScreen(tester, page(const ReviewsSection(productId: 'p1', productName: 'Galaxy S25')), overrides: fakes());
    await tester.pumpAndSettle();
    expect(find.text('Ratings & reviews'), findsOneWidget);
    expect(find.text('3.8'), findsOneWidget);
    expect(find.text('4 ratings'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '2 stars: 1'), findsOneWidget);
    expect(find.text('Verified purchase'), findsNWidgets(3));
    expect(find.text('See all 4 reviews'), findsOneWidget);
    expect(find.text('Write a review'), findsNothing); // not bought here
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing at all without reviews or a delivered order', (tester) async {
    await pumpScreen(tester, page(const ReviewsSection(productId: 'p1', productName: 'Galaxy S25')), overrides: fakes());
    await tester.pumpAndSettle();
    expect(find.text('Ratings & reviews'), findsNothing);
  });

  testWidgets('a buyer writes one: a star is required, then it saves', (tester) async {
    repo.canReview = {'p1'};
    await pumpScreen(tester, page(const ReviewsSection(productId: 'p1', productName: 'Galaxy S25')), overrides: fakes());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write a review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a star.'), findsOneWidget);
    expect(repo.calls, isEmpty);
    await tester.tap(find.byTooltip('4 stars'));
    await tester.enterText(find.byType(TextField), '  Good value  ');
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['save p1 4 "Good value" 0']);
    expect(find.text('Thanks! Your review helps other buyers.'), findsOneWidget);
  });

  testWidgets('tiles show ★ avg (count) only from 3 reviews', (tester) async {
    repo.tiles = {'p1': (avg10: 43, count: 12), 'p2': (avg10: 50, count: 2)};
    ProductCard card(String id) => ProductCard(id: id, slug: id, name: 'Phone $id', brandName: 'B', categorySlug: 'c',
        minPricePaise: 100000, mrpPaise: 100000, inStock: true);
    await pumpScreen(tester, page(Row(children: [Expanded(child: ProductTile(card('p1'))), Expanded(child: ProductTile(card('p2')))])),
        overrides: fakes());
    await tester.pumpAndSettle();
    expect(find.text('4.3 (12)'), findsOneWidget);
    expect(find.textContaining('(2)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff hide a review with the switch', (tester) async {
    repo.list = [_r('a', 1, text: 'Call me on 98…')];
    await pumpScreen(tester, const AdminReviewsScreen(), overrides: fakes());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(repo.calls, ['hide a true']);
  });
}
