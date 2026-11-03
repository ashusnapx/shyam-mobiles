import 'dart:async';

import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/network.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/picker.dart';
import '../../../core/widgets/widgets.dart';
import '../data/catalog.dart';
import '../widgets/product_tile.dart';

const _priceCaps = [150000, 500000, 1500000, 3000000, 5000000];
const _phoneBands = <(int?, int?)>[(null, 1000000), (null, 1500000), (null, 2500000), (2500000, null)];

/// What Waidhan asks for most, as chips under an empty search.
const _popular = ['Keypad phone', 'Charger', 'Earphones', 'Cover', 'Screen guard'];
const _recentKey = 'recent_searches';

/// Route params seed the filters once; after that they live in local state. Updating the route per keystroke
/// would recreate this screen (the route is keyed by its query) and drop keyboard focus.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.query, this.category, this.brand, this.sort, this.minPrice, this.maxPrice});

  final String? query;
  final String? category;
  final String? brand;
  final String? sort;
  final int? minPrice; // paise; Home's budget bands
  final int? maxPrice;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  // a deep link can carry any ?q=; the field and the query keep the first 100 characters
  late final _text = TextEditingController(text: _clip(widget.query ?? ''));
  Timer? _debounce;

  late String _q = tidy(_text.text);

  static String _clip(String q) => String.fromCharCodes(q.runes.take(MaxLen.search));
  late String? _category = widget.category;
  late String? _brand = widget.brand;
  late int? _minPrice = (widget.minPrice ?? 0) > 0 ? widget.minPrice : null;
  late int? _maxPrice = (widget.maxPrice ?? 0) > 0 ? widget.maxPrice : null;
  bool _inStock = false;
  late SearchSort _sort = SearchSort.parse(widget.sort);

  SearchParams get _params => (
        q: _q,
        category: _category,
        brand: _brand,
        minPricePaise: _minPrice,
        maxPricePaise: _maxPrice,
        inStock: _inStock,
        sort: _sort,
      );
  bool get _filtered => _category != null || _brand != null || _minPrice != null || _maxPrice != null || _inStock;

  List<String> _recent = const []; // the last searches typed on this phone, newest first

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecent());
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null; // no plugin (tests): nothing is remembered
    }
  }

  Future<void> _loadRecent() async {
    final saved = (await _prefs())?.getStringList(_recentKey) ?? const [];
    if (mounted && saved.isNotEmpty) setState(() => _recent = saved);
  }

  Future<void> _remember(String q) async {
    if (q.isEmpty) return;
    final next = [q, ..._recent.where((r) => r.toLowerCase() != q.toLowerCase())].take(5).toList();
    setState(() => _recent = next);
    await (await _prefs())?.setStringList(_recentKey, next);
  }

  void _searchFor(String q) {
    _text.text = q;
    _setQuery(q);
    unawaited(_remember(tidy(q)));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _setQuery(String text) {
    _debounce?.cancel();
    if (tidy(text) != _q) setState(() => _q = tidy(text));
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _setQuery(text));
  }

  void _clearFilters() => setState(() {
        _category = null;
        _brand = null;
        _minPrice = null;
        _maxPrice = null;
        _inStock = false;
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
    final category = categories.where((c) => c.slug == _category).firstOrNull;
    final categoryName = category?.name ?? _category;
    final brandName = brands.where((b) => b.slug == _brand).firstOrNull?.name ?? _brand;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
              child: ValueListenableBuilder(
                valueListenable: _text,
                builder: (context, value, _) => TextField(
                  controller: _text,
                  // only from the Search tab itself, not from a link into a list
                  autofocus: GoRouterState.of(context).uri.query.isEmpty,
                  textInputAction: TextInputAction.search,
                  inputFormatters: textInput(MaxLen.search),
                  onChanged: _onChanged,
                  onSubmitted: _searchFor,
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
                  PickerChip(
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
                  PickerChip(
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
                  PickerChip(
                    label: _priceLabel ?? 'Price',
                    selected: _minPrice != null || _maxPrice != null,
                    onTap: () => _pick<(int?, int?)>(
                      'Price',
                      // phones: the same budget bands as Home's "Shop by budget"
                      Future.value([
                        (null, 'Any price'),
                        if (category?.kind == CategoryKind.phone)
                          for (final (min, max) in _phoneBands) ((min, max), max == null ? 'Above ${formatInr(min!)}' : 'Under ${formatInr(max)}')
                        else
                          for (final p in _priceCaps) ((null, p), 'Under ${formatInr(p)}'),
                      ]),
                      _minPrice == null && _maxPrice == null ? null : (_minPrice, _maxPrice),
                      (v) {
                        _minPrice = v?.$1;
                        _maxPrice = v?.$2;
                      },
                    ),
                  ),
                  FilterChip(
                    label: const Text('In stock'),
                    selected: _inStock,
                    showCheckmark: false,
                    onSelected: (v) => setState(() => _inStock = v),
                  ),
                  PickerChip(
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
                AsyncValue(value: final r?) => _results(params, r, category),
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

  /// "Under ₹15,000", "₹10,000 – ₹25,000", "Above ₹25,000"; null with no price filter.
  String? get _priceLabel => switch ((_minPrice, _maxPrice)) {
        (null, null) => null,
        (null, final max?) => 'Under ${formatInr(max)}',
        (final min?, null) => 'Above ${formatInr(min)}',
        (final min?, final max?) => '${formatInr(min)} – ${formatInr(max)}',
      };

  /// "35 products"; in a category, "11 phones" or "18 accessories".
  static String _count(int n, Category? category) {
    final (one, many) = switch (category?.kind) {
      CategoryKind.phone => ('phone', 'phones'),
      CategoryKind.accessory => ('accessory', 'accessories'),
      _ => ('product', 'products'),
    };
    return '$n ${n == 1 ? one : many}';
  }

  Future<void> _askOnWhatsApp() async {
    final phone = (await ref.read(storeSettingsProvider.future)).storePhone;
    final what = _q.isEmpty ? 'a product I couldn’t find in the app' : '“$_q”';
    if (mounted) await openUri(context, whatsAppUri(phone, text: 'Hi, do you have $what?'));
  }

  Widget _results(SearchParams params, SearchResults r, Category? category) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final notifier = ref.read(searchProvider(params).notifier);
    // data saver: no prefetching; the next page loads once the spinner row is in view, nothing is built off screen
    final saver = ref.watch(dataSaverProvider) == DataMode.saver;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < (saver ? 100 : 600)) notifier.loadMore();
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
          scrollCacheExtent: saver ? const ScrollCacheExtent.pixels(0) : null,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (_q.isEmpty && !_filtered)
              SliverToBoxAdapter(
                key: const ValueKey('suggest'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
                  child: Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.xs,
                    children: [
                      for (final r in _recent)
                        ActionChip(
                          avatar: const Icon(PhosphorIconsRegular.clockCounterClockwise, size: IconSizes.sm),
                          label: Text(r),
                          onPressed: () => _searchFor(r),
                        ),
                      for (final p in _popular.where((p) => !_recent.contains(p)))
                        ActionChip(label: Text(p), onPressed: () => _searchFor(p)),
                    ],
                  ),
                ),
              ),
            SliverToBoxAdapter(
              key: const ValueKey('count'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
                child: Text(_count(r.total, category), style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ),
            ),
            if (r.items.isEmpty)
              SliverFillRemaining(
                key: const ValueKey('empty'),
                hasScrollBody: false,
                child: EmptyState(
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  tone: Worlds.search,
                  title: 'We couldn’t find that',
                  message: 'Try another word, or ask us. We may be able to get it for you.',
                  action: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Space.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: _askOnWhatsApp,
                        style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.whatsapp,
                          foregroundColor: BrandColors.ink,
                        ),
                        icon: const Icon(PhosphorIconsFill.whatsappLogo),
                        label: const Text('Ask on WhatsApp'),
                      ),
                      if (_filtered) OutlinedButton(onPressed: _clearFilters, child: const Text('Clear filters')),
                    ],
                  ),
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
          child: Padding(padding: EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md), child: Text('20 products')),
        ),
        SliverProductGrid(fakeCards(6)),
      ],
    ),
  );
}
