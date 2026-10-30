// Design review only, skipped in the normal suite: renders Home at 360x800 dp with the brand fonts (static TTFs in
// FONTS_DIR: jakarta-<weight>.ttf, familjen-<weight>.ttf, and the latin-ext ones for ₹) and the Phosphor icons into
// PREVIEW_OUT:
//   FONTS_DIR=… PREVIEW_OUT=… flutter test test/preview/home_preview_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/core/theme/theme.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/data/rails.dart';
import 'package:shyam_mobiles/features/catalog/screens/home_screen.dart';
import 'package:shyam_mobiles/features/offers/data/offers.dart';

import '../features/offers/fakes.dart';

ProductCard _card(String id, String name, String brand, int rupees, {String category = 'cases-covers', int? mrp}) =>
    ProductCard(
      id: id,
      slug: id,
      name: name,
      brandName: brand,
      categorySlug: category,
      minPricePaise: rupees * 100,
      mrpPaise: (mrp ?? (rupees * 1.2).round()) * 100,
      inStock: true,
    );

Future<void> _loadFonts(ThemeData theme) async {
  final dir = Platform.environment['FONTS_DIR']!;
  Future<void> load(String family, String file) async {
    final loader = FontLoader(family)..addFont(File(file).readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }

  // google_fonts names each family after its variant ("PlusJakartaSans_700"): load the matching static file
  final families = <String>{};
  for (final s in [theme.textTheme.displayLarge, theme.textTheme.displayMedium, theme.textTheme.displaySmall,
    theme.textTheme.headlineLarge, theme.textTheme.headlineMedium, theme.textTheme.headlineSmall,
    theme.textTheme.titleLarge, theme.textTheme.titleMedium, theme.textTheme.titleSmall, theme.textTheme.bodyLarge,
    theme.textTheme.bodyMedium, theme.textTheme.bodySmall, theme.textTheme.labelLarge, theme.textTheme.labelMedium,
    theme.textTheme.labelSmall]) {
    if (s?.fontFamily case final f?) families.add(f);
  }
  for (final f in families) {
    final [name, variant] = f.split('_');
    final weight = variant == 'regular' ? 400 : int.parse(variant.replaceAll(RegExp(r'\D'), ''));
    final prefix = name.startsWith('Familjen') ? 'familjen' : 'jakarta';
    final available = prefix == 'familjen' ? [400, 500, 600, 700] : [400, 500, 600, 700, 800];
    final w = available.reduce((a, b) => (a - weight).abs() <= (b - weight).abs() ? a : b);
    await load(f, '$dir/$prefix-$w.ttf');
  }
  // the latin subsets lack ₹: google_fonts styles fall back to the bare family name, so the extended files go there
  final ext = FontLoader('PlusJakartaSans');
  for (final w in [400, 700, 800]) {
    ext.addFont(File('$dir/jakarta-ext-$w.ttf').readAsBytes().then(ByteData.sublistView));
  }
  await ext.load();
  await load('FamiljenGrotesk', '$dir/familjen-ext-700.ttf');
  for (final (family, file) in [
    ('PhosphorRegular', 'Phosphor'),
    ('PhosphorFill', 'Phosphor-Fill'),
    ('PhosphorBold', 'Phosphor-Bold'),
    ('PhosphorLight', 'Phosphor-Light'),
  ]) {
    await load('packages/phosphor_flutter/$family', 'third_party/phosphor_flutter/lib/fonts/$file.ttf');
  }
}

void main() {
  final theme = lightTheme;

  final categories = [
    for (final (i, (slug, name, kind)) in [
      ('smartphones', 'Smartphones', CategoryKind.phone),
      ('keypad-phones', 'Keypad phones', CategoryKind.phone),
      ('cases-covers', 'Cases & covers', CategoryKind.accessory),
      ('screen-guards', 'Screen guards', CategoryKind.accessory),
      ('chargers-cables', 'Chargers & cables', CategoryKind.accessory),
      ('earbuds-headphones', 'Earbuds', CategoryKind.accessory),
      ('power-banks', 'Power banks', CategoryKind.accessory),
    ].indexed)
      Category(id: '$i', slug: slug, name: name, kind: kind, sort: i),
  ];
  final featured = [
    _card('s25', 'Samsung Galaxy S25', 'Samsung', 74999, category: 'smartphones', mrp: 80999),
    _card('rn14', 'Xiaomi Redmi Note 14 Pro 5G', 'Xiaomi', 23999, category: 'smartphones', mrp: 26999),
    _card('pixel', 'Google Pixel 9a', 'Google', 49999, category: 'smartphones', mrp: 52999),
    _card('a56', 'Samsung Galaxy A56 5G', 'Samsung', 38999, category: 'smartphones', mrp: 41999),
  ];
  final deals = [
    _card('case', 'Spigen Ultra Hybrid Case for iPhone 16', 'Spigen', 1299),
    _card('guard', 'Spigen GlasTR Galaxy S25 Screen Guard', 'Spigen', 999),
    _card('cable', 'Ambrane 60 W Type-C Cable', 'Ambrane', 299, category: 'chargers-cables'),
    _card('buds', 'boAt Airdopes 141', 'boAt', 1199, category: 'earbuds-headphones'),
  ];
  const settings = StoreSettings(
    deliveryFeePaise: 4900,
    freeDeliveryMinPaise: 99900,
    codEnabled: true,
    codMaxPaise: 2500000,
    storePhone: '+917987559272',
    storeAddress: 'Rajeev Complex, Waidhan, District Singrauli',
    storeHours: '10 am – 9 pm',
    repairNote: '',
  );

  final out = Platform.environment['PREVIEW_OUT'];
  for (final scale in [1.0, 1.4]) {
    testWidgets('home preview at ${scale}x text', skip: out == null || Platform.environment['FONTS_DIR'] == null,
        (tester) async {
      await tester.runAsync(() => _loadFonts(theme));
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(null),
          storeSettingsProvider.overrideWith((ref) async => settings),
          homeProvider.overrideWith((ref) async => (categories: categories, featured: featured, accessories: deals)),
          latestProvider.overrideWith((ref) async => [...deals, ...featured]),
          offersApiProvider.overrideWithValue(FakeOffersApi(bannerRows: [
            PromoBanner(
              id: 'b1',
              title: 'Diwali dhamaka: flat ₹500 off every phone',
              subtitle: 'Till Sunday. Use code DIWALI500 at checkout.',
              ctaLabel: 'Use code DIWALI500',
              link: '/offers',
              tone: 1,
              startsAt: DateTime(2026),
            ),
          ])),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              devicePixelRatio: 3,
              padding: const EdgeInsets.only(top: 24, bottom: 16),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: const HomeScreen(),
              bottomNavigationBar: NavigationBar(destinations: const [
                NavigationDestination(icon: Icon(PhosphorIconsFill.house), label: 'Home'),
                NavigationDestination(icon: Icon(PhosphorIconsRegular.magnifyingGlass), label: 'Search'),
                NavigationDestination(icon: Icon(PhosphorIconsRegular.wrench), label: 'Repairs'),
                NavigationDestination(icon: Icon(PhosphorIconsRegular.shoppingBag), label: 'Cart'),
                NavigationDestination(icon: Icon(PhosphorIconsRegular.user), label: 'Account'),
              ]),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$out/home_${scale}x.png'));
      await tester.pumpWidget(const SizedBox()); // stops the carousel timer
    });
  }
}
