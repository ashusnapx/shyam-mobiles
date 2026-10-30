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
}
