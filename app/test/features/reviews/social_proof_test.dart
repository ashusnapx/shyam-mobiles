// Honest social proof (docs/GROWTH.md §2b): "N bought this week" from counted sales (3 and up only) and
// "Frequently bought together" from real co-purchases (pairs seen twice and up).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/features/reviews/data/reviews.dart';
import 'package:shyam_mobiles/features/reviews/data/reviews_repository.dart';
import 'package:shyam_mobiles/features/reviews/widgets/review_widgets.dart';

import '../../fakes/fake_reviews_repository.dart';
import '../repairs/layout_harness.dart';

String _ist(DateTime now, int daysAgo) =>
    now.toUtc().add(const Duration(hours: 5, minutes: 30)).subtract(Duration(days: daysAgo)).toIso8601String().substring(0, 10);

void main() {
  test('this week is the 7 IST days ending today', () {
    final now = DateTime.utc(2026, 11, 19, 20); // 01:30 on the 20th in IST
    expect(boughtThisWeek({'2026-11-20': 1, '2026-11-14': 2, '2026-11-13': 9, '2026-11-21': 5}, now), 3);
    expect(boughtThisWeek(const {}, now), 0);
  });

  test('together: pairs seen at least twice, most often first', () {
    expect(togetherIds({'a': 1, 'b': 2, 'c': 5, 'd': 2}), ['c', 'b', 'd']);
    expect(togetherIds({'a': 1}), isEmpty);
    expect(togetherIds({for (var i = 0; i < 12; i++) 'p$i': 3}).length, 8);
  });

  testWidgets('"N bought this week" shows from 3, never below', (tester) async {
    final now = DateTime.now();
    final repo = FakeReviewsRepository()
      ..statsOf = {
        'hot': ProductStats(sold: {_ist(now, 0): 2, _ist(now, 6): 2}),
        'quiet': ProductStats(sold: {_ist(now, 0): 2, _ist(now, 8): 5}),
      };
    await pumpScreen(tester, const Scaffold(body: Column(children: [BoughtThisWeek('hot'), BoughtThisWeek('quiet')])),
        overrides: [reviewsRepositoryProvider.overrideWithValue(repo)]);
    await tester.pumpAndSettle();
    expect(find.text('4 bought this week'), findsOneWidget);
    expect(find.textContaining('bought this week'), findsOneWidget);
  });
}
