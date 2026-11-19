import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/theme/generative.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/core/widgets/motion.dart';
import 'package:shyam_mobiles/features/offers/widgets/offer_widgets.dart';

void main() {
  Future<void> pumpBanner(WidgetTester tester, {required bool reduce}) => tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Scaffold(
              body: PromoBannerCard(PromoBanner(
                id: 'b1',
                title: 'Diwali sale',
                link: '/offers',
                imagePath: 'p1/1.webp',
                startsAt: DateTime(2026),
                endsAt: DateTime.now().add(const Duration(days: 2, hours: 4, minutes: 30)),
              )),
            ),
          ),
        ),
      ));

  testWidgets('reduce-motion: the banner holds still (no Ken Burns, sweep or pop)', (tester) async {
    await pumpBanner(tester, reduce: true);
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('with motion on, the banner moves and shows a live countdown', (tester) async {
    await pumpBanner(tester, reduce: false);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.text('Ends in 2d 4h'), findsOneWidget);
  });

  test('countdown: days and hours, then hours and minutes, then minutes; null once ended', () {
    final now = DateTime(2026, 11, 19, 10);
    expect(countdown(now.add(const Duration(days: 2, hours: 4, minutes: 59)), now: now), 'Ends in 2d 4h');
    expect(countdown(now.add(const Duration(hours: 3, minutes: 12, seconds: 30)), now: now), 'Ends in 3h 12m');
    expect(countdown(now.add(const Duration(minutes: 9, seconds: 59)), now: now), 'Ends in 9m');
    expect(countdown(now.add(const Duration(seconds: 20)), now: now), 'Ends in 1m');
    expect(countdown(now, now: now), isNull);
    expect(countdown(now.subtract(const Duration(hours: 1)), now: now), isNull);
  });

  test('the sweep keeps white text on the glass panel at 4.5:1 or more, for many seeds', () {
    final sheen = Colors.white.withValues(alpha: sweepAlpha);
    for (var i = 0; i < 400; i++) {
      for (final stop in deepPalette('seed-$i').stops) {
        final bg = Color.alphaBlend(sheen, Color.alphaBlend(Glass.onDeep, stop));
        expect(contrast(Colors.white, bg), greaterThanOrEqualTo(4.5), reason: 'seed-$i $stop');
      }
    }
  });
}
