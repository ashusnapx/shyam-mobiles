// Renders the notification illustrations, skipped in the normal suite:
//   ART_OUT=assets/notification_art flutter test test/preview/notification_art_test.dart     # the PNGs Android shows
//   PREVIEW_OUT=/path/sheet.png flutter test test/preview/notification_art_test.dart          # every kind on one sheet
// One PNG per look actually used (group, icon, badge): 48 dp at 3x, the size of a notification's large icon.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/features/notifications/widgets/notification_art.dart';

Future<void> _fonts() async {
  Future<void> load(String family, String file) =>
      (FontLoader(family)..addFont(File(file).readAsBytes().then(ByteData.sublistView))).load();
  for (final (family, file) in [('PhosphorRegular', 'Phosphor'), ('PhosphorFill', 'Phosphor-Fill'), ('PhosphorBold', 'Phosphor-Bold')]) {
    await load('packages/phosphor_flutter/$family', 'third_party/phosphor_flutter/lib/fonts/$file.ttf');
  }
  final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  await (FontLoader('Roboto')
        ..addFont(File('$dir/Roboto-Regular.ttf').readAsBytes().then(ByteData.sublistView))
        ..addFont(File('$dir/Roboto-Bold.ttf').readAsBytes().then(ByteData.sublistView)))
      .load();
}

Future<void> _png(WidgetTester tester, Widget child, Size size, double ratio, String path) async {
  final key = GlobalKey();
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Theme(
      data: ThemeData(colorScheme: lightScheme, fontFamily: 'Roboto'),
      child: Center(child: RepaintBoundary(key: key, child: SizedBox.fromSize(size: size, child: child))),
    ),
  ));
  await tester.pump();
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  });
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

void main() {
  final artOut = Platform.environment['ART_OUT'];
  final sheetOut = Platform.environment['PREVIEW_OUT'];

  testWidgets('notification art PNGs', skip: artOut == null, (tester) async {
    await tester.runAsync(_fonts);
    addTearDown(tester.view.reset);
    final looks = {for (final e in notificationArt.entries) artAsset(e.value): e.key, artAsset(defaultArt): ''};
    for (final MapEntry(key: asset, value: kind) in looks.entries) {
      await _png(tester, NotificationArt(kind: kind), const Size.square(48), 3, '$artOut/${asset.split('/').last}');
    }
    // nothing left over from a look no kind uses any more
    for (final f in Directory(artOut!).listSync().whereType<File>()) {
      expect(looks.keys.map((a) => a.split('/').last), contains(f.uri.pathSegments.last));
    }
  });

  testWidgets('notification art preview sheet', skip: sheetOut == null, (tester) async {
    await tester.runAsync(_fonts);
    addTearDown(tester.view.reset);
    final kinds = [...notificationArt.keys, 'something_new'];
    const cols = 5;
    final rows = (kinds.length / cols).ceil();
    await _png(
      tester,
      ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 12,
            children: [
              for (final k in kinds)
                SizedBox(
                  width: 128,
                  child: Column(children: [
                    NotificationArt(kind: k, size: 64),
                    const SizedBox(height: 6),
                    Text(k, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Roboto', fontSize: 10, color: BrandColors.graphite)),
                  ]),
                ),
            ],
          ),
        ),
      ),
      Size(32 + cols * 128 + (cols - 1) * 8, 32 + rows * 104.0),
      2,
      sheetOut!,
    );
  });
}
