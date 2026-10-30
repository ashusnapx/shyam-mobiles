import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/network.dart';
import 'package:shyam_mobiles/features/catalog/widgets/gallery.dart';

ProductPhoto photo(String path, [String? color]) => ProductPhoto(id: path, path: path, color: color);

void main() {
  group('photosFor', () {
    final photos = [photo('box'), photo('navy-front', 'Navy'), photo('icy-front', 'Icyblue'), photo('back'), photo('navy-side', 'Navy')];
    List<String> paths(String color) => [for (final p in photosFor(photos, color)) p.path];

    test("the colour's own photos first, then the untagged ones; other colours' stay out", () {
      expect(paths('Navy'), ['navy-front', 'navy-side', 'box', 'back']);
      expect(paths('Icyblue'), ['icy-front', 'box', 'back']);
    });

    test('a colour without photos of its own, or no colour at all, shows every photo', () {
      expect(paths('Mint'), ['box', 'navy-front', 'icy-front', 'back', 'navy-side']);
      expect(paths(''), paths('Mint'));
      expect(photosFor(const [], 'Navy'), isEmpty);
    });
  });

  group('ProductGallery', () {
    Future<void> pump(WidgetTester tester, List<String> paths, {DataMode mode = DataMode.full}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [dataSaverProvider.overrideWithValue(mode)],
        child: MaterialApp(home: Scaffold(body: ListView(children: [ProductGallery(paths: paths)]))),
      ));
    }

    Future<void> tapPhoto(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel(RegExp('opens full screen')).first);
      await tester.pump(kDoubleTapTimeout); // a tap waits out the double-tap window
      await tester.pumpAndSettle();
    }

    testWidgets('is a full-width square with a thumbnail strip that jumps to a photo', (tester) async {
      await pump(tester, ['p/1.webp', 'p/2.webp', 'p/3.webp']);
      expect(tester.getSize(find.byType(PageView)), const Size(360, 360));
      expect(find.bySemanticsLabel('Photo 1 of 3, opens full screen'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Photo 3 of 3'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Photo 3 of 3, opens full screen'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Photo 3 of 3')), containsSemantics(isSelected: true));
      // Previous / Next as well as the swipe
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, PhosphorIconsBold.caretRight)).onPressed, isNull);
      await tester.tap(find.byTooltip('Previous photo'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Photo 2 of 3, opens full screen'), findsOneWidget);
    });

    testWidgets('one photo: no strip', (tester) async {
      await pump(tester, ['p/1.webp']);
      expect(find.bySemanticsLabel('Product photo, opens full screen'), findsOneWidget);
      expect(find.bySemanticsLabel('Photo 1 of 1'), findsNothing);
    });

    testWidgets('tap opens the full-screen viewer, which pages and closes', (tester) async {
      await pump(tester, ['p/1.webp', 'p/2.webp', 'p/3.webp']);
      await tapPhoto(tester);
      expect(find.text('1 of 3'), findsOneWidget);
      await tester.fling(find.byType(PageView).last, const Offset(-300, 0), 1000); // the viewer's
      await tester.pumpAndSettle();
      expect(find.text('2 of 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Next photo').last); // the viewer's button
      await tester.pumpAndSettle();
      expect(find.text('3 of 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous photo').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fit to screen'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3'), findsNothing);
      // the gallery followed along, so the photo flew back to the same place
      expect(find.bySemanticsLabel('Photo 2 of 3, opens full screen'), findsOneWidget);
    });

    testWidgets('the viewer loads the full photo even in data-saver mode', (tester) async {
      await pump(tester, ['p/1.webp'], mode: DataMode.saver);
      final inline = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage).first);
      expect(inline.imageUrl, endsWith('/p/1@thumb.webp'));
      await tapPhoto(tester);
      final urls = [for (final w in tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))) w.imageUrl];
      expect(urls, contains(endsWith('/p/1.webp')));
    });

    testWidgets('double-tap zooms in and stops the swipe to the next photo; double-tap again fits', (tester) async {
      await pump(tester, ['p/1.webp', 'p/2.webp']);
      final page = find.byType(PageView);
      Future<void> doubleTap() async {
        await tester.tapAt(tester.getCenter(page));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(tester.getCenter(page));
        await tester.pumpAndSettle();
      }

      double scale() => tester.widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
          .transformationController!
          .value
          .getMaxScaleOnAxis();
      await doubleTap();
      expect(scale(), greaterThan(2));
      expect(tester.widget<PageView>(page).physics, isA<NeverScrollableScrollPhysics>());
      await doubleTap();
      expect(scale(), closeTo(1, 0.01));
      expect(tester.widget<PageView>(page).physics, isNull);
    });
  });
}
