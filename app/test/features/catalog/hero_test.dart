import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/network.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/core/widgets/widgets.dart';
import 'package:shyam_mobiles/features/catalog/data/hero.dart';

ProductCard _card(String id, int price, int mrp, {bool inStock = true}) => ProductCard(
    id: id, slug: id, name: id, brandName: 'B', categorySlug: 'smartphones', minPricePaise: price, mrpPaise: mrp, inStock: inStock);

void main() {
  final now = DateTime.utc(2026, 11, 19, 6); // 11:30 in Waidhan

  test('deal of the day: the biggest real discounts in stock, one a day in turn', () {
    final cards = [
      _card('a', 9000, 10000), // 10%
      _card('b', 5000, 10000), // 50%
      _card('c', 7000, 10000), // 30%
      _card('d', 1000, 10000, inStock: false), // 90% but sold out
      _card('e', 10000, 10000), // no discount
    ];
    final picks = {for (var i = 0; i < 3; i++) dealOfTheDay(cards, now.add(Duration(days: i)))!.id};
    expect(picks, {'a', 'b', 'c'}, reason: 'rotates through every real deal');
    expect(dealOfTheDay(cards, now)!.id, dealOfTheDay(cards, now.add(const Duration(hours: 12)))!.id,
        reason: 'one pick for the whole IST day');
    expect(dealOfTheDay([_card('e', 10000, 10000)], now), isNull);
  });

  test('the deal ends at the next midnight in Waidhan', () {
    expect(istMidnightAfter(now), DateTime.utc(2026, 11, 19, 18, 30));
    expect(istMidnightAfter(DateTime.utc(2026, 11, 19, 19)), DateTime.utc(2026, 11, 20, 18, 30));
  });

  test('automatic slides: only the ones on, never the deal twice, nothing untrue', () {
    final cards = [_card('b', 5000, 10000)];
    final newest = [_card('b', 5000, 10000), _card('n', 2000, 2000)];
    final all = autoSlides(const ['deal', 'newest', 'exchange'], cards: cards, newest: newest, now: now);
    expect([for (final s in all) s.kind], [AutoBanner.deal, AutoBanner.newest, AutoBanner.exchange]);
    expect(all[1].card!.id, 'n', reason: 'the deal is not repeated as New');
    expect(all.first.endsAt, istMidnightAfter(now));
    expect(autoSlides(const ['repairs'], cards: cards, newest: newest, now: now).single.kind, AutoBanner.repairs);
    expect(autoSlides(const [], cards: cards, newest: newest, now: now), isEmpty);
    expect(autoSlides(const ['deal', 'newest'], cards: const [], newest: const [], now: now), isEmpty);
  });

  test('banner facts: saving, real low stock from 3 down, rating from 3 reviews', () {
    final c = _card('p', 7499900, 7999900);
    expect(slideFacts(c).savePaise, 500000);
    expect(slideFacts(c, stock: 3).left, 3);
    expect(slideFacts(c, stock: 1).left, 1);
    expect(slideFacts(c, stock: 4).left, isNull);
    expect(slideFacts(c, stock: 0).left, isNull, reason: 'sold out is not "only 0 left"');
    expect(slideFacts(c).left, isNull, reason: 'unknown stock says nothing');
    expect(slideFacts(c, ratingCount: 2, ratingSum: 10).rating, isNull);
    expect(slideFacts(c, ratingCount: 3, ratingSum: 13).rating, '4.3');
    expect(slideFacts(_card('q', 100, 100)).savePaise, 0);
  });

  test('cut-out key: beside the photo, any extension', () {
    expect(cutPathFor('p1/1730000000000.webp'), 'p1/1730000000000@cut.webp');
    expect(cutPathFor('store/1.jpg'), 'store/1@cut.webp');
  });

  testWidgets('no cut-out to load (no photo, or data saver): the photo in a soft tile instead', (tester) async {
    Future<void> pump(String? path, DataMode mode) => tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [dataSaverProvider.overrideWithValue(mode)],
          child: MaterialApp(home: Scaffold(body: SizedBox(width: 160, height: 160, child: ProductCutout(path)))),
        ));
    await pump(null, DataMode.full);
    expect(find.byType(ProductImage), findsOneWidget);
    await pump('p1/1.webp', DataMode.saver);
    expect(find.byType(ProductImage), findsOneWidget);
    await pump('p1/1.webp', DataMode.full);
    expect(find.byType(ProductImage), findsNothing, reason: 'the cut-out loads first; its errorWidget is the tile');
  });

  test('the fan: offers show phones, packs phone + guard + case, exchange the newest and an older phone at 70%', () {
    ProductCard p(String id, String slug) => ProductCard(
        id: id, slug: id, name: id, brandName: 'B', categorySlug: slug, minPricePaise: 100, mrpPaise: 100, inStock: true, coverPath: '$id/1.webp');
    final pool = [p('new', 'smartphones'), p('guard', 'screen-guards'), p('mid', 'smartphones'), p('case', 'cases-covers'), p('old', 'smartphones')];
    expect([for (final i in heroFan(HeroFan.offer, pool)) i.path], ['new/1.webp', 'mid/1.webp', 'old/1.webp']);
    expect([for (final i in heroFan(HeroFan.pack, pool)) i.path], ['new/1.webp', 'guard/1.webp', 'case/1.webp']);
    expect([for (final i in heroFan(HeroFan.exchange, pool)) (i.path, i.opacity)], [('new/1.webp', 1.0), ('old/1.webp', 0.7)]);
    expect(heroFan(HeroFan.none, pool), isEmpty);
    expect(heroFan(HeroFan.pack, [p('g', 'screen-guards')]), isEmpty, reason: 'a pack needs its phone');
    expect(heroFan(HeroFan.offer, [_card('x', 100, 100, inStock: false)]), isEmpty, reason: 'sold out or no photo: never shown');
  });

  test('labels: two-word buttons, spoken time left, one slide label', () {
    expect(heroCta('Get an estimate'), 'Get estimate');
    expect(heroCta('Book a repair'), 'Book repair');
    expect(heroCta('Shop now'), 'Shop now');
    expect(heroCta('  '), 'Shop now');
    final t = DateTime(2026, 11, 19, 10);
    expect(spokenLeft(t.add(const Duration(days: 10, hours: 7)), now: t), 'ends in 10 days');
    expect(spokenLeft(t.add(const Duration(hours: 1, minutes: 5)), now: t), 'ends in 1 hour');
    expect(spokenLeft(t.add(const Duration(minutes: 9)), now: t), 'ends in 9 minutes');
    expect(spokenLeft(t, now: t), isNull);
    expect(heroLabel('Offer', 'Festive phone sale', 'Shop now', endsAt: t.add(const Duration(days: 10, hours: 7)), now: t),
        'Offer: Festive phone sale, ends in 10 days, Shop now');
  });
}
