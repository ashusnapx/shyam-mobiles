import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/paging.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../catalog/widgets/product_tile.dart';
import '../data/offers.dart';
import '../widgets/offer_widgets.dart';

/// "Apply" from Offers: the code goes with the cart, which checks it and shows the saving.
void applyFromOffers(BuildContext context, WidgetRef ref, String code) {
  ref.read(couponCodeProvider.notifier).set(code);
  showMessage(context, '$code added to your cart. You’ll see the saving there.');
  context.go('/cart');
}

final _fakeOffer = Offer(
  id: 'skeleton',
  title: 'Festive offer on phones',
  description: 'On all smartphones this week',
  code: 'FESTIVE10',
  kind: OfferKind.percent,
  value: 10,
  minSubtotalPaise: 199900,
  startsAt: DateTime(2026),
);

class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(availableOffersProvider);
    final applied = ref.watch(couponCodeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Offers & coupons')),
      body: AsyncBody<List<Offer>>(
        value: offers,
        onRetry: () => ref.invalidate(availableOffersProvider),
        loading: Skeletonizer(
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Space.lg),
            children: [for (var i = 0; i < 3; i++) OfferCard(_fakeOffer, onApply: () {})],
          ),
        ),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: PhosphorIconsRegular.sealPercent,
                title: 'No offers right now',
                message: 'New coupons and sales show up here. Check back soon.',
                action: FilledButton(onPressed: () => context.go('/'), child: const Text('Keep shopping')),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(availableOffersProvider.future),
                // available_offers() is every running offer the caller may use (a JSON array: no paging), built lazily
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
                  itemCount: list.length,
                  itemBuilder: (context, i) => Padding(
                    key: ValueKey(list[i].id),
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: OfferCard(
                      list[i],
                      applied: list[i].code != null && list[i].code == applied,
                      onApply: list[i].code == null ? null : () => applyFromOffers(context, ref, list[i].code!),
                    ).enter(context, index: i),
                  ),
                ),
              ),
      ),
    );
  }
}

class OfferDetailScreen extends ConsumerWidget {
  const OfferDetailScreen({super.key, required this.offerId});

  final String offerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(availableOffersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Offer')),
      body: AsyncBody<List<Offer>>(
        value: offers,
        onRetry: () => ref.invalidate(availableOffersProvider),
        loading: const Center(child: CircularProgressIndicator()),
        data: (list) => switch (list.where((o) => o.id == offerId).firstOrNull) {
          final o? => _Detail(offer: o),
          null => EmptyState(
              icon: PhosphorIconsRegular.hourglass,
              title: 'This offer has ended',
              message: 'Have a look at what’s on now.',
              action: FilledButton(onPressed: () => context.pushReplacement('/offers'), child: const Text('See offers')),
            ),
        },
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.offer});

  final Offer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final o = offer;
    final products = ref.watch(offerProductsProvider(o.id));
    final left = timeLeft(o.endsAt);
    final applied = ref.watch(couponCodeProvider) == o.code;
    final terms = [
      ...offerTerms(o),
      if (o.endsAt != null) 'Valid till ${formatDateTime(o.endsAt!)}',
    ];
    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(availableOffersProvider);
        return ref.refresh(offerProductsProvider(o.id).future);
      },
      child: LoadMoreListener(
        hasMore: products.value?.hasMore ?? false,
        onMore: ref.read(offerProductsProvider(o.id).notifier).loadMore,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      children: [
                        Tag(offerHeadline(o), tone: TagTone.deal, icon: PhosphorIconsBold.sealPercent),
                        if (left != null) Tag(left, icon: PhosphorIconsBold.clock),
                      ],
                    ),
                    const SizedBox(height: Space.sm),
                    Semantics(header: true, child: Text(o.title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
                    if (o.description.isNotEmpty) ...[
                      const SizedBox(height: Space.xs),
                      Text(o.description, style: t.bodyMedium),
                    ],
                    const SizedBox(height: Space.lg),
                    if (o.code case final code?)
                      CodeActions(code: code, applied: applied, onApply: () => applyFromOffers(context, ref, code))
                    else
                      const Tag('No code needed: it applies at checkout', tone: TagTone.ok, icon: PhosphorIconsBold.check),
                    if (terms.isNotEmpty) ...[
                      const SizedBox(height: Space.lg),
                      Text('Terms', style: t.titleSmall),
                      const SizedBox(height: Space.xs),
                      for (final line in terms)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(PhosphorIconsRegular.check, size: 16, color: c.onSurfaceVariant),
                              const SizedBox(width: Space.sm),
                              Expanded(child: Text(line, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant))),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: SectionHeader(o.wholeOrder ? 'Works on everything, like' : 'Products in this offer')),
            ...switch (products) {
              AsyncValue(value: final page?) when page.items.isEmpty => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                      child: Text('Nothing in stock for this offer right now.', style: t.bodyMedium),
                    ),
                  ),
                ],
              AsyncValue(value: final page?) => [
                  SliverProductGrid(page.items),
                  if (page.hasMore)
                    SliverToBoxAdapter(
                      child: PagedFooter(
                        failed: page.moreFailed,
                        onRetry: () => ref.read(offerProductsProvider(o.id).notifier).loadMore(retry: true),
                        what: 'more products',
                      ),
                    ),
                ],
              AsyncValue(:final error?) => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorView(error: error, onRetry: () => ref.invalidate(offerProductsProvider(o.id))),
                  ),
                ],
              _ => [Skeletonizer.sliver(child: SliverProductGrid(fakeCards(4)))],
            },
            const SliverPadding(padding: EdgeInsets.only(bottom: Space.xl)),
          ],
        ),
      ),
    );
  }
}
