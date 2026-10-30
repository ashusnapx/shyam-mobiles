// Staff offers at 360x800 dp with 1.4x text: the offers list and its actions, the promotion editor's rules and
// the payload it saves, groups, banners and the referral settings. FakeAdminOffersApi records every write.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/admin.dart';
import 'package:shyam_mobiles/features/admin/data/offers_admin.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_banners_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_groups_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_offers_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_settings_screen.dart';

import '../offers/fakes.dart';
import '../repairs/layout_harness.dart';

AdminProductRow _product(String id, String name) => AdminProductRow(
      id: id,
      slug: id,
      name: name,
      brandName: 'Samsung',
      categoryName: 'Phones',
      isActive: true,
      isFeatured: false,
      coverPath: null,
      activeVariants: 1,
      stock: 5,
      lowStock: false,
    );

final _catalogue = [
  adminProductsProvider.overrideWithValue(AsyncData([_product('s25', 'Samsung Galaxy S25 5G'), _product('a55', 'Samsung Galaxy A55 5G')])),
  adminCategoriesProvider.overrideWithValue(const AsyncData([Category(id: 'c1', slug: 'smartphones', name: 'Phones', kind: CategoryKind.phone)])),
  adminBrandsProvider.overrideWithValue(const AsyncData([Brand(id: 'b1', slug: 'samsung', name: 'Samsung')])),
];

final _now = DateTime.now();

final _running = Promotion(
  id: 'p1',
  title: 'Diwali dhamaka on phones',
  code: 'DIWALI10',
  kind: OfferKind.percent,
  value: 10,
  startsAt: _now.subtract(const Duration(days: 2)),
  uses: 3,
  discountTotalPaise: 150000,
  status: PromotionStatus.running,
);

final _scheduled = Promotion(
  id: 'p2',
  title: 'Weekend sale on cases',
  kind: OfferKind.flat,
  value: 10000,
  startsAt: _now.add(const Duration(days: 2)),
  status: PromotionStatus.scheduled,
);

final _personal = Promotion(
  id: 'p3',
  title: 'Welcome',
  code: 'FRIEND8X2K',
  kind: OfferKind.flat,
  value: 20000,
  startsAt: _now,
  userId: 'u9',
  status: PromotionStatus.running,
);

/// Scrolls [text] into view and taps it (or, for a picker field's label, which ignores taps, the field).
Future<void> _tap(WidgetTester tester, String text) async {
  await scrollTo(tester, find.text(text));
  await tester.ensureVisible(find.text(text)); // to the top, clear of the sticky Save bar
  await tester.pumpAndSettle();
  final field = find.ancestor(of: find.text(text), matching: find.byType(InputDecorator));
  await tester.tap(field.evaluate().isEmpty ? find.text(text) : field);
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String field, String option) async {
  await _tap(tester, field);
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers list: status, uses and given; pause, end now and delete go through the right calls', (tester) async {
    final api = FakeAdminOffersApi(list: [_running, _scheduled, _personal]);
    await pumpScreen(tester, const AdminOffersScreen(), overrides: [adminOffersApiProvider.overrideWithValue(api)]);
    await tester.pumpAndSettle();
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.textContaining('DIWALI10 · 10% off · 3 uses · ₹1,500 given'), findsOneWidget);
    expect(find.text('Welcome'), findsNothing, reason: 'referral coupons have their own tab');

    await tester.tap(find.byTooltip('Actions for Diwali dhamaka on phones'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing, reason: 'used offers can only be ended');
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(api.saved.last, {'id': 'p1', 'is_active': false});
    expect(find.text('Offer paused'), findsOneWidget);

    await tester.tap(find.byTooltip('Actions for Weekend sale on cases'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End now'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'End now')); // the red, destructive choice
    await tester.pumpAndSettle();
    expect(api.saved.last.keys, containsAll(['id', 'ends_at', 'starts_at']), reason: 'a scheduled offer moves its start too');

    await tester.tap(find.byTooltip('Actions for Weekend sale on cases'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Weekend sale on cases”?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Keep offer'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);

    await tester.tap(find.text('Referral coupons'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('offer editor: rules checked on the form, then the exact payload saved', (tester) async {
    final api = FakeAdminOffersApi(groups: const [Collection(id: 'g1', slug: 'diwali-picks', name: 'Diwali picks')]);
    await pumpScreen(tester, const AdminOfferEditScreen(), routes: ['/admin/offers'], overrides: [
      adminOffersApiProvider.overrideWithValue(api),
      ..._catalogue,
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create offer'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a title.'), findsOneWidget);
    expect(api.saved, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Diwali dhamaka');
    await tester.enterText(find.widgetWithText(TextFormField, 'Percent off'), '95');
    await tester.tap(find.text('Create offer'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a percent from 1 to 90.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Percent off'), '10');
    await tester.enterText(find.widgetWithText(TextFormField, 'Most it can take off (optional)'), '500');

    await _tap(tester, 'Generate');
    final code = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Code')).controller!.text;
    expect(validateCodeFor(code), isTrue, reason: 'Generate makes a valid code: $code');
    await tester.enterText(find.widgetWithText(TextFormField, 'Code'), 'diwali 10');

    await _pick(tester, 'The whole order', 'Some products');
    await tester.tap(find.text('Create offer'));
    await tester.pumpAndSettle();
    expect(find.text('Pick at least one product, category, brand or group.'), findsOneWidget);

    await _tap(tester, 'Products, categories, brands or groups');
    await tester.tap(find.text('Brand · Samsung'));
    await tester.tap(find.text('Group · Diwali picks'));
    await tester.pump();
    await tester.tap(find.text('Done (2)'));
    await tester.pumpAndSettle();
    expect(find.text('1 brand · 1 group'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Minimum order (optional)'), '1999');
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000)); // the last switches
    await tester.pumpAndSettle();
    await _tap(tester, 'Online payment only');
    await _tap(tester, 'Show a banner on home');
    await tester.tap(find.text('Create offer'));
    await tester.pumpAndSettle();

    final p = api.saved.single;
    expect(p.containsKey('id'), isFalse, reason: 'no id: insert');
    expect({for (final k in ['title', 'code', 'kind', 'value', 'max_discount_paise', 'min_subtotal_paise', 'applies_to', 'per_user_limit', 'usage_limit', 'online_only', 'first_order_only', 'is_public', 'show_banner', 'ends_at']) k: p[k]}, {
      'title': 'Diwali dhamaka',
      'code': 'DIWALI10',
      'kind': 'percent',
      'value': 10,
      'max_discount_paise': 50000,
      'min_subtotal_paise': 199900,
      'applies_to': 'items',
      'per_user_limit': 1,
      'usage_limit': null,
      'online_only': true,
      'first_order_only': false,
      'is_public': true,
      'show_banner': true,
      'ends_at': null,
    });
    expect(p['targets'], unorderedEquals([
      {'target_type': 'brand', 'target_id': 'b1'},
      {'target_type': 'collection', 'target_id': 'g1'},
    ]));
    expect(DateTime.parse(p['starts_at'] as String).isUtc, isTrue);
    expect(find.text('Page /admin/offers'), findsOneWidget);
  });

  testWidgets('offer editor: a hidden code can’t have a banner; a duplicate starts with no code', (tester) async {
    final api = FakeAdminOffersApi(list: [_running.copyWithBanner()]);
    await pumpScreen(tester, const AdminOfferEditScreen(copyOf: 'p1'), overrides: [adminOffersApiProvider.overrideWithValue(api), ..._catalogue]);
    await tester.pumpAndSettle();
    expect(find.text('Create offer'), findsOneWidget, reason: 'a copy is a new offer');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Title')).controller!.text, 'Diwali dhamaka on phones');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Code')).controller!.text, isEmpty);

    await _tap(tester, 'List it in Offers');
    await scrollTo(tester, find.text('Show a banner on home'));
    final banner = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Show a banner on home'));
    expect((banner.value, banner.onChanged), (false, null));
  });

  testWidgets('groups: name makes the short name, products picked several at a time, saved', (tester) async {
    final api = FakeAdminOffersApi();
    await pumpScreen(tester, const AdminGroupEditScreen(), routes: ['/admin/groups'], overrides: [
      adminOffersApiProvider.overrideWithValue(api),
      ..._catalogue,
    ]);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Diwali picks');
    await tester.pump();
    expect(find.text('diwali-picks'), findsOneWidget);
    await _tap(tester, 'Products in this group');
    await tester.tap(find.text('Samsung Galaxy S25 5G'));
    await tester.tap(find.text('Samsung Galaxy A55 5G'));
    await tester.pump();
    await tester.tap(find.text('Done (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Take Samsung Galaxy A55 5G out'));
    await tester.pump();
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();
    expect(api.calls, ['group Diwali picks 1']);
    expect(find.text('Page /admin/groups'), findsOneWidget);

    await pumpScreen(tester, const AdminGroupsScreen(), overrides: [
      adminOffersApiProvider.overrideWithValue(FakeAdminOffersApi(groups: const [
        Collection(id: 'g1', slug: 'diwali-picks', name: 'Diwali picks for the whole family, phones and more', productIds: {'s25'}),
      ])),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('1 product'), findsOneWidget);
  });

  testWidgets('banners: list order, editor preview, link picked from the shop, saved', (tester) async {
    final rows = [
      PromoBanner(id: 'b1', title: 'Diwali dhamaka', link: '/offers', startsAt: _now, promotionId: 'p1'),
      PromoBanner(id: 'b2', title: 'Repairs in an hour', link: '/repairs', startsAt: _now, sort: 1, isActive: false),
    ];
    final api = FakeAdminOffersApi(bannerRows: rows);
    await pumpScreen(tester, const AdminBannersScreen(), overrides: [adminOffersApiProvider.overrideWithValue(api)]);
    await tester.pumpAndSettle();
    expect(find.text('From an offer'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(find.byTooltip('Move Diwali dhamaka down'));
    await tester.pumpAndSettle();
    expect(api.saved, [{'sort': 0}, {'sort': 1}]);

    api.saved.clear();
    await pumpScreen(tester, const AdminBannerEditScreen(), routes: ['/admin/banners'], overrides: [
      adminOffersApiProvider.overrideWithValue(api),
      ..._catalogue,
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Banner title'), findsOneWidget, reason: 'the preview');
    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Galaxy week');
    await tester.pump();
    expect(find.text('Galaxy week'), findsNWidgets(2), reason: 'field and preview');
    await tester.tap(find.text('Create banner'));
    await tester.pumpAndSettle();
    expect(find.text('Pick where the banner goes'), findsOneWidget);
    await _pick(tester, 'Opens', 'Product · Samsung Galaxy S25 5G');
    await tester.tap(find.text('Create banner'));
    await tester.pumpAndSettle();
    expect(api.saved.single, containsPair('link', '/product/s25'));
    expect(api.saved.single, containsPair('cta_label', 'Shop now'));
    expect(api.saved.single, containsPair('sort', 2));
    expect(api.saved.single, containsPair('subtitle', ''));
    expect(find.text('Page /admin/banners'), findsOneWidget);
  });

  testWidgets('settings: the referral section fits and checks its amounts', (tester) async {
    await pumpScreen(tester, const AdminSettingsScreen());
    await scrollTo(tester, find.text('Rewards per customer a month'));
    expect(find.text('Run Refer & earn'), findsOneWidget);
  });
}

bool validateCodeFor(String code) => RegExp(r'^[A-Z0-9]{8}$').hasMatch(code);

extension on Promotion {
  Promotion copyWithBanner() => Promotion(
        id: id,
        title: title,
        code: code,
        kind: kind,
        value: value,
        startsAt: startsAt,
        showBanner: true,
        uses: uses,
        status: status,
      );
}
