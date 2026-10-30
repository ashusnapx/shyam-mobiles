// Counters, presses, scroll reveals and parallax: they land on exact values, keep taps working, run once, and step
// aside entirely when the phone asks for less motion.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/widgets/motion.dart';
import 'package:shyam_mobiles/core/widgets/widgets.dart';

Widget _app(Widget child, {bool reduce = false}) => ProviderScope(
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(360, 800), disableAnimations: reduce),
          child: Scaffold(body: child),
        ),
      ),
    );

void main() {
  testWidgets('CountTo rolls to the exact new value; fromZero counts up from 0 first', (tester) async {
    Widget at(int paise, {bool fromZero = false}) => _app(Center(child: CountTo(paise, fromZero: fromZero)));
    await tester.pumpWidget(at(7499900));
    expect(find.text('₹74,999'), findsOneWidget, reason: 'no count on first show');
    await tester.pumpWidget(at(8699900));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('₹86,999'), findsNothing, reason: 'still rolling');
    await tester.pumpAndSettle();
    expect(find.text('₹86,999'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(at(129900, fromZero: true));
    expect(find.text('₹0'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('₹1,299'), findsOneWidget);
    expect(tester.getSemantics(find.byType(CountTo)).label, '₹1,299');
  });

  testWidgets('with reduced motion: plain widgets, final values at once', (tester) async {
    await tester.pumpWidget(_app(
      ListView(children: [
        const CountTo(129900, fromZero: true),
        Pressable(child: InkWell(onTap: () {}, child: const Text('Tile'))),
        const RevealOnScroll(child: Text('Header')),
        const Parallax(child: Text('Photo')),
        const BrandMark(ripple: true),
      ]),
      reduce: true,
    ));
    expect(find.text('₹1,299'), findsOneWidget);
    expect(find.descendant(of: find.byType(Pressable), matching: find.byType(ScaleTransition)), findsNothing);
    expect(find.descendant(of: find.byType(RevealOnScroll), matching: find.byType(FadeTransition)), findsNothing);
    expect(find.descendant(of: find.byType(Parallax), matching: find.byType(AnimatedBuilder)), findsNothing);
    expect(find.descendant(of: find.byType(CountTo), matching: find.byType(TweenAnimationBuilder<int>)), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('Pressable dips under the finger, springs back, and the tap still lands', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(Center(
      child: Pressable(child: InkWell(onTap: () => taps++, child: const SizedBox.square(dimension: 100))),
    )));
    double scale() =>
        tester.widget<ScaleTransition>(find.descendant(of: find.byType(Pressable), matching: find.byType(ScaleTransition))).scale.value;
    final press = await tester.startGesture(tester.getCenter(find.byType(InkWell)));
    await tester.pump(); // the ticker's first frame
    await tester.pump(const Duration(milliseconds: 120));
    expect(scale(), lessThan(0.97));
    await press.up();
    await tester.pumpAndSettle();
    expect(scale(), closeTo(1, 0.001));
    expect(taps, 1);
  });

  testWidgets('a finger that starts scrolling lets go of the card', (tester) async {
    await tester.pumpWidget(_app(ListView(children: [
      for (var i = 0; i < 3; i++)
        Pressable(child: InkWell(onTap: () {}, child: SizedBox(height: 300, child: Text('Card $i')))),
    ])));
    final drag = await tester.startGesture(tester.getCenter(find.text('Card 0')));
    await drag.moveBy(const Offset(0, -60));
    await tester.pumpAndSettle();
    final scale = tester
        .widget<ScaleTransition>(find.descendant(of: find.byType(Pressable).first, matching: find.byType(ScaleTransition)))
        .scale
        .value;
    expect(scale, closeTo(1, 0.001));
    await drag.up();
  });

  testWidgets('RevealOnScroll: shown at once on screen; below the fold it rises in once, when it scrolls in',
      (tester) async {
    // as on Home: sliver boxes, built up front and laid out as they near the screen
    await tester.pumpWidget(_app(const CustomScrollView(slivers: [
      SliverToBoxAdapter(child: RevealOnScroll(child: Text('Top'))),
      SliverToBoxAdapter(child: SizedBox(height: 1200)),
      SliverToBoxAdapter(child: RevealOnScroll(child: Text('Below'))),
      SliverToBoxAdapter(child: SizedBox(height: 600)),
    ])));
    await tester.pump();
    double opacity(String text) => tester
        .widget<FadeTransition>(
            find.ancestor(of: find.text(text, skipOffstage: false), matching: find.byType(FadeTransition, skipOffstage: false)).first)
        .opacity
        .value;
    expect(opacity('Top'), 1);
    expect(opacity('Below'), 0);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(opacity('Below'), 1);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 1000)); // away and back: no replay
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pump();
    expect(opacity('Below'), 1);
  });

  testWidgets('Parallax: the child drifts by its rate of the scroll, transform only', (tester) async {
    await tester.pumpWidget(_app(ListView(children: const [
      Parallax(rate: 0.5, child: SizedBox(height: 200, child: Text('Photo'))),
      SizedBox(height: 2000),
    ])));
    final before = tester.getTopLeft(find.text('Photo')).dy;
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Photo')).dy, closeTo(before - 100 + 50, 1), reason: 'half the scroll');
  });
}
