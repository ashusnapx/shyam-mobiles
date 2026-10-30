// The shared infinite-scroll notifier (lib/core/paging.dart): page offsets, repeats, short pages and retries.
// Orders' own failure/retry test is in test/features/cart/cart_writes_test.dart.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/paging.dart';
import 'package:shyam_mobiles/core/supabase.dart';

/// Rows "r0", "r1"… from [rows]; [shiftAfterFirst] puts a new row at the top once page 1 is out, like a fresh order.
class _Rows extends PagedNotifier<String> {
  _Rows(this.rows, {this.shiftAfterFirst = false, this.dropEvery});

  List<String> rows;
  final bool shiftAfterFirst;
  final int? dropEvery; // a row the server leaves out (an inactive product), so pages come back short
  final asked = <int>[];

  @override
  int get pageSize => 3;

  @override
  Object idOf(String r) => r;

  @override
  bool hasMoreAfter(int from, List<String> got) => dropEvery == null ? super.hasMoreAfter(from, got) : from + pageSize < rows.length;

  @override
  Future<List<String>> fetch(int from, int size) async {
    asked.add(from);
    final page = rows.skip(from).take(size).toList();
    if (from == 0 && shiftAfterFirst) rows = ['new', ...rows];
    return [for (final (i, r) in page.indexed) if (dropEvery == null || (from + i) % dropEvery! != 0) r];
  }
}

Future<(ProviderContainer, _Rows)> _start(_Rows n) async {
  final provider = AsyncNotifierProvider<_Rows, Paged<String>>(() => n);
  final c = ProviderContainer(retry: noAutoRetry);
  addTearDown(c.dispose);
  c.listen(provider, (_, _) {});
  await c.read(provider.future);
  return (c, n);
}

void main() {
  test('pages follow on by page size; a row repeated by a shift shows once', () async {
    final (_, n) = await _start(_Rows([for (var i = 0; i < 7; i++) 'r$i'], shiftAfterFirst: true));
    await n.loadMore();
    await n.loadMore();
    expect(n.asked, [0, 3, 6]);
    final page = n.state.value!;
    expect(page.items, ['r0', 'r1', 'r2', 'r3', 'r4', 'r5', 'r6'], reason: 'r2 came again on page 2 and was dropped');
    expect(page.hasMore, isFalse);
    await n.loadMore();
    expect(n.asked, hasLength(3), reason: 'nothing more to ask for');
  });

  test('short pages (rows the server leaves out) still end, without asking forever', () async {
    final (_, n) = await _start(_Rows([for (var i = 0; i < 8; i++) 'r$i'], dropEvery: 2));
    for (var i = 0; i < 5; i++) {
      await n.loadMore();
    }
    expect(n.asked, [0, 3, 6]);
    expect(n.state.value!.items, ['r1', 'r3', 'r5', 'r7']);
    expect(n.state.value!.hasMore, isFalse);
  });

  test('replaceItems edits loaded rows and keeps the paging', () async {
    final (_, n) = await _start(_Rows([for (var i = 0; i < 5; i++) 'r$i']));
    n.replaceItems((items) => [for (final r in items) r == 'r1' ? 'R1' : r]);
    expect(n.state.value!.items, ['r0', 'R1', 'r2']);
    expect(n.state.value!.hasMore, isTrue);
  });
}
