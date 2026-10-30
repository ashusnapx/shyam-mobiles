import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/input.dart';
import '../../../core/paging.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../data/admin.dart';
import '../widgets/admin_widgets.dart';

class AdminProductsScreen extends ConsumerStatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  ConsumerState<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends ConsumerState<AdminProductsScreen> {
  String _query = '';
  Timer? _debounce; // one search per pause in typing, not per letter
  // The route passes no params; the dashboard's low-stock tile adds ?stock=low.
  late bool _lowOnly = GoRouterState.of(context).uri.queryParameters['stock'] == 'low';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = adminProductPagesProvider((query: _query, lowOnly: _lowOnly));
    final value = ref.watch(provider);
    return AdminGate(
      child: Scaffold(
        appBar: AppBar(title: const Text('Products')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/admin/products/new'),
          icon: const Icon(PhosphorIconsRegular.plus),
          label: const Text('Add product'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search products',
                  prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
                ),
                textInputAction: TextInputAction.search,
                inputFormatters: textInput(MaxLen.search),
                onChanged: (q) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = tidy(q)));
                },
              ),
            ),
            ChipBar(
              options: const {'all': 'All', 'low': 'Low stock'},
              selected: _lowOnly ? 'low' : 'all',
              onSelected: (k) => setState(() => _lowOnly = k == 'low'),
            ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: AsyncBody<Paged<AdminProductRow>>(
                value: value,
                onRetry: () => ref.invalidate(provider),
                loading: Skeletonizer(child: _Rows(rows: _skeleton)),
                data: (page) {
                  final rows = page.items;
                  if (rows.isEmpty && _query.isEmpty && !_lowOnly) {
                    return EmptyState(
                      icon: PhosphorIconsRegular.deviceMobile,
                      title: 'No products yet',
                      message: 'Add your first phone or accessory.',
                      action: FilledButton(
                        onPressed: () => context.push('/admin/products/new'),
                        child: const Text('Add product'),
                      ),
                    );
                  }
                  if (rows.isEmpty) {
                    return const EmptyState(
                      icon: PhosphorIconsRegular.magnifyingGlass,
                      title: 'Nothing matches',
                      message: 'Try another name or clear the filter.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () => ref.refresh(provider.future),
                    child: LoadMoreListener(
                      hasMore: page.hasMore,
                      onMore: ref.read(provider.notifier).loadMore,
                      child: _Rows(
                        rows: rows,
                        footer: page.hasMore
                            ? PagedFooter(
                                failed: page.moreFailed,
                                onRetry: () => ref.read(provider.notifier).loadMore(retry: true),
                                what: 'more products',
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
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.rows, this.footer});

  final List<AdminProductRow> rows;
  final Widget? footer; // the next page's spinner or retry

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: 96 + MediaQuery.paddingOf(context).bottom), // clear of the FAB
      itemCount: rows.length + (footer == null ? 0 : 1),
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        if (i == rows.length) return footer!;
        final p = rows[i];
        final stock = p.activeVariants == 0
            ? 'No active variants'
            : '${p.activeVariants} variant${p.activeVariants == 1 ? '' : 's'} · ${p.stock == 0 ? 'out of stock' : '${p.stock} in stock'}';
        return InkWell(
          onTap: () => context.push('/admin/products/${p.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
            child: Row(
              children: [
                SizedBox(width: 56, child: ProductImage(p.coverPath, radius: Radii.md, padding: Space.xs)),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: t.titleSmall),
                      Text('${p.brandName} · ${p.categoryName}', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                      Text(stock, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                      if (!p.isActive || p.isFeatured || p.lowStock)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Wrap(
                            spacing: Space.xs,
                            runSpacing: Space.xs,
                            children: [
                              if (!p.isActive) const Tag('Hidden', tone: TagTone.bad),
                              if (p.lowStock) const Tag('Low stock', tone: TagTone.deal),
                              if (p.isFeatured) const Tag('Featured', tone: TagTone.ok),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(PhosphorIconsRegular.caretRight, size: 18, color: c.onSurfaceVariant),
              ],
            ),
          ),
        );
      },
    );
  }
}

final _skeleton = [
  for (var i = 0; i < 6; i++)
    AdminProductRow(
      id: '$i',
      name: 'Samsung Galaxy S25 5G',
      brandName: 'Samsung',
      categoryName: 'Phones',
      isActive: true,
      isFeatured: false,
      coverPath: null,
      activeVariants: 2,
      stock: 12,
      lowStock: false,
    ),
];
