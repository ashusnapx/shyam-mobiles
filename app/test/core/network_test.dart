import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/network.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/core/widgets/widgets.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';

void main() {
  group('decideDataMode', () {
    const s = DataMode.saver, f = DataMode.full;
    // (network, latency ms, low RAM) → mode
    const table = <(NetType, int?, bool, DataMode)>[
      // wifi is fast until measured slow
      (NetType.wifi, null, false, f),
      (NetType.wifi, 200, false, f),
      (NetType.wifi, 800, false, f),
      (NetType.wifi, 801, false, s),
      // mobile data is slow until measured fast
      (NetType.mobile, null, false, s),
      (NetType.mobile, 400, false, f),
      (NetType.mobile, 1500, false, s),
      // offline or unknown keeps the last reading (nothing loads anyway)
      (NetType.none, null, false, f),
      (NetType.none, 2000, false, s),
      (NetType.unknown, null, false, f),
      // a low-RAM phone always saves
      (NetType.wifi, 100, true, s),
      (NetType.unknown, null, true, s),
    ];
    for (final (net, ms, lowRam, want) in table) {
      test('$net · ${ms ?? '?'} ms · lowRam $lowRam → $want', () {
        expect(decideDataMode(net: net, latencyMs: ms, lowRam: lowRam), want);
      });
    }
  });

  test('netTypeOf', () {
    expect(netTypeOf([ConnectivityResult.wifi]), NetType.wifi);
    expect(netTypeOf([ConnectivityResult.ethernet]), NetType.wifi);
    expect(netTypeOf([ConnectivityResult.vpn, ConnectivityResult.mobile]), NetType.mobile);
    expect(netTypeOf([ConnectivityResult.mobile, ConnectivityResult.wifi]), NetType.wifi);
    expect(netTypeOf([ConnectivityResult.none]), NetType.none);
    expect(netTypeOf([]), NetType.none);
    expect(netTypeOf([ConnectivityResult.vpn]), NetType.unknown);
  });

  test('a fresh container is in full mode and online (no platform calls before start)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(dataSaverProvider), DataMode.full);
    expect(c.read(offlineProvider), isFalse);
  });

  test('thumbPathFor', () {
    expect(thumbPathFor('p1/1730000000000.webp'), 'p1/1730000000000@thumb.webp');
    expect(thumbPathFor('store/1730000000000.webp'), 'store/1730000000000@thumb.webp');
    expect(thumbPathFor('p1/1.jpg'), isNull); // older uploads never had one
    expect(thumbPathFor('p1/1.png'), isNull);
  });

  group('saved payloads', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('store settings and home survive the round trip', () async {
      final settingsRow = {
        'id': true,
        'delivery_fee_paise': 4900,
        'free_delivery_min_paise': 99900,
        'cod_enabled': true,
        'cod_max_paise': 2500000,
        'store_phone': '+917987559272',
        'store_address': 'Rajeev Complex, Waidhan',
        'store_lat': 24.0670269,
        'store_lng': 82.6307508,
        'store_maps_url': null,
        'store_photos': ['store/1.webp', 'store/2.jpg'],
        'store_hours': '10 am – 9 pm',
        'repair_note': 'Final price after inspection.',
        'returns_policy': '7 days, unopened.',
      };
      await writeSaved('store_settings', settingsRow);
      final s = StoreSettings.fromJson((await readSaved('store_settings'))! as Map<String, dynamic>);
      expect(s.storePhotos, ['store/1.webp', 'store/2.jpg']);
      expect(s.storeLat, 24.0670269);
      expect(s.codMaxPaise, 2500000);

      final card = {
        'id': 'p1', 'slug': 'galaxy-s25', 'name': 'Samsung Galaxy S25', 'is_featured': true,
        'category_slug': 'smartphones', 'brand_name': 'Samsung', 'min_price_paise': 7499900,
        'mrp_paise': 8099900, 'in_stock': true, 'cover_path': 'p1/1.webp',
      };
      await writeSaved('home', {
        'categories': [{'id': 'c1', 'slug': 'smartphones', 'name': 'Smartphones', 'kind': 'phone', 'sort': 1}],
        'featured': [card],
        'accessories': <Object>[],
      });
      final home = homeFromJson(await readSaved('home'));
      expect(home.categories.single.kind, CategoryKind.phone);
      expect(home.featured.single.coverPath, 'p1/1.webp');
      expect(home.featured.single.minPricePaise, 7499900);
      expect(home.accessories, isEmpty);
    });

    test('nothing saved reads as null', () async {
      expect(await readSaved('never-saved'), isNull);
    });

    test('savedOrFetch shows the saved copy first, then the fresh one', () async {
      await writeSaved('swr-test', {'n': 1});
      var fetches = 0;
      final provider = FutureProvider<int>((ref) => savedOrFetch(ref, 'swr-test', () async {
            fetches++;
            return {'n': 2};
          }, (j) => (j! as Map<String, dynamic>)['n'] as int));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final sub = c.listen(provider, (_, _) {});
      addTearDown(sub.close);
      expect(await c.read(provider.future), 1); // at once, from the phone
      await pumpEventQueue();
      expect(await c.read(provider.future), 2); // the background refresh replaced it
      expect(fetches, 1); // and wasn't fetched twice
      expect(await readSaved('swr-test'), {'n': 2}); // saved for next time
    });

    test('savedOrFetch keeps the saved copy when the refresh fails (offline)', () async {
      await writeSaved('swr-offline', {'n': 1});
      final provider = FutureProvider<int>((ref) => savedOrFetch(
          ref, 'swr-offline', () async => throw const SocketLikeError(), (j) => (j! as Map<String, dynamic>)['n'] as int));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final sub = c.listen(provider, (_, _) {});
      addTearDown(sub.close);
      expect(await c.read(provider.future), 1);
      await pumpEventQueue();
      expect(c.read(provider).value, 1);
      expect(c.read(provider).hasError, isFalse);
    });
  });

  group('ProductImage in data-saver mode', () {
    Future<void> pump(WidgetTester tester, DataMode mode, String path) => tester.pumpWidget(ProviderScope(
          overrides: [dataSaverProvider.overrideWithValue(mode)],
          child: MaterialApp(home: Scaffold(body: SizedBox(width: 300, child: ProductImage(path, full: true)))),
        ));

    testWidgets('the gallery offers the full photo only in saver mode, and only for photos with a thumb', (tester) async {
      await pump(tester, DataMode.full, 'p1/100.webp');
      expect(find.text('Tap for full photo'), findsNothing);
      await pump(tester, DataMode.saver, 'p1/1.jpg'); // no thumb exists: the full photo, no button
      expect(find.text('Tap for full photo'), findsNothing);
      await pump(tester, DataMode.saver, 'p1/101.webp');
      expect(find.text('Tap for full photo'), findsOneWidget);
      await tester.tap(find.text('Tap for full photo'));
      await tester.pump();
      expect(find.text('Tap for full photo'), findsNothing);
    });
  });
}

class SocketLikeError implements Exception {
  const SocketLikeError();
}
