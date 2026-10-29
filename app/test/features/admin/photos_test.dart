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

  test('preparePhoto refuses files over 15 MB before compressing', () async {
    await expectLater(
      preparePhoto(Uint8List(maxPhotoBytes + 1)),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('under 15 MB'))),
    );
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
