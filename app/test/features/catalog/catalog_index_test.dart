import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/catalog_admin_repository_firebase.dart';
import 'package:shyam_mobiles/features/admin/data/catalogue.dart';
import 'package:shyam_mobiles/features/admin/data/rules.dart' show gstinError;
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog_index.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog_repository_firebase.dart' show variantFromDoc;

// The Firebase build's on-phone search over catalogIndex/public and the staff catalogue over catalogIndex/staff
// (same results as product_cards and admin_catalogue), plus the doc ↔ model mapping.
Map<String, dynamic> card(String name, {String c = 'smartphones', String k = 'phone', int p = 100000, bool i = true, bool f = false, int t = 0, List<String>? ft}) => {
      'n': name, 's': name.toLowerCase().replaceAll(' ', '-'), 'b': name.split(' ').first.toLowerCase(), 'bn': name.split(' ').first,
      'c': c, 'k': k, 'v': '8 GB · 128 GB', 'p': p, 'm': p, 'i': i, 'f': f, 'cv': null, 'col': <String>[], 't': t, 'ft': ?ft,
    };

final IndexCards cards = {
  's25': card('Samsung Galaxy S25', p: 7499900, f: true, t: 3),
  'a56': card('Samsung Galaxy A56', p: 3899900, i: false, t: 2),
  'iph': card('Apple iPhone 16', p: 6990000, f: true, t: 1),
  'case': card('Spigen Case', c: 'cases-covers', k: 'accessory', p: 129900, f: true, t: 4, ft: ['iPhone 16']),
  'buds': card('boAt Airdopes', c: 'earbuds-headphones', k: 'accessory', p: 109900, t: 5),
  'pb': card('Anker Powerbank', c: 'power-banks', k: 'accessory', p: 199900, t: 6),
};

SearchParams params({String q = '', String? category, bool inStock = false, SearchSort sort = SearchSort.relevance}) =>
    (q: q, category: category, brand: null, minPricePaise: null, maxPricePaise: null, inStock: inStock, sort: sort);

void main() {
  test('search: every typed word starts a word; in stock first, then the sort, then id', () {
    expect([for (final c in searchCards(cards, params(q: 'sams gal'))) c.id], ['s25', 'a56']);
    expect([for (final c in searchCards(cards, params(q: 'galaxy 8'))) c.id], ['s25', 'a56'], reason: 'variant names count');
    expect(searchCards(cards, params(q: 'alaxy')), isEmpty, reason: 'prefixes only');
    expect([for (final c in searchCards(cards, params(sort: SearchSort.priceAsc, category: 'smartphones'))) c.id], ['iph', 's25', 'a56']);
    expect([for (final c in searchCards(cards, params(sort: SearchSort.newest))) c.id].first, 'pb');
    expect(searchCards(cards, params(inStock: true)).any((c) => c.id == 'a56'), isFalse);
    expect(words('सैमसंग फ़ोन!'), ['सैमसंग', 'फ़ोन']);
  });

  test('home, fits and latest', () {
    final h = homeCards(cards);
    expect([for (final c in h.featured) c.id], ['s25', 'iph', 'case'], reason: 'phones first, newest first');
    expect([for (final c in h.accessories) c.id], ['buds', 'case'], reason: 'in stock, ≤ ₹1,500, cheapest first');
    expect([for (final c in fitsCards(cards, {'iPhone 16'}, 8)) c.id], ['case']);
    expect(latestCards(cards, 2).map((c) => c.id), ['pb', 'buds']);
    expect(cardOf('s25', cards['s25']!).toJson()['min_price_paise'], 7499900);
  });

  test('a variant doc maps colorHex to the model key', () {
    final v = variantFromDoc('v1', {
      'productId': 's25', 'sku': 'S', 'name': 'Navy', 'attributes': {'color': 'Navy', 'colorHex': '#2C3646'},
      'pricePaise': 100, 'mrpPaise': 200, 'stock': 3, 'isActive': true, 'sort': 1,
    });
    expect((v.colorHex, v.color, v.inStock), ('#2C3646', 'Navy', true));
    expect(variantInput('s25', null, {'attributes': {'color_hex': '#FFFFFF'}, 'sku': 'S'})['attributes'], {'colorHex': '#FFFFFF'});
    expect(productInput(null, {'slug': 'x', 'gst_rate': 12.5})['gstRateBp'], 1250);
  });

  test('staff catalogue: search, filters, sort, totals (admin_catalogue rules)', () {
    final staff = staffRows({
      's25': {...card('Samsung Galaxy S25'), 'active': true, 'u': 10, 'variants': [
        {'id': 'v1', 'sku': 'SAM-1', 'n': 'Navy', 'p': 100, 'm': 150, 'st': 2, 'a': true, 'u': 20},
        {'id': 'v2', 'sku': 'SAM-2', 'n': 'Blue', 'p': 200, 'm': 250, 'st': 0, 'a': false, 'u': 5},
      ]},
      'iph': {...card('Apple iPhone 16'), 'active': false, 'u': 30, 'variants': [
        {'id': 'v3', 'sku': 'APL-1', 'n': 'Black', 'p': 300, 'm': 300, 'st': 9, 'a': true, 'u': 1},
      ]},
    });
    const all = allRows;
    final page = cataloguePage(staff, all, offset: 0, limit: 50);
    expect([for (final r in page.rows) r.variantId], ['v3', 'v2', 'v1'], reason: 'by product name, then variant name');
    expect(page.summary, (skus: 3, units: 11, valueAtPricePaise: 2900, valueAtMrpPaise: 3000, low: 1, out: 1, total: 3));
    expect(page.rows.first.updatedAt.millisecondsSinceEpoch, 30, reason: 'the later of variant and product');
    CatalogueView v({String query = '', StockFilter stock = StockFilter.all, VisibilityFilter vis = VisibilityFilter.all, CatalogueSort sort = CatalogueSort.name}) =>
        (query: query, categoryId: null, brandId: null, stock: stock, visibility: vis, sort: sort);
    expect([for (final r in cataloguePage(staff, v(query: 'sam-2'), offset: 0, limit: 9).rows) r.variantId], ['v2']);
    expect([for (final r in cataloguePage(staff, v(vis: VisibilityFilter.shown), offset: 0, limit: 9).rows) r.variantId], ['v1']);
    expect([for (final r in cataloguePage(staff, v(stock: StockFilter.low), offset: 0, limit: 9).rows) r.variantId], ['v1']);
    expect([for (final r in cataloguePage(staff, v(sort: CatalogueSort.stock), offset: 1, limit: 1).rows) r.variantId], ['v1']);
  });

  test('GSTIN: shape and check character', () {
    expect(gstinError('23BXEPG0619P2ZG'), isNull, reason: 'the shop’s own');
    expect(gstinError('23BXEPG0619P2ZH'), contains('doesn’t check out'));
    expect(gstinError('23bxepg0619p2zg'), contains('15-character'));
    expect(gstinError('BXEPG0619P'), contains('15-character'), reason: 'a PAN is not a GSTIN');
  });

  test('a card keeps its kind for Category round trips', () {
    const c = Category(id: 'smartphones', slug: 'smartphones', name: 'Smartphones', kind: CategoryKind.phone);
    expect(Category.fromJson(c.toJson()).kind, CategoryKind.phone);
  });
}
