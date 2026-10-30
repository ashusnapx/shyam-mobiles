import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';

bool _fontLoaded = false;

/// Loads the SDK's Roboto so text has real widths (the default test font draws every glyph 1em wide).
/// google_fonts can't fetch in tests; Roboto is a little narrower than Plus Jakarta Sans, hence 1.4x below.
Future<void> _loadRoboto() async {
  if (_fontLoaded) return;
  _fontLoaded = true;
  final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Roboto');
  for (final f in ['Regular', 'Medium', 'Bold', 'Black']) {
    final file = File('$dir/Roboto-$f.ttf');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await loader.load();
}

/// Pumps [screen] at 360x800 dp with large text (≈1.3x of the real font), light theme only, no network.
/// [routes] are stand-in pages the screen can navigate to (each shows its path).
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  bool dark = false,
  StoreSettings store = testSettings,
  List<String> routes = const [],
}) async {
  await tester.runAsync(_loadRoboto);
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => screen),
    for (final r in routes) GoRoute(path: r, builder: (_, s) => Scaffold(body: Text('Page ${s.uri}'))),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(), // fresh container when a test pumps a second screen with other overrides
      overrides: [
        currentUserIdProvider.overrideWithValue('user-1'),
        isAdminProvider.overrideWithValue(const AsyncData(true)),
        storeSettingsProvider.overrideWithValue(AsyncData(store)),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: ThemeData(colorScheme: lightScheme, fontFamily: 'Roboto'),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Scrolls the screen's main list until [finder] is built and visible.
Future<void> scrollTo(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);

const testSettings = StoreSettings(
  deliveryFeePaise: 4900,
  freeDeliveryMinPaise: 99900,
  codEnabled: true,
  codMaxPaise: 2500000,
  storePhone: '+919999999999',
  storeAddress: 'Shop 4, Main Market, Lajpat Nagar, New Delhi 110024',
  storeHours: '10 am – 9 pm',
  repairNote: 'Final price is confirmed after inspection at the store.',
  returnsPolicy: 'Unopened items can be returned within 7 days of delivery.',
);

RepairBooking testBooking({RepairStatus status = RepairStatus.confirmed, int? quote = 249900}) => RepairBooking(
      id: 'b1',
      number: 'RP100012',
      deviceBrand: 'Samsung',
      deviceModel: 'Galaxy S23 Ultra',
      issue: RepairIssue.waterDamage,
      description: 'Fell in a bucket, screen flickers and the speaker sounds muffled.',
      preferredDate: DateTime(2026, 10, 30),
      slot: RepairSlot.afternoon,
      contactPhone: '+919876543210',
      status: status,
      createdAt: DateTime(2026, 10, 29, 10),
      quotePaise: quote,
      adminNote: 'Bring the charger too, please.',
    );
