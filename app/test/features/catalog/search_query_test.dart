import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shyam_mobiles/features/catalog/data/catalog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Runs [searchQuery] against a fake PostgREST and returns the request's query parameters.
Future<Map<String, String>> paramsFor(SearchParams p, {int offset = 0}) async {
  late Uri url;
  final client = PostgrestClient(
    'http://localhost/rest/v1',
    httpClient: MockClient((req) async {
      url = req.url;
      return http.Response('[]', 200, request: req, headers: {'content-type': 'application/json'});
    }),
  );
  await searchQuery(client.from('product_cards'), p, offset: offset);
  return url.queryParameters;
}

SearchParams params({String q = '', String? category, String? brand, int? max, SearchSort sort = SearchSort.relevance}) =>
    (q: q, category: category, brand: brand, maxPricePaise: max, sort: sort);

void main() {
  test('sort param round-trips and unknown values fall back to relevance', () {
    for (final s in SearchSort.values) {
      expect(SearchSort.parse(s.param), s);
    }
    expect(SearchSort.parse('price_asc'), SearchSort.priceAsc);
    expect(SearchSort.parse(null), SearchSort.relevance);
    expect(SearchSort.parse('cheapest'), SearchSort.relevance);
  });

  test('no filters: card columns, relevance order, first page of 20', () async {
    final qp = await paramsFor(params());
    expect(qp['select'], cardColumns.replaceAll(' ', ''));
    expect(qp.containsKey('search'), isFalse);
    expect(qp['order'], 'is_featured.desc.nullslast,name.asc.nullslast,id.asc.nullslast');
    expect(qp['offset'], '0');
    expect(qp['limit'], '20');
  });

  test('query and filters map to prefix full-text search + eq/lte filters', () async {
    final qp = await paramsFor(
      params(q: '5g phone', category: 'smartphones', brand: 'samsung', max: 3000000, sort: SearchSort.priceAsc),
      offset: 40,
    );
    expect(qp['search'], 'fts(simple).5g:* & phone:*');
    expect(qp['category_slug'], 'eq.smartphones');
    expect(qp['brand_slug'], 'eq.samsung');
    expect(qp['min_price_paise'], 'lte.3000000');
    expect(qp['order'], 'min_price_paise.asc.nullslast,id.asc.nullslast');
    expect(qp['offset'], '40');
    expect(qp['limit'], '20');
  });

  test('each sort maps to its order, always ending on id', () async {
    expect((await paramsFor(params(sort: SearchSort.newest)))['order'], 'created_at.desc.nullslast,id.asc.nullslast');
    expect(
      (await paramsFor(params(sort: SearchSort.priceDesc)))['order'],
      'min_price_paise.desc.nullslast,id.asc.nullslast',
    );
  });

  test('prefix query: partial words match, tsquery syntax is stripped', () {
    expect(prefixTsQuery('sams'), 'sams:*');
    expect(prefixTsQuery('  Galaxy S25! '), 'galaxy:* & s25:*');
    expect(prefixTsQuery('a & (b | !c):'), 'a:* & b:* & c:*');
    expect(prefixTsQuery(' !&| '), isNull);
  });
}
