import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/paging.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/picker.dart';
import '../../../core/widgets/widgets.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../data/admin.dart';
import '../data/catalogue.dart';
import '../data/rules.dart';
import '../widgets/admin_widgets.dart';

String catalogueError(Object e) => e is StaleRowException
    ? 'That changed since the list loaded (an order, or another phone). It’s refreshed: check it and try again.'
    : adminError(e);

enum BulkAction {
  show('Show in the shop'),
  hide('Hide from the shop'),
  feature('Feature on home'),
  unfeature('Stop featuring'),
  setStock('Set stock to…'),
  addStock('Add stock…'),
  removeStock('Remove stock…'),
  raisePercent('Raise price by %…'),
  lowerPercent('Lower price by %…'),
  raiseRupees('Raise price by ₹…'),
  lowerRupees('Lower price by ₹…');

  const BulkAction(this.label);
  final String label;
}

/// Every variant with its stock, price and visibility; quick edits inline, bulk edits for a selection.
class AdminCatalogueScreen extends ConsumerStatefulWidget {
  const AdminCatalogueScreen({super.key});

  @override
  ConsumerState<AdminCatalogueScreen> createState() => _AdminCatalogueScreenState();
}

class _AdminCatalogueScreenState extends ConsumerState<AdminCatalogueScreen> {
  String _query = '';
  String? _categoryId;
  String? _brandId;
  StockFilter _stock = StockFilter.all;
  VisibilityFilter _visibility = VisibilityFilter.all;
  CatalogueSort _sort = CatalogueSort.name;

  bool _selecting = false;
  final _selected = <String>{}; // variant ids
  bool _busy = false; // a bulk edit is running: further taps on it are ignored

  final _want = <String, int>{}; // stock from −/+ taps not saved yet
  final _sending = <String>{}; // rows with a write on the way

  final _search = TextEditingController();
  Timer? _debounce; // the server searches once typing pauses, not on every letter

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// The loaded pages of the current view; edits go through it.
  CatalogueNotifier get _notifier => ref.read(catalogueProvider(_view).notifier);

  CatalogueView get _view => (
        query: _query,
        categoryId: _categoryId,
        brandId: _brandId,
        stock: _stock,
        visibility: _visibility,
        sort: _sort,
      );

  bool get _filtered =>
      _categoryId != null || _brandId != null || _stock != StockFilter.all || _visibility != VisibilityFilter.all;

  void _endSelect() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  // A new view is a new list from page 1, so a selection made in the old one is dropped.
  void _clearFilters() => setState(() {
        _categoryId = _brandId = null;
        _stock = StockFilter.all;
        _visibility = VisibilityFilter.all;
        _selected.clear();
      });

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  Future<void> _pick<T>(String title, List<(T?, String)> options, T? current, void Function(T?) apply) async {
    final picked = await showPickerSheet<T>(context, title: title, options: options, selected: current);
    if (picked != null && mounted) {
      setState(() {
        apply(picked.$1);
        _selected.clear();
      });
    }
  }

  // Quick edits -----------------------------------------------------------------

  void _step(CatalogueRow r, int by) {
    setState(() => _want[r.variantId] = bulkStock(_want[r.variantId] ?? r.stock, StockOp.add, by));
    unawaited(_sendStock(r.variantId));
  }

  /// One stock write per row at a time; taps made while it's on the way go out together in the next one.
  Future<void> _sendStock(String id) async {
    if (!_sending.add(id)) return;
    final notifier = _notifier;
    try {
      while (true) {
        final want = _want[id], row = notifier.row(id);
        if (want == null || row == null || want == row.stock) break;
        await notifier.setStock(row, want);
      }
    } catch (e) {
      if (mounted) showMessage(context, catalogueError(e));
    } finally {
      _sending.remove(id);
      if (mounted) setState(() => _want.remove(id));
    }
  }

  Future<void> _typeStock(CatalogueRow r) async {
    final n = await _askNumber(context, title: 'Stock of ${r.sku}', label: 'Units in stock', min: 0, max: maxStock, initial: r.stock);
    if (n == null || n == r.stock || !mounted) return;
    await _write(() => _notifier.setStock(r, n));
  }

  Future<void> _editPrice(CatalogueRow r) async {
    final p = await showModalBottomSheet<(int, int)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PriceSheet(row: r),
    );
    if (p == null || !mounted || (p.$1 == r.pricePaise && p.$2 == r.mrpPaise)) return;
    await _write(() => _notifier.setPrice(r, p.$1, p.$2));
  }

  /// One tap, so it offers Undo: the eye sits next to the price button and a slip hides the variant at once.
  Future<void> _toggleVisible(CatalogueRow r) async {
    final key = 'visible:${r.variantId}';
    if (!_sending.add(key)) return; // a tap is already on the way
    final notifier = _notifier;
    try {
      await notifier.setVisible([r], !r.variantActive);
      if (!mounted) return;
      showMessage(
        context,
        r.variantActive ? '${r.sku} hidden from the shop' : '${r.sku} shown in the shop',
        action: SnackBarAction(label: 'Undo', onPressed: () {
          if (notifier.row(r.variantId) case final now?) _toggleVisible(now);
        }),
      );
    } catch (e) {
      if (mounted) showMessage(context, catalogueError(e));
    } finally {
      _sending.remove(key);
    }
  }

  /// The row already shows the change (optimistic); a failure has put it back.
  Future<void> _write(Future<void> Function() write, [String? done]) async {
    try {
      await write();
      if (mounted && done != null) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, catalogueError(e));
    }
  }

  // Bulk edits ------------------------------------------------------------------

  Future<void> _bulk(List<CatalogueRow> rows) async {
    if (_busy || rows.isEmpty) return;
    setState(() => _busy = true);
    try {
      final picked = await showPickerSheet<BulkAction>(
        context,
        title: 'Change ${_rowsLabel(rows.length)}',
        options: [for (final a in BulkAction.values) (a, a.label)],
      );
      final action = picked?.$1;
      if (action != null && mounted) await _runBulk(action, rows);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runBulk(BulkAction action, List<CatalogueRow> rows) async {
    final notifier = _notifier;
    final products = {for (final r in rows) r.productId}.length;
    final productsLabel = '$products product${products == 1 ? '' : 's'}';
    Future<void> flag(String title, String message, String verb, Future<void> Function() write, String done) async {
      final ok = await confirmChoice(context, title: title, message: message, action: verb, keep: 'Cancel');
      if (!ok || !mounted) return;
      _endSelect();
      await _write(write, done);
    }

    switch (action) {
      case BulkAction.show:
        await flag('Show ${_rowsLabel(rows.length)}?', 'Customers can see and buy them again (when their product is shown too).',
            'Show', () => notifier.setVisible(rows, true), '${_rowsLabel(rows.length)} shown');
      case BulkAction.hide:
        await flag('Hide ${_rowsLabel(rows.length)}?', 'Customers stop seeing them right away. Nothing is deleted: show them again any time.',
            'Hide', () => notifier.setVisible(rows, false), '${_rowsLabel(rows.length)} hidden');
      case BulkAction.feature:
        await flag('Feature $productsLabel?', 'They show in the carousel at the top of the home screen.', 'Feature',
            () => notifier.setFeatured(rows, true), '$productsLabel featured');
      case BulkAction.unfeature:
        await flag('Stop featuring $productsLabel?', 'They leave the home carousel but stay in the shop.', 'Stop featuring',
            () => notifier.setFeatured(rows, false), '$productsLabel no longer featured');
      case BulkAction.setStock || BulkAction.addStock || BulkAction.removeStock:
        final op = switch (action) {
          BulkAction.setStock => StockOp.set,
          BulkAction.addStock => StockOp.add,
          _ => StockOp.remove,
        };
        final n = await _askNumber(
          context,
          title: action.label.replaceAll('…', ''),
          label: op == StockOp.set ? 'Units in stock' : 'Units',
          min: op == StockOp.set ? 0 : 1,
          max: maxStock,
        );
        if (n == null || !mounted) return;
        final changes = _changes(rows, (r) => r.copyWith(stock: bulkStock(r.stock, op, n)), (a, b) => a.stock == b.stock);
        await _preview(
          title: action.label.replaceAll('…', ' $n'),
          rows: rows.length,
          changes: changes,
          show: (r) => '${r.stock}',
          // one request when every row gets the same number; otherwise one per row, guarded
          run: op == StockOp.set
              ? (progress) async {
                  try {
                    await notifier.setStockAll([for (final c in changes) c.before], n);
                    progress(changes.length);
                    return const [];
                  } catch (e) {
                    return [for (final c in changes) (c, e)];
                  }
                }
              : (progress) => notifier.applyEach(changes, progress),
        );
      case BulkAction.raisePercent || BulkAction.lowerPercent || BulkAction.raiseRupees || BulkAction.lowerRupees:
        // two actions instead of a minus sign: many Android number pads have no minus key
        final percent = action == BulkAction.raisePercent || action == BulkAction.lowerPercent;
        final lower = action == BulkAction.lowerPercent || action == BulkAction.lowerRupees;
        final n = await _askNumber(
          context,
          title: action.label.replaceAll('…', ''),
          label: percent ? 'Percent' : 'Rupees',
          prefix: percent ? null : '₹ ',
          suffix: percent ? '%' : null,
          min: 1,
          max: percent ? (lower ? -minPercent : maxPercent) : maxPricePaise ~/ 100,
          helper: 'Rounded to whole rupees, never under ₹1 or over the MRP.',
        );
        if (n == null || !mounted) return;
        final amount = lower ? -n : n;
        final changes = _changes(
            rows,
            (r) => r.copyWith(pricePaise: bulkPrice(r.pricePaise, r.mrpPaise, percent: percent, amount: amount)),
            (a, b) => a.pricePaise == b.pricePaise);
        await _preview(
          title: '${lower ? 'Lower' : 'Raise'} prices by ${percent ? '$n%' : formatInr(n * 100)}',
          rows: rows.length,
          changes: changes,
          show: (r) => formatInr(r.pricePaise),
          run: (progress) => notifier.applyEach(changes, progress),
        );
    }
  }

  List<RowChange> _changes(List<CatalogueRow> rows, CatalogueRow Function(CatalogueRow) apply, bool Function(CatalogueRow, CatalogueRow) same) => [
        for (final r in rows)
          if (apply(r) case final after when !same(r, after)) (before: r, after: after),
      ];

  Future<void> _preview({
    required String title,
    required int rows,
    required List<RowChange> changes,
    required String Function(CatalogueRow) show,
    required Future<List<(RowChange, Object?)>> Function(void Function(int) progress) run,
  }) async {
    if (changes.isEmpty) {
      showMessage(context, 'Nothing to change: the selected rows already match.');
      return;
    }
    final finished = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _BulkSheet(title: title, rows: rows, changes: changes, show: show, run: run),
    );
    if (finished == true && mounted) _endSelect();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(catalogueProvider(_view));
    final summary = ref.watch(catalogueSummaryProvider(_view));
    final categories = ref.watch(adminCategoriesProvider).value ?? const [];
    final brands = ref.watch(adminBrandsProvider).value ?? const [];
    final all = value.value?.items ?? const <CatalogueRow>[];
    final selectedRows = [for (final r in all) if (_selected.contains(r.variantId)) r];
    return AdminGate(
      child: PopScope(
        canPop: !_selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _endSelect();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: _selecting
                ? IconButton(tooltip: 'Stop selecting', icon: const Icon(PhosphorIconsRegular.x), onPressed: _endSelect)
                : null,
            title: Text(_selecting ? '${_selected.length} selected' : 'Catalogue'),
            actions: [
              if (_selecting)
                IconButton(
                  tooltip: 'Select all loaded',
                  icon: const Icon(PhosphorIconsRegular.selectionAll),
                  onPressed: () => setState(() => _selected.addAll([for (final r in all) r.variantId])),
                )
              else
                IconButton(
                  tooltip: 'Select rows',
                  icon: const Icon(PhosphorIconsRegular.checkSquare),
                  onPressed: () => setState(() => _selecting = true),
                ),
            ],
          ),
          bottomNavigationBar: _selecting
              ? BulkBar(count: selectedRows.length, onPressed: selectedRows.isEmpty || _busy ? null : () => _bulk(selectedRows))
              : null,
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search name or SKU',
                    prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(PhosphorIconsRegular.xCircle),
                            onPressed: () => setState(() {
                              _debounce?.cancel();
                              _search.clear();
                              _query = '';
                              _selected.clear();
                            }),
                          ),
                  ),
                  textInputAction: TextInputAction.search,
                  inputFormatters: textInput(MaxLen.search),
                  onChanged: (q) {
                    setState(() {}); // the clear button
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      if (mounted && tidy(q) != _query) {
                        setState(() {
                          _query = tidy(q);
                          _selected.clear();
                        });
                      }
                    });
                  },
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: Row(
                  spacing: Space.sm,
                  children: [
                    PickerChip(
                      label: categories.where((c) => c.id == _categoryId).firstOrNull?.name ?? 'Category',
                      selected: _categoryId != null,
                      onTap: () => _pick<String>('Category', [(null, 'All categories'), for (final c in categories) (c.id, c.name)],
                          _categoryId, (v) => _categoryId = v),
                    ),
                    PickerChip(
                      label: brands.where((b) => b.id == _brandId).firstOrNull?.name ?? 'Brand',
                      selected: _brandId != null,
                      onTap: () => _pick<String>(
                          'Brand', [(null, 'All brands'), for (final b in brands) (b.id, b.name)], _brandId, (v) => _brandId = v),
                    ),
                    PickerChip(
                      label: _stock == StockFilter.all ? 'Stock' : _stock.label,
                      selected: _stock != StockFilter.all,
                      onTap: () => _pick<StockFilter>('Stock', [for (final s in StockFilter.values) (s, s.label)], _stock,
                          (v) => _stock = v ?? StockFilter.all),
                    ),
                    PickerChip(
                      label: _visibility == VisibilityFilter.all ? 'Visibility' : _visibility.label,
                      selected: _visibility != VisibilityFilter.all,
                      onTap: () => _pick<VisibilityFilter>('Visibility', [for (final s in VisibilityFilter.values) (s, s.label)],
                          _visibility, (v) => _visibility = v ?? VisibilityFilter.all),
                    ),
                    PickerChip(
                      label: _sort.label,
                      icon: PhosphorIconsRegular.sortAscending,
                      selected: false,
                      onTap: () => _pick<CatalogueSort>('Sort by', [for (final s in CatalogueSort.values) (s, s.label)], _sort,
                          (v) => _sort = v ?? CatalogueSort.name),
                    ),
                    if (_filtered)
                      ActionChip(
                        avatar: const Icon(PhosphorIconsRegular.x, size: 16),
                        label: const Text('Clear filters'),
                        onPressed: _clearFilters,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.sm),
              Expanded(
                child: AsyncBody<Paged<CatalogueRow>>(
                  value: value,
                  onRetry: () => ref
                    ..invalidate(catalogueProvider)
                    ..invalidate(catalogueSummaryProvider),
                  loading: Skeletonizer(child: _list(_skeleton, summary: const AsyncLoading(), interactive: false)),
                  data: (page) {
                    final rows = page.items;
                    if (rows.isEmpty && !_filtered && _query.isEmpty) {
                      return EmptyState(
                        icon: PhosphorIconsRegular.package,
                        title: 'No products yet',
                        message: 'Add a product and its variants to see them here.',
                        action: FilledButton(
                          onPressed: () => context.push('/admin/products/new'),
                          child: const Text('Add product'),
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () {
                        ref.invalidate(catalogueSummaryProvider(_view));
                        return ref.refresh(catalogueProvider(_view).future);
                      },
                      child: rows.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              children: [
                                EmptyState(
                                  icon: PhosphorIconsRegular.magnifyingGlass,
                                  title: 'Nothing matches',
                                  message: _filtered ? 'Try another word or clear the filters.' : 'Try another word.',
                                  action: _filtered
                                      ? OutlinedButton(onPressed: _clearFilters, child: const Text('Clear filters'))
                                      : null,
                                ),
                              ],
                            )
                          : LoadMoreListener(
                              hasMore: page.hasMore,
                              onMore: _notifier.loadMore,
                              child: _list(
                                rows,
                                summary: summary,
                                footer: page.hasMore
                                    ? PagedFooter(
                                        failed: page.moreFailed,
                                        onRetry: () => _notifier.loadMore(retry: true),
                                        what: 'more variants',
                                      )
                                    : null,
                              ),
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(List<CatalogueRow> rows, {required AsyncValue<CatalogueSummary> summary, Widget? footer, bool interactive = true}) =>
      ListView.builder(
        key: PageStorageKey(_view), // a new search or filter starts at the top, not at the old list's offset
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(bottom: Space.xl + MediaQuery.paddingOf(context).bottom),
        itemCount: rows.length + 1 + (footer == null ? 0 : 1),
        itemBuilder: (context, i) {
          if (i == 0) {
            // the server's totals over every matching row; quietly absent if they fail (the rows still work)
            return switch (summary) {
              AsyncValue(value: final s?) => CatalogueSummaryCard(s),
              AsyncValue(hasError: true) => const SizedBox.shrink(),
              _ => const Skeletonizer(child: CatalogueSummaryCard(_skeletonSummary)),
            };
          }
          if (i > rows.length) return footer!;
          final r = rows[i - 1];
          return CatalogueTile(
            key: ValueKey(r.variantId),
            row: r,
            stock: _want[r.variantId] ?? r.stock,
            selecting: _selecting,
            selected: _selected.contains(r.variantId),
            onTap: !interactive
                ? null
                : _selecting
                    ? () => _toggle(r.variantId)
                    : () async {
                        await context.push('/admin/products/${r.productId}');
                        if (mounted) {
                          // the editor may have changed it
                          ref
                            ..invalidate(catalogueProvider)
                            ..invalidate(catalogueSummaryProvider);
                        }
                      },
            onLongPress: !interactive || _selecting
                ? null
                : () => setState(() {
                      _selecting = true;
                      _selected.add(r.variantId);
                    }),
            onStep: (by) => _step(r, by),
            onTypeStock: () => _typeStock(r),
            onEditPrice: () => _editPrice(r),
            onToggleVisible: () => _toggleVisible(r),
          );
        },
      );
}

String _rowsLabel(int n) => '$n variant${n == 1 ? '' : 's'}';

/// SKUs, units, stock value and low/out counts for every row the search and filters match (from the server, not
/// just the loaded pages); says so when they hide some.
class CatalogueSummaryCard extends StatelessWidget {
  const CatalogueSummaryCard(this.s, {super.key});

  final CatalogueSummary s;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget stat(String label, String value) => Expanded(
          child: Semantics(
            label: '$label, $value',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.labelSmall?.copyWith(color: c.onSurfaceVariant)),
                Text(
                  value,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
        );
    const gap = SizedBox(height: Space.sm);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
      child: Card(
        color: c.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.skus < s.total) ...[
                Text('Showing ${s.skus} of ${_rowsLabel(s.total)}', style: t.labelMedium?.copyWith(color: c.onSurfaceVariant)),
                gap,
              ],
              Row(spacing: Space.md, children: [stat('SKUs', '${s.skus}'), stat('Units in stock', '${s.units}')]),
              gap,
              Row(spacing: Space.md, children: [
                stat('Stock value at price', shortInr(s.valueAtPricePaise)),
                stat('Stock value at MRP', shortInr(s.valueAtMrpPaise)),
              ]),
              gap,
              Row(spacing: Space.md, children: [stat('Low (1–3 left)', '${s.low}'), stat('Out of stock', '${s.out}')]),
            ],
          ),
        ),
      ),
    );
  }
}

class CatalogueTile extends StatelessWidget {
  const CatalogueTile({
    super.key,
    required this.row,
    required this.stock,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onStep,
    required this.onTypeStock,
    required this.onEditPrice,
    required this.onToggleVisible,
  });

  final CatalogueRow row;
  final int stock; // shown: includes −/+ taps not saved yet
  final bool selecting;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<int> onStep;
  final VoidCallback onTypeStock;
  final VoidCallback onEditPrice;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final r = row;
    final off = discountPercent(r.pricePaise, r.mrpPaise);
    const tabular = [FontFeature.tabularFigures()];
    return Card(
      margin: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
      color: selected ? c.primaryContainer : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
              side: BorderSide(color: c.primary, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.fromLTRB(selecting ? Space.xs : Space.md, Space.md, Space.md, Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selecting)
                    Checkbox(
                      value: selected,
                      onChanged: onTap == null ? null : (_) => onTap!(),
                      semanticLabel: 'Select ${r.productName}, ${r.variantName}',
                    ),
                  SizedBox(width: 56, child: ProductImage(r.coverPath, radius: Radii.md, padding: Space.xs)),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.productName, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                        Text('${r.variantName} · ${r.sku}', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: formatInr(r.pricePaise), style: const TextStyle(fontWeight: FontWeight.w800)),
                            TextSpan(text: '  MRP ${formatInr(r.mrpPaise)}', style: TextStyle(color: c.onSurfaceVariant)),
                            if (off > 0) TextSpan(text: '  $off% off', style: TextStyle(color: c.secondary)),
                          ]),
                          style: t.bodyMedium?.copyWith(fontFeatures: tabular),
                        ),
                        if (!r.variantActive || !r.productActive || r.featured || stock <= lowStockMax)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: Wrap(
                              spacing: Space.xs,
                              runSpacing: Space.xs,
                              children: [
                                if (!r.variantActive) const Tag('Hidden', tone: TagTone.bad),
                                if (!r.productActive) const Tag('Product hidden', tone: TagTone.bad),
                                if (stock == 0)
                                  const Tag('Out of stock', tone: TagTone.bad)
                                else if (stock <= lowStockMax)
                                  const Tag('Low stock', tone: TagTone.deal),
                                if (r.featured) const Tag('Featured', tone: TagTone.ok),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!selecting) ...[
                const Padding(padding: EdgeInsets.symmetric(vertical: Space.sm), child: Divider()),
                Row(
                  children: [
                    _StockStepper(sku: r.sku, stock: stock, onStep: onStep, onType: onTypeStock),
                    const Spacer(),
                    IconButton.filledTonal(
                      tooltip: 'Edit price of ${r.sku}',
                      onPressed: onEditPrice,
                      icon: const Icon(PhosphorIconsRegular.currencyInr),
                    ),
                    const SizedBox(width: Space.sm),
                    // a toggle: solid while customers can see it
                    IconButton.outlined(
                      tooltip: r.variantActive ? 'Hide ${r.sku} from the shop' : 'Show ${r.sku} in the shop',
                      isSelected: r.variantActive,
                      onPressed: onToggleVisible,
                      icon: const Icon(PhosphorIconsRegular.eyeSlash),
                      selectedIcon: const Icon(PhosphorIconsRegular.eye),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StockStepper extends StatelessWidget {
  const _StockStepper({required this.sku, required this.stock, required this.onStep, required this.onType});

  final String sku;
  final int stock;
  final ValueChanged<int> onStep;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          tooltip: 'One less of $sku',
          onPressed: stock > 0 ? () => onStep(-1) : null,
          icon: const Icon(PhosphorIconsRegular.minus, size: 18),
        ),
        Semantics(
          button: true,
          label: 'Stock $stock. Type a number',
          excludeSemantics: true,
          child: InkWell(
            onTap: onType,
            borderRadius: BorderRadius.circular(Radii.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$stock', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text('in stock', style: t.labelSmall?.copyWith(color: c.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
        IconButton.outlined(
          tooltip: 'One more of $sku',
          onPressed: stock < maxStock ? () => onStep(1) : null,
          icon: const Icon(PhosphorIconsRegular.plus, size: 18),
        ),
      ],
    );
  }
}

/// "3 selected" and the bulk edit button, above the gesture bar.
class BulkBar extends StatelessWidget {
  const BulkBar({super.key, required this.count, required this.onPressed});

  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => StickyBar(
        child: Row(
          children: [
            Expanded(
              child: Text(
                count == 0 ? 'Tap rows to select them' : '${_rowsLabel(count)} selected',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: Space.sm),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(PhosphorIconsRegular.listChecks),
              label: const Text('Bulk edit'),
            ),
          ],
        ),
      );
}

/// Shows every planned change (old → new), saves on confirm with progress, then reports what didn't save.
/// Pops true once something was saved.
class _BulkSheet extends StatefulWidget {
  const _BulkSheet({required this.title, required this.rows, required this.changes, required this.show, required this.run});

  final String title;
  final int rows; // selected; [changes] leaves out the ones already at the new value
  final List<RowChange> changes;
  final String Function(CatalogueRow) show;
  final Future<List<(RowChange, Object?)>> Function(void Function(int) progress) run;

  @override
  State<_BulkSheet> createState() => _BulkSheetState();
}

class _BulkSheetState extends State<_BulkSheet> {
  int? _done; // null until saving starts
  List<(RowChange, Object?)>? _failed; // set when finished

  bool _closed = false;

  void _close(bool saved) {
    if (_closed) return; // a double tap must not pop the screen underneath too
    _closed = true;
    Navigator.pop(context, saved);
  }

  Future<void> _save() async {
    if (_done != null) return; // a second tap before the buttons went away
    setState(() => _done = 0);
    final failed = await widget.run((n) {
      if (mounted) setState(() => _done = n);
    });
    if (mounted) setState(() => _failed = failed);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final n = widget.changes.length;
    final saving = _done != null && _failed == null;
    final failed = _failed;
    const compact = Size(64, 44);
    final skipped = widget.rows - n;
    return PopScope(
      canPop: !saving,
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg + MediaQuery.paddingOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text(widget.title, style: t.titleLarge)),
              const SizedBox(height: Space.xs),
              Text(
                failed == null
                    ? '${_rowsLabel(n)} will change${skipped > 0 ? ' ($skipped already match)' : ''}. Check them, then save.'
                    : failed.isEmpty
                        ? 'All ${_rowsLabel(n)} saved.'
                        : 'Saved ${n - failed.length} of $n. These weren’t saved and are back to their old values:',
                style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
              ),
              const SizedBox(height: Space.sm),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (failed == null)
                      for (final ch in widget.changes)
                        _ChangeLine(
                          title: '${ch.before.productName} · ${ch.before.variantName}',
                          detail: '${widget.show(ch.before)} → ${widget.show(ch.after)}',
                        )
                    else
                      for (final (ch, e) in failed)
                        _ChangeLine(
                          title: '${ch.before.productName} · ${ch.before.variantName}',
                          detail: e == null ? 'Not tried: saving stopped at an earlier error.' : catalogueError(e),
                          error: true,
                        ),
                  ],
                ),
              ),
              const SizedBox(height: Space.md),
              if (saving) ...[
                LinearProgressIndicator(value: n == 0 ? null : _done! / n),
                const SizedBox(height: Space.sm),
                Text('Saving ${_done!} of $n…', style: t.bodyMedium),
              ] else if (failed != null)
                FilledButton(
                  onPressed: () => _close(failed.length < n),
                  child: const Text('Done'),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => _close(false),
                      style: TextButton.styleFrom(minimumSize: compact),
                      child: const Text('Cancel'),
                    ),
                    Flexible(
                      child: FilledButton(
                        onPressed: _save,
                        style: FilledButton.styleFrom(minimumSize: compact),
                        child: Text('Save ${_rowsLabel(n)}'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeLine extends StatelessWidget {
  const _ChangeLine({required this.title, required this.detail, this.error = false});

  final String title;
  final String detail;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.bodyMedium),
          Text(
            detail,
            style: (error ? t.bodySmall : t.titleSmall)?.copyWith(
              color: error ? c.error : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// A whole number from [min] to [max]; null if dismissed.
Future<int?> _askNumber(
  BuildContext context, {
  required String title,
  required String label,
  required int min,
  required int max,
  int? initial,
  String? prefix,
  String? suffix,
  String? helper,
}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NumberSheet(
        title: title,
        label: label,
        min: min,
        max: max,
        initial: initial,
        prefix: prefix,
        suffix: suffix,
        helper: helper,
      ),
    );

class _NumberSheet extends StatefulWidget {
  const _NumberSheet({
    required this.title,
    required this.label,
    required this.min,
    required this.max,
    required this.initial,
    required this.prefix,
    required this.suffix,
    required this.helper,
  });

  final String title;
  final String label;
  final int min;
  final int max;
  final int? initial;
  final String? prefix;
  final String? suffix;
  final String? helper;

  @override
  State<_NumberSheet> createState() => _NumberSheetState();
}

class _NumberSheetState extends State<_NumberSheet> {
  final _form = GlobalKey<FormState>();
  late final _text = TextEditingController(text: widget.initial?.toString());

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    final n = int.tryParse(v ?? '');
    return n == null || n < widget.min || n > widget.max ? 'Enter a whole number from ${widget.min} to ${widget.max}' : null;
  }

  bool _popped = false; // a double tap must not pop the screen underneath too

  void _submit() {
    if (_popped || !_form.currentState!.validate()) return;
    _popped = true;
    Navigator.pop(context, int.parse(_text.text));
  }

  @override
  Widget build(BuildContext context) {
    return SheetForm(
      formKey: _form,
      title: widget.title,
      children: [
        TextFormField(
          controller: _text,
          autofocus: true,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixText: widget.prefix,
            suffixText: widget.suffix,
            helperText: widget.helper,
            helperMaxLines: 3,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [DigitsFormatter('${widget.max}'.length)], // the validator holds the exact limit
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          validator: _validate,
        ),
        const SizedBox(height: Space.md),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}

/// Price and MRP in rupees (paise stored), the same rules as the variant editor: MRP ≥ price > 0.
class _PriceSheet extends StatefulWidget {
  const _PriceSheet({required this.row});

  final CatalogueRow row;

  @override
  State<_PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends State<_PriceSheet> {
  final _form = GlobalKey<FormState>();
  late final _price = TextEditingController(text: rupeesText(widget.row.pricePaise));
  late final _mrp = TextEditingController(text: rupeesText(widget.row.mrpPaise));

  @override
  void dispose() {
    _price.dispose();
    _mrp.dispose();
    super.dispose();
  }

  static final _maxText = 'Up to ${formatInr(maxPricePaise)}';

  bool _popped = false; // a double tap must not pop the screen underneath too

  void _submit() {
    if (_popped || !_form.currentState!.validate()) return;
    _popped = true;
    Navigator.pop(context, (parseRupees(_price.text)!, parseRupees(_mrp.text)!));
  }

  // pasted "₹1,299.50" keeps 1299.50; 7 digits is ₹99,99,999, the validator holds ₹10,00,000
  static const _rupeeInput = [RupeesFormatter(maxDigits: 7)];

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    return SheetForm(
      formKey: _form,
      title: 'Price of ${r.sku}',
      children: [
        Text('${r.productName} · ${r.variantName}', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: Space.md),
        TextFormField(
          controller: _price,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Price', prefixText: '₹ '),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _rupeeInput,
          validator: (v) {
            final p = parseRupees(v ?? '');
            if (p == null || p <= 0) return 'Enter a price above ₹0';
            return p > maxPricePaise ? _maxText : null;
          },
        ),
        const SizedBox(height: Space.md),
        TextFormField(
          controller: _mrp,
          decoration: const InputDecoration(labelText: 'MRP', prefixText: '₹ '),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _rupeeInput,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          validator: (v) {
            final mrp = parseRupees(v ?? '');
            if (mrp == null) return 'Enter the MRP';
            if (mrp > maxPricePaise) return _maxText;
            final price = parseRupees(_price.text);
            return price != null && mrp < price ? 'Can’t be below ${formatInr(price)}' : null;
          },
        ),
        const SizedBox(height: Space.md),
        FilledButton(onPressed: _submit, child: const Text('Save price')),
      ],
    );
  }
}

const CatalogueSummary _skeletonSummary =
    (skus: 120, units: 1450, valueAtPricePaise: 48200000, valueAtMrpPaise: 52000000, low: 4, out: 2, total: 120);

final _skeleton = [
  for (var i = 0; i < 5; i++)
    CatalogueRow(
      variantId: 'skeleton-$i',
      productId: 'p$i',
      productName: 'Samsung Galaxy S25 5G',
      variantName: '8 GB · 256 GB · Navy',
      sku: 'SAM-S25-8-256',
      pricePaise: 7499900,
      mrpPaise: 8099900,
      stock: 12,
      variantActive: true,
      productActive: true,
      featured: false,
      categoryId: 'c',
      brandId: 'b',
      updatedAt: DateTime(2026),
    ),
];
