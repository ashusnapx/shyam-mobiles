import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/features/admin/data/photos.dart';

/// A real PNG of [w]x[h] (transparent, like a screenshot with an alpha channel).
Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(ui.Rect.fromLTWH(0, 0, w / 2, h / 2), ui.Paint()..color = const ui.Color(0xFF0A0A0A));
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  group('photoPlan: longest side ≤ the limit, aspect kept, decoded small first', () {
    // (width, height, max) → (inSampleSize, out width, out height)
    const table = <(int, int, int, int, int, int)>[
      (4000, 3000, 1600, 2, 1600, 1200), // 12 MP landscape
      (3000, 4000, 1600, 2, 1200, 1600), // portrait
      (8160, 6120, 1600, 4, 1600, 1200), // 50 MP: decoded at 1/4, never at 200 MB
      (12000, 9000, 1600, 4, 1600, 1200), // 108 MP: 1/8 would drop below 1600
      (1600, 1200, 1600, 1, 1600, 1200), // already the size
      (1080, 2400, 1600, 1, 720, 1600), // phone screenshot
      (900, 600, 1600, 1, 900, 600), // small: never upscaled
      (4000, 4000, 1600, 2, 1600, 1600), // square
      (1600, 1200, 480, 2, 480, 360), // thumb from the full photo
      (1200, 1600, 480, 2, 360, 480),
      (5000, 100, 1600, 2, 1600, 32), // panorama strip
    ];
    for (final (w, h, maxSide, sample, outW, outH) in table) {
      test('$w×$h → ≤$maxSide', () {
        final p = photoPlan(w, h, maxSide);
        expect(p.inSampleSize, sample);
        expect((p.width, p.height), (outW, outH));
        expect(p.width <= maxSide && p.height <= maxSide, isTrue);
        // the decode itself is at least as big as the output
        expect(w ~/ p.inSampleSize >= p.width && h ~/ p.inSampleSize >= p.height, isTrue);
      });
    }
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(180 * 1024), '180 KB');
    expect(formatBytes(4404019), '4.2 MB');
    expect(formatBytes(15 * 1024 * 1024), '15.0 MB');
  });

  test('any camera photo is accepted; only what no camera makes is refused', () {
    checkPhotoSize(48 * 1024 * 1024); // a 200 MP original
    expect(() => checkPhotoSize(maxPhotoBytes + 1),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('too big to be a photo'))));
  });

  test('fitBudget keeps the best step that fits and lowers quality before size', () async {
    final tried = <(int, int)>[];
    Future<Uint8List> encode(int side, int quality) async {
      tried.add((side, quality));
      return Uint8List(side * quality * 10); // stands in for the WebP: bigger and better weigh more
    }

    expect((await fitBudget(encode, budget: 2000000)).length, 1600 * 80 * 10); // fits at once: full quality
    expect(tried, [(1600, 80)]);
    tried.clear();
    expect((await fitBudget(encode, budget: 900000)).length, 1400 * 64 * 10); // quality 80→72→64, then 1400 px
    expect(tried, [(1600, 80), (1600, 72), (1600, 64), (1400, 64)]);
    tried.clear();
    expect((await fitBudget(encode, budget: 10)).length, 1000 * 56 * 10); // nothing fits: the smallest try
    expect(tried.length, photoSteps.length);
  });

  test('preparePhoto refuses files that aren’t images', () async {
    final pdf = Uint8List.fromList('%PDF-1.7 not a photo'.codeUnits);
    await expectLater(
      preparePhoto(pdf),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('isn’t a photo'))),
    );
    // a JPEG header with nothing after it: corrupt
    await expectLater(preparePhoto(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0])), throwsA(isA<FormatException>()));
  });

  testWidgets('imageSizeOf reads the size from the header (transparent PNG)', (tester) async {
    final size = await tester.runAsync(() async => imageSizeOf(await _png(1080, 2400)));
    expect(size, (1080, 2400));
  });

  test('the social JPEG is 1080 px wide at most, whatever the photo\'s shape', () {
    for (final (w, h) in [(4000, 3000), (3000, 4000), (1920, 1080), (1080, 2400), (800, 600), (4000, 4000)]) {
      final out = photoPlan(w, h, socialMaxSide(w, h));
      expect(out.width, lessThanOrEqualTo(socialWidth), reason: '$w x $h');
      expect(out.width, greaterThanOrEqualTo(w < socialWidth ? w : socialWidth - 2), reason: '$w x $h: no needless shrink');
    }
  });

  test('alphaBounds: the box around the visible pixels, none when all transparent', () {
    final rgba = Uint8List(4 * 5 * 4); // 5 x 4, all transparent
    expect(alphaBounds(rgba, 5, 4), isNull);
    rgba[(1 * 5 + 2) * 4 + 3] = 255; // (2, 1)
    rgba[(2 * 5 + 3) * 4 + 3] = 200; // (3, 2)
    rgba[(3 * 5 + 0) * 4 + 3] = 5; // (0, 3): faint, ignored
    expect(alphaBounds(rgba, 5, 4), const ui.Rect.fromLTRB(2, 1, 4, 3));
  });

  // A 120 × 40 opaque bar on a 200 × 200 canvas, turned [degrees] (y down) about the centre.
  Uint8List bar(double degrees, {double w = 120, double h = 40}) {
    final rgba = Uint8List(200 * 200 * 4);
    final a = degrees * pi / 180;
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 200; x++) {
        final dx = x - 100.0, dy = y - 100.0;
        final u = dx * cos(a) + dy * sin(a), v = -dx * sin(a) + dy * cos(a); // back into the bar's own axes
        if (u.abs() <= w / 2 && v.abs() <= h / 2) rgba[(y * 200 + x) * 4 + 3] = 255;
      }
    }
    return rgba;
  }

  test('a product photographed slightly tilted is turned straight; a straight, square or steep one is left', () {
    for (final d in [-8.0, -3.0, 4.0, 10.0]) {
      expect(tiltOf(bar(d), 200, 200) * 180 / pi, closeTo(d, 0.6), reason: '$d°');
    }
    expect(tiltOf(bar(87), 200, 200) * 180 / pi, closeTo(-3, 0.6), reason: 'standing up, 3° off vertical');
    expect(tiltOf(bar(0), 200, 200), 0);
    expect(tiltOf(bar(30), 200, 200), 0, reason: 'over 12°: on purpose');
    expect(tiltOf(bar(6, w: 60, h: 60), 200, 200), 0, reason: 'a square has no long axis');
  });

  test('a dim photo is stretched to full range, capped at 1.4×; a full-range one is left alone', () {
    Uint8List grey(int from, int to) {
      final rgba = Uint8List(256 * 4 * 2);
      for (var i = 0; i < 512; i++) {
        final v = from + (to - from) * (i % 256) ~/ 255;
        rgba.setAll(i * 4, [v, v, v, 255]);
      }
      return rgba;
    }

    final (g1, l1) = levelsOf(grey(40, 210));
    expect(g1, closeTo(1.4, 0.001));
    expect(42 * g1 + l1, closeTo(0, 6), reason: 'the darkest stays near black');
    final (g2, l2) = levelsOf(grey(0, 255));
    expect(g2, closeTo(1, 0.05));
    expect(l2, closeTo(0, 4));
    expect(levelsOf(grey(120, 130)), (1.0, 0.0), reason: 'one flat colour');
  });

  test('red and blue are swapped before ML Kit, so its own swap gives the true colours back', () {
    expect(swapRedBlue(Uint8List.fromList([10, 20, 30, 255, 1, 2, 3, 4])), [30, 20, 10, 255, 3, 2, 1, 4]);
  });
}
