// Cart and orders notifiers against a fake Supabase HTTP backend.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/account/data/addresses.dart';
import 'package:shyam_mobiles/features/cart/data/cart.dart';
import 'package:shyam_mobiles/features/orders/data/orders.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

http.Response _json(Object body, http.Request r) =>
    http.Response(jsonEncode(body), 200, request: r, headers: {'content-type': 'application/json'});

Map<String, dynamic> _cartRow(int qty) => {
      'qty': qty,
      'variant': {
        'id': 'v1', 'product_id': 'p1', 'sku': 'S', 'name': '8 GB · 128 GB', 'attributes': <String, dynamic>{},
        'price_paise': 1299900, 'mrp_paise': 1299900, 'stock': 5, 'is_active': true, 'sort': 0,
        'product': {'id': 'p1', 'slug': 'phone', 'name': 'Phone', 'is_active': true, 'images': <Object>[]},
      },
    };

Map<String, dynamic> _orderRow(int i) => {
      'id': 'o$i', 'number': 'SM${100000 + i}', 'user_id': 'u1', 'status': 'delivered', 'payment_method': 'cod',
      'payment_status': 'paid', 'subtotal_paise': 100, 'delivery_fee_paise': 0, 'total_paise': 100,
      'address': {'name': 'A', 'phone': '+919876543210', 'line1': 'x', 'city': 'Gaya', 'state': 'Bihar', 'pincode': '823001'},
      'created_at': '2026-10-29T10:00:00Z', 'items': <Object>[],
    };

({ProviderContainer container, SupabaseClient db}) _setup(Future<http.Response> Function(http.Request) handler) {
  final db = SupabaseClient(
    'http://localhost',
    'sb_publishable_test',
    httpClient: MockClient(handler),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final container = ProviderContainer(retry: noAutoRetry, overrides: [
    supabaseProvider.overrideWithValue(db),
    currentUserIdProvider.overrideWithValue('u1'),
  ]);
  return (container: container, db: db);
}

void main() {
  test('a line whose item the shop hid is dropped, not a broken cart', () async {
    final deletes = <String>[];
    final s = _setup((r) async {
      if (r.method == 'DELETE') {
        deletes.add(r.url.query);
        return http.Response('', 204, request: r);
      }
      // RLS hides an inactive variant from customers, so its line comes back without one
      return _json([_cartRow(1), {'qty': 2, 'variant_id': 'v9', 'variant': null}], r);
    });
    final lines = await s.container.read(cartProvider.future);
    expect([for (final l in lines) l.variant.id], ['v1']);
    expect(Uri.decodeQueryComponent(deletes.single), 'variant_id=in.("v9")');
  });

  test('quantity taps reach the server one at a time, in tap order', () async {
    final patches = <int>[];
    final gates = <Completer<void>>[];
    final s = _setup((r) async {
      if (r.method == 'GET') return _json([_cartRow(1)], r);
      patches.add((jsonDecode(r.body) as Map)['qty'] as int);
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      return http.Response('', 204, request: r);
    });
    addTearDown(() async {
      s.container.dispose();
      await s.db.dispose();
    });
    final cart = s.container.read(cartProvider.notifier);
    await s.container.read(cartProvider.future);

    final first = cart.setQty('v1', 2);
    final second = cart.setQty('v1', 3);
    expect(s.container.read(cartProvider).value!.single.qty, 3); // optimistic, right away
    await pumpEventQueue();
    expect(patches, [2], reason: 'the second write waits for the first');

    gates.single.complete();
    await first;
    await pumpEventQueue();
    expect(patches, [2, 3]);
    gates.last.complete();
    await second;
    expect(s.container.read(cartProvider).value!.single.qty, 3);
  });

  test('a failed write rolls back and does not block the next one', () async {
    var fail = true;
    final s = _setup((r) async {
      if (r.method == 'GET') return _json([_cartRow(1)], r);
      if (fail) {
        fail = false;
        return http.Response('{"message":"boom","code":"XX000"}', 500, request: r, headers: {'content-type': 'application/json'});
      }
      return http.Response('', 204, request: r);
    });
    addTearDown(() async {
      s.container.dispose();
      await s.db.dispose();
    });
    final cart = s.container.read(cartProvider.notifier);
    await s.container.read(cartProvider.future);

    await expectLater(cart.setQty('v1', 2), throwsA(isA<PostgrestException>()));
    expect(s.container.read(cartProvider).value!.single.qty, 1);
    await cart.setQty('v1', 4);
    expect(s.container.read(cartProvider).value!.single.qty, 4);
  });

  test('orders: a failed next page shows a retry instead of an endless spinner', () async {
    var failNext = true;
    final ranges = <String?>[];
    final s = _setup((r) async {
      final from = int.parse((r.headers['Range'] ?? r.url.queryParameters['offset'] ?? '0-').split('-').first);
      ranges.add(r.headers['Range'] ?? r.url.queryParameters['offset']);
      if (from > 0 && failNext) {
        failNext = false;
        // 400: not retried by postgrest, so the test needn't wait out its back-off
        return http.Response('{"message":"bad","code":"PGRST100"}', 400, request: r, headers: {'content-type': 'application/json'});
      }
      return _json([for (var i = from; i < from + (from == 0 ? ordersPageSize : 3); i++) _orderRow(i)], r);
    });
    final sub = s.container.listen(ordersProvider, (_, _) {});
    addTearDown(() async {
      sub.close();
      s.container.dispose();
      await s.db.dispose();
    });
    final first = await s.container.read(ordersProvider.future);
    expect((first.items.length, first.hasMore, first.moreFailed), (ordersPageSize, true, false));

    final notifier = s.container.read(ordersProvider.notifier);
    await notifier.loadMore(); // fails: no throw, the list stays and paging pauses
    var page = s.container.read(ordersProvider).value!;
    expect((page.items.length, page.hasMore, page.moreFailed), (ordersPageSize, true, true));

    final calls = ranges.length;
    await notifier.loadMore(); // scrolling doesn't hammer the server while failed
    expect(ranges.length, calls);

    await notifier.loadMore(retry: true);
    page = s.container.read(ordersProvider).value!;
    expect((page.items.length, page.hasMore, page.moreFailed), (ordersPageSize + 3, false, false));
  });

  test('address: a saved row is returned even when the list reload fails (no duplicate on a second tap)', () async {
    var gets = 0;
    final s = _setup((r) async {
      if (r.method == 'POST') return _json({...(jsonDecode(r.body) as Map), 'id': 'a1'}, r);
      // 400: not retried by postgrest
      return ++gets == 1
          ? _json(<Object>[], r)
          : http.Response('{"message":"bad","code":"PGRST100"}', 400, request: r, headers: {'content-type': 'application/json'});
    });
    final sub = s.container.listen(addressesProvider, (_, _) {}); // the screens watch it
    addTearDown(() async {
      sub.close();
      s.container.dispose();
      await s.db.dispose();
    });
    await s.container.read(addressesProvider.future);
    final saved = await s.container.read(addressesProvider.notifier).save(const Address(
          name: 'Rahul Kumar', phone: '+919876543210', line1: 'House 14', city: 'Gaya', state: 'Bihar', pincode: '823001'));
    expect(saved.id, 'a1');
    // the list shows its own error and "Try again" right away: no automatic retries keeping it loading
    final list = s.container.read(addressesProvider);
    expect((list.hasError, list.isLoading), (true, false));
  });
}
