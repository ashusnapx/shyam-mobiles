import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/wishlist/data/wishlist.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeWishlistApi implements WishlistApi {
  Set<String> ids = {'a'};
  final calls = <String>[];
  final pending = <String, Completer<void>>{}; // writes held open by the test

  Future<void> _write(String call, String productId) {
    calls.add(call);
    return (pending[productId] = Completer<void>()).future;
  }

  @override
  Future<Set<String>> productIds() async => {...ids};
  @override
  Future<void> add(String userId, String productId) => _write('add $userId $productId', productId);
  @override
  Future<void> remove(String userId, String productId) => _write('remove $userId $productId', productId);
}

void main() {
  late FakeWishlistApi api;
  late ProviderContainer container;

  ProviderContainer make(String? userId) {
    final c = ProviderContainer(overrides: [
      wishlistApiProvider.overrideWithValue(api),
      currentUserIdProvider.overrideWithValue(userId),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Set<String>? ids() => container.read(wishlistProvider).value;

  setUp(() => api = FakeWishlistApi());

  test('add shows at once and sticks when the write succeeds', () async {
    container = make('u1');
    await container.read(wishlistProvider.future);
    final done = container.read(wishlistProvider.notifier).toggle('b');
    expect(ids(), {'a', 'b'});
    api.pending['b']!.complete();
    await done;
    expect(ids(), {'a', 'b'});
    expect(api.calls, ['add u1 b']);
  });

  test('a failed remove rolls the heart back and rethrows', () async {
    container = make('u1');
    await container.read(wishlistProvider.future);
    final done = container.read(wishlistProvider.notifier).toggle('a');
    expect(ids(), isEmpty);
    api.pending['a']!.completeError(const PostgrestException(message: 'boom'));
    await expectLater(done, throwsA(isA<PostgrestException>()));
    expect(ids(), {'a'});
  });

  test('rollback only reverts the failed product, not other toggles in flight', () async {
    container = make('u1');
    await container.read(wishlistProvider.future);
    final notifier = container.read(wishlistProvider.notifier);
    final failing = notifier.toggle('b');
    final ok = notifier.toggle('c');
    expect(ids(), {'a', 'b', 'c'});
    api.pending['c']!.complete();
    api.pending['b']!.completeError(Exception('offline'));
    await ok;
    await expectLater(failing, throwsException);
    expect(ids(), {'a', 'c'});
  });

  test('signed out: empty set and toggle refuses without writing', () async {
    container = make(null);
    expect(await container.read(wishlistProvider.future), isEmpty);
    await expectLater(container.read(wishlistProvider.notifier).toggle('a'), throwsA(isA<AuthException>()));
    expect(api.calls, isEmpty);
  });
}
