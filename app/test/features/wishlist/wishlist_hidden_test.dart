// Saved products the shop has hidden: the wishlist pages past them, says some were dropped, and never claims
// "Nothing saved" while later pages have items. And the cart says once when it dropped a hidden item. Fake HTTP.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/wishlist/data/wishlist.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

http.Response _json(Object body, http.Request r) =>
    http.Response(jsonEncode(body), 200, request: r, headers: {'content-type': 'application/json'});

Map<String, dynamic> _card(String id) => {
      'id': id, 'slug': id, 'name': 'Phone $id', 'is_featured': false, 'category_slug': 'smartphones',
      'brand_name': 'Samsung', 'min_price_paise': 999900, 'mrp_paise': 999900, 'in_stock': true, 'cover_path': null,
    };

class _Ids extends WishlistNotifier {
  _Ids(this.ids);

  final Set<String> ids;

  @override
  Future<Set<String>> build() async => ids;
}

ProviderContainer _container(Future<http.Response> Function(http.Request) handler, {Set<String> ids = const {}}) {
  final db = SupabaseClient('http://localhost', 'sb_publishable_test',
      httpClient: MockClient(handler), authOptions: const AuthClientOptions(autoRefreshToken: false));
  final c = ProviderContainer(retry: noAutoRetry, overrides: [
    supabaseProvider.overrideWithValue(db),
    currentUserIdProvider.overrideWithValue('u1'),
    wishlistProvider.overrideWith(() => _Ids(ids)),
  ]);
  addTearDown(() async {
    c.dispose();
    await db.dispose();
  });
  return c;
}

void main() {
  test('wishlist: a page of only hidden products moves on; dropped ones are counted', () async {
    // 70 saved: the first 30 are all hidden, then every other one is sold
    final ids = {for (var i = 0; i < 70; i++) 'p$i'};
    var asks = 0;
    final c = _container((r) async {
      asks++;
      final wanted = [
        for (final v in RegExp(r'in\.\(([^)]*)\)').firstMatch(Uri.decodeComponent(r.url.query))![1]!.split(','))
          v.replaceAll('"', ''),
      ];
      return _json([for (final id in wanted) if (int.parse(id.substring(1)) >= 30 && int.parse(id.substring(1)).isEven) _card(id)], r);
    }, ids: ids);
    c.listen(wishlistCardsProvider, (_, _) {});
    final first = await c.read(wishlistCardsProvider.future);
    expect(first.items.map((c) => c.id), [for (var i = 30; i < 60; i += 2) 'p$i'], reason: 'skipped straight past page 1');
    expect((asks, first.hasMore), (2, true));
    expect(c.read(wishlistCardsProvider.notifier).dropped, 45);
    await c.read(wishlistCardsProvider.notifier).loadMore();
    final all = c.read(wishlistCardsProvider).value!;
    expect((all.items.length, all.hasMore), (20, false));
    expect(c.read(wishlistCardsProvider.notifier).dropped, 50);
  });

  test('wishlist: everything hidden ends with an empty list, not more pages', () async {
    final c = _container((r) async => _json(<Object>[], r), ids: {for (var i = 0; i < 40; i++) 'p$i'});
    c.listen(wishlistCardsProvider, (_, _) {});
    final page = await c.read(wishlistCardsProvider.future);
    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
    expect(c.read(wishlistCardsProvider.notifier).dropped, 40);
  });

  test('cart: a line the shop hid is dropped and named once', () async {
    var hidden = false;
    final deletes = <String>[];
    final c = _container((r) async {
      if (r.method == 'DELETE') {
        deletes.add(r.url.query);
        return http.Response('', 204, request: r);
      }
      return _json([
        {
          'qty': 1,
          'variant_id': 'v1',
          'variant': hidden
              ? null
              : {
                  'id': 'v1', 'product_id': 'p1', 'sku': 'S', 'name': '8 GB', 'attributes': <String, dynamic>{},
                  'price_paise': 999900, 'mrp_paise': 999900, 'stock': 5, 'is_active': true, 'sort': 0,
                  'product': {'id': 'p1', 'slug': 'a15', 'name': 'Galaxy A15', 'is_active': true, 'images': <Object>[]},
                },
        },
      ], r);
    });
    c.listen(cartProvider, (_, _) {});
    await c.read(cartProvider.future);
    expect(c.read(cartProvider.notifier).takeRemoved(), isEmpty);
    hidden = true;
    c.invalidate(cartProvider);
    expect(await c.read(cartProvider.future), isEmpty);
    expect(deletes.single, contains('v1'));
    final names = c.read(cartProvider.notifier).takeRemoved();
    expect(removedNotice(names), 'Galaxy A15 is no longer available and was removed from your cart.');
    expect(c.read(cartProvider.notifier).takeRemoved(), isEmpty, reason: 'said once');
  });

  test('cart notice wording', () {
    expect(removedNotice([null]), 'An item in your cart is no longer available and was removed.');
    expect(removedNotice([null, null]), '2 items in your cart are no longer available and were removed.');
    expect(removedNotice(['A15', 'Note 14']), 'A15 and Note 14 are no longer available and were removed from your cart.');
    expect(removedNotice(['A15', null]), 'A15 (and 1 more) are no longer available and were removed from your cart.');
  });
}
