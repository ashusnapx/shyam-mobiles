import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/theme/generative.dart';

void main() {
  test('the same seed gives the same colours; different seeds differ', () {
    expect(deepPalette('banner-1').stops, deepPalette('banner-1').stops);
    expect(deepPalette('banner-1').stops, isNot(deepPalette('banner-2').stops));
  });

  test('white text passes AA on every deep stop, for many seeds', () {
    for (var i = 0; i < 400; i++) {
      for (final c in deepPalette('seed-$i').stops) {
        expect(contrast(c, Colors.white), greaterThanOrEqualTo(4.5), reason: 'seed-$i $c');
      }
    }
  });

  test('soft accents read on their band (3:1), and bands stay near white', () {
    for (var i = 0; i < 400; i++) {
      final p = softPalette('cat-$i');
      expect(contrast(p.accent, p.band), greaterThanOrEqualTo(3), reason: 'cat-$i');
      expect(p.band.computeLuminance(), greaterThan(0.8), reason: 'cat-$i');
    }
  });

  test('oklch stays in gamut and matches known points', () {
    expect(oklch(1, 0, 0), const Color(0xFFFFFFFF));
    expect(oklch(0, 0, 0), const Color(0xFF000000));
    final vivid = oklch(0.7, 0.4, 145); // far outside sRGB: chroma is reduced, not clipped into a different hue
    expect(vivid.g, greaterThan(vivid.r));
    expect(vivid.g, greaterThan(vivid.b));
  });

  testWidgets('the aurora paints, and stays still when the phone asks for less motion', (tester) async {
    Widget at({required bool reduce}) => MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(width: 300, height: 150, child: AuroraBackground(palette: deepPalette('x'), seed: 'x')),
          ),
        );
    await tester.pumpWidget(at(reduce: true));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(at(reduce: false));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox()); // dispose the repeating drift
  });
}
