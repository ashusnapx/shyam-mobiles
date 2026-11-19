import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/stories.dart';

void main() {
  const story = (
    id: 'p1',
    name: 'Samsung Galaxy S25 Ultra Titanium Edition 1 TB Titanium Silverblue',
    price: '₹1,29,999',
    photo: null,
    link: 'https://shyam-mobiles.web.app/open?p=samsung-galaxy-s25-ultra',
  );

  testWidgets('no Share to Story buttons without META_APP_ID, and the phone is never asked', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('shyam_mobiles/stories'), (c) async {
      calls.add(c);
      return ['instagram', 'facebook'];
    });
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: Scaffold(body: StoryTiles(story)))));
    await tester.pump();
    expect(find.byType(ListTile), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('the story card fits a long name at 360x640 (1080x1920 at 3x)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Center(child: SizedBox(width: 360, height: 640, child: StoryCard(story)))));
    expect(tester.takeException(), isNull);
    expect(find.text('Shyam Mobiles · Waidhan'), findsOneWidget);
    expect(find.text('₹1,29,999'), findsOneWidget);
  });
}
