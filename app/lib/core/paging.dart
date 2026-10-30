import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'theme/tokens.dart';

/// A list loaded a page at a time. [moreFailed]: the last next-page load failed; paging pauses until a retry, so a
/// dead network shows "Try again" instead of a spinner forever.
typedef Paged<T> = ({List<T> items, bool hasMore, bool moreFailed});

/// Infinite scroll for any growing list: [build] loads the first page (so a refresh or invalidate starts over),
/// [loadMore] appends the next. Subclasses say how to [fetch] rows `from..from + size - 1` (PostgREST `range`) and
/// watch whatever the list depends on in their own `build` before calling `super.build()`.
abstract class PagedNotifier<T> extends AsyncNotifier<Paged<T>> {
  int get pageSize => 30;

  Future<List<T>> fetch(int from, int size);

  /// Rows are matched by this when a page repeats one (a row added at the top shifts everything down one).
  Object idOf(T item);

  /// Whether a page that came back with [rows] from [from] leaves more to load.
  bool hasMoreAfter(int from, List<T> rows) => rows.length == pageSize;

  bool _loadingMore = false;
  int _next = 0; // where the next page starts: pages, not loaded items, so dropped repeats don't shift it

  @override
  Future<Paged<T>> build() async {
    final rows = await fetch(0, pageSize);
    _next = pageSize;
    return (items: rows, hasMore: hasMoreAfter(0, rows), moreFailed: false);
  }

  /// Appends the next page. No-op while one is loading, at the end, or after a failure unless [retry].
  Future<void> loadMore({bool retry = false}) async {
    final cur = state.value;
    if (cur == null || !cur.hasMore || _loadingMore || state.isLoading || (cur.moreFailed && !retry)) return;
    _loadingMore = true;
    if (retry) state = AsyncData((items: cur.items, hasMore: true, moreFailed: false)); // the spinner again
    try {
      final from = _next;
      final rows = await fetch(from, pageSize);
      _next = from + pageSize;
      final seen = {for (final i in cur.items) idOf(i)};
      if (ref.mounted) {
        state = AsyncData((
          items: [...cur.items, ...rows.where((r) => !seen.contains(idOf(r)))],
          hasMore: hasMoreAfter(from, rows),
          moreFailed: false,
        ));
      }
    } catch (_) {
      if (ref.mounted) state = AsyncData((items: cur.items, hasMore: true, moreFailed: true));
    } finally {
      _loadingMore = false;
    }
  }

  /// Swaps loaded rows in place (an optimistic edit or its rollback), keeping the paging as it is.
  void replaceItems(List<T> Function(List<T> items) change) {
    final cur = state.value;
    if (!ref.mounted || cur == null) return;
    state = AsyncData((items: change(cur.items), hasMore: cur.hasMore, moreFailed: cur.moreFailed));
  }
}

/// Asks for the next page as the list nears its end (under 400 px of it left), like Orders.
class LoadMoreListener extends StatelessWidget {
  const LoadMoreListener({super.key, required this.hasMore, required this.onMore, required this.child});

  final bool hasMore;
  final Future<void> Function() onMore;
  final Widget child;

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
        onNotification: (s) {
          if (hasMore && s.metrics.axis == Axis.vertical && s.metrics.extentAfter < 400) unawaited(onMore());
          return false;
        },
        child: child,
      );
}

/// The row after the last loaded one: a spinner while the next page loads, or "Couldn't load more" with a retry.
class PagedFooter extends StatelessWidget {
  const PagedFooter({super.key, required this.failed, required this.onRetry, this.what = 'more'});

  final bool failed;
  final VoidCallback onRetry;
  final String what; // "more orders", for the spinner's screen-reader label

  @override
  Widget build(BuildContext context) => failed
      ? Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(PhosphorIconsRegular.arrowClockwise),
            label: const Text('Couldn’t load more. Try again'),
          ),
        )
      : Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Center(child: CircularProgressIndicator(semanticsLabel: 'Loading $what')),
        );
}
