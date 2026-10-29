import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/picker.dart';
import '../../../core/widgets/widgets.dart';
import '../data/catalog.dart';
import '../widgets/product_tile.dart';

const _priceCaps = [150000, 500000, 1500000, 3000000, 5000000];

/// Route params seed the filters once; after that they live in local state. Updating the route per keystroke
/// would recreate this screen (the route is keyed by its query) and drop keyboard focus.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.query, this.category, this.brand, this.sort});

  final String? query;
  final String? category;
  final String? brand;
  final String? sort;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _text = TextEditingController(text: widget.query ?? '');
  Timer? _debounce;

  late String _q = (widget.query ?? '').trim();
  late String? _category = widget.category;
  late String? _brand = widget.brand;
  int? _maxPrice;
  late SearchSort _sort = SearchSort.parse(widget.sort);

  SearchParams get _params => (q: _q, category: _category, brand: _brand, maxPricePaise: _maxPrice, sort: _sort);
  bool get _filtered => _category != null || _brand != null || _maxPrice != null;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _setQuery(String text) {
    _debounce?.cancel();
    if (text.trim() != _q) setState(() => _q = text.trim());
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _setQuery(text));
  }

  void _clearFilters() => setState(() {
        _category = null;
        _brand = null;
        _maxPrice = null;
      });

  /// Bottom-sheet picker. [options] pairs a value with its label; a null value means "any".
  Future<void> _pick<T>(String title, Future<List<(T?, String)>> options, T? current, void Function(T?) apply) async {
    final List<(T?, String)> list;
    try {
      list = await options;
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
      return;
    }
    if (!mounted) return;
    final picked = await showPickerSheet<T>(context, title: title, options: list, selected: current);
    if (!mounted) return;
    if (picked != null) setState(() => apply(picked.$1));
  }

  @override
  Widget build(BuildContext context) {
    final params = _params;
    final results = ref.watch(searchProvider(params));
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final brands = ref.watch(brandsProvider).value ?? const [];
    final categoryName = categories.where((c) => c.slug == _category).firstOrNull?.name ?? _category;
    final brandName = brands.where((b) => b.slug == _brand).firstOrNull?.name ?? _brand;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 6, Space.lg, 0),
              child: ValueListenableBuilder(
                valueListenable: _text,
                builder: (context, value, _) => TextField(
                  controller: _text,
                  autofocus: widget.query == null && widget.category == null && widget.brand == null && widget.sort == null,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: _setQuery,
                  decoration: InputDecoration(
                    hintText: 'Search phones, cases, chargers…',
                    prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, size: 20),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(PhosphorIconsRegular.xCircle, size: 20),
                            onPressed: () {
                              _text.clear();
                              _setQuery('');
                            },
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Row(
                spacing: Space.sm,
                children: [
                  _FilterChip(
                    label: categoryName ?? 'Category',
                    selected: _category != null,
                    onTap: () => _pick<String>(
                      'Category',
                      ref.read(categoriesProvider.future).then((cs) => [
                            (null, 'All categories'),
                            for (final c in cs) (c.slug, c.name),
                          ]),
                      _category,
                      (v) => _category = v,
                    ),
                  ),
                  _FilterChip(
                    label: brandName ?? 'Brand',
                    selected: _brand != null,
                    onTap: () => _pick<String>(
                      'Brand',
                      ref.read(brandsProvider.future).then((bs) => [
                            (null, 'All brands'),
                            for (final b in bs) (b.slug, b.name),
                          ]),
                      _brand,
                      (v) => _brand = v,
                    ),
                  ),
                  _FilterChip(
                    label: _maxPrice == null ? 'Price' : 'Under ${formatInr(_maxPrice!)}',
                    selected: _maxPrice != null,
                    onTap: () => _pick<int>(
                      'Price',
                      Future.value([(null, 'Any price'), for (final p in _priceCaps) (p, 'Under ${formatInr(p)}')]),
                      _maxPrice,
                      (v) => _maxPrice = v,
                    ),
                  ),
                  _FilterChip(
                    label: _sort.label,
                    icon: PhosphorIconsRegular.sortAscending,
                    selected: false,
                    onTap: () => _pick<SearchSort>(
                      'Sort by',
                      Future.value([for (final s in SearchSort.values) (s, s.label)]),
                      _sort,
                      (v) => _sort = v ?? SearchSort.relevance,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (results) {
                AsyncValue(value: final r?) => _results(params, r),
                AsyncValue(:final error?) => ErrorView(
                    error: error,
                    onRetry: () => ref.invalidate(searchProvider(params)),
                  ),
                _ => _skeleton,
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(SearchParams params, SearchResults r) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final notifier = ref.read(searchProvider(params).notifier);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600) notifier.loadMore();
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async {
          try {
            ref.invalidate(searchProvider(params));
            await ref.read(searchProvider(params).future);
          } catch (_) {} // the error view shows it
        },
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              key: const ValueKey('count'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, 10, Space.lg, Space.md),
                child: Text(
                  r.total == 1 ? '1 result' : '${r.total} results',
                  style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ),
            ),
            if (r.items.isEmpty)
              SliverFillRemaining(
                key: const ValueKey('empty'),
                hasScrollBody: false,
                child: EmptyState(
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  title: 'Nothing matches that',
                  message: _filtered ? 'Try fewer filters or a different word.' : 'Try a different word.',
                  action: _filtered
                      ? OutlinedButton(onPressed: _clearFilters, child: const Text('Clear filters'))
                      : null,
                ),
              )
            else
              SliverProductGrid(r.items, key: const ValueKey('grid')),
            if (r.moreFailed)
              SliverToBoxAdapter(
                key: const ValueKey('more-failed'),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => notifier.loadMore(retry: true),
                    icon: const Icon(PhosphorIconsRegular.arrowClockwise),
                    label: const Text('Couldn’t load more. Try again'),
                  ),
                ),
              )
            else if (r.items.length < r.total)
              const SliverToBoxAdapter(
                key: ValueKey('more'),
                child: Padding(
                  padding: EdgeInsets.all(Space.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            const SliverPadding(key: ValueKey('end'), padding: EdgeInsets.only(bottom: Space.lg)),
          ],
        ),
      ),
    );
  }

  static final _skeleton = Skeletonizer(
    child: CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.fromLTRB(Space.lg, 10, Space.lg, Space.md), child: Text('20 results')),
        ),
        SliverProductGrid(fakeCards(6)),
      ],
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final fg = selected ? c.onPrimaryContainer : c.onSurface;
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      selectedColor: c.primaryContainer,
      side: selected ? BorderSide.none : null,
      avatar: icon == null ? null : Icon(icon, size: 16, color: fg),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          Text(label, style: TextStyle(color: fg)),
          if (icon == null) Icon(PhosphorIconsBold.caretDown, size: 12, color: fg),
        ],
      ),
      onSelected: (_) => onTap(),
    );
  }
}
