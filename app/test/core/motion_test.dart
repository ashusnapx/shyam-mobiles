import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/widgets/widgets.dart';

void main() {
  testWidgets('Bump is still on first build and pops when its trigger changes', (tester) async {
    Widget at(int n) => Directionality(
          textDirection: TextDirection.ltr,
          child: Bump(trigger: n, child: const SizedBox.square(dimension: 10)),
        );
    double scale() => tester
        .widget<ScaleTransition>(find.descendant(of: find.byType(Bump), matching: find.byType(ScaleTransition)))
        .scale
        .value;
    await tester.pumpWidget(at(0));
    expect(scale(), 1);
    await tester.pumpWidget(at(0)); // same count: nothing
    expect(scale(), 1);
    await tester.pumpWidget(at(1));
    await tester.pump(const Duration(milliseconds: 16));
    expect(scale(), greaterThan(1.05));
    await tester.pumpAndSettle();
    expect(scale(), 1);
  });

  testWidgets('enter() animates, unless the phone asks for less motion', (tester) async {
    Widget screen({required bool reduce}) => MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(builder: (context) => const Text('Phones').enter(context, index: 2)),
          ),
        );
    await tester.pumpWidget(screen(reduce: false));
    expect(find.byType(Animate), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen(reduce: true));
    expect(find.byType(Animate), findsNothing);
    expect(find.text('Phones'), findsOneWidget);
  });
}
