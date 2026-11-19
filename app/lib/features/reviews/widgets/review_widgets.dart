import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/supabase.dart' show currentUserIdProvider;
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../admin/data/photos.dart' show preparePhoto, readPhoto;
import '../../admin/widgets/admin_widgets.dart' show pickPhoto;
import '../../feedback/widgets/feedback_widgets.dart' show StarRating;
import '../data/reviews.dart';
import '../data/reviews_repository.dart';

const maxReviewText = 1000;
const maxReviewPhotos = 3;

/// The product page's "Ratings & reviews": the average, the count, the 5-to-1 breakdown and the top three, with
/// "Write a review" for a customer whose order of it was delivered. Hidden when there's nothing to show or do.
class ReviewsSection extends ConsumerWidget {
  const ReviewsSection({super.key, required this.productId, required this.productName});

  final String productId;
  final String productName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(productStatsProvider(productId)).value ?? const ProductStats();
    final mine = ref.watch(myReviewProvider(productId)).value;
    final canWrite = mine != null || (ref.watch(reviewableProvider).value?.contains(productId) ?? false);
    if (stats.ratingCount == 0 && !canWrite) return const SizedBox.shrink();
    final all = ref.watch(productReviewsProvider(productId)).value ?? const <Review>[];
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Ratings & reviews', inset: false),
        if (stats.ratingCount > 0) RatingSummary(stats),
        for (final r in topReviews(all)) ReviewTile(r),
        if (all.length > 3)
          TextButton(
            onPressed: () => showAllReviews(context, productName, all),
            child: Text('See all ${stats.ratingCount} reviews'),
          ),
        if (mine?.hidden ?? false)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text('The shop has hidden your review. Edit it, or call the shop to ask why.',
                style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
          ),
        if (canWrite)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: OutlinedButton.icon(
              onPressed: () => showReviewSheet(context, productId: productId, productName: productName, mine: mine),
              icon: const Icon(PhosphorIconsRegular.pencilSimple, size: 18),
              label: Text(mine == null ? 'Write a review' : 'Edit your review'),
            ),
          ),
      ],
    );
  }
}

/// "4.3 ★★★★☆ 12 ratings" beside a bar per star, 5 down to 1.
class RatingSummary extends StatelessWidget {
  const RatingSummary(this.stats, {super.key});

  final ProductStats stats;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final n = stats.ratingCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Semantics(
            label: 'Rated ${stats.average.toStringAsFixed(1)} out of 5 by $n buyer${n == 1 ? '' : 's'}',
            excludeSemantics: true,
            child: Column(
              children: [
                Text(stats.average.toStringAsFixed(1), style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                StarRating(value: stats.average.round(), size: 16),
                Text('$n rating${n == 1 ? '' : 's'}', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              children: [
                for (var s = 5; s >= 1; s--)
                  Semantics(
                    label: '$s star${s == 1 ? '' : 's'}: ${stats.stars[s - 1]}',
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(width: 24, child: Text('$s★', style: t.bodySmall)),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(Radii.xs),
                              child: LinearProgressIndicator(
                                value: n == 0 ? 0 : stats.stars[s - 1] / n,
                                minHeight: 8,
                                color: BrandColors.gold,
                                backgroundColor: c.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 36,
                            child: Text('${stats.stars[s - 1]}', textAlign: TextAlign.end, style: t.bodySmall),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One review: stars, the buyer's first name, "Verified purchase", the date, the words and the photos.
class ReviewTile extends StatelessWidget {
  const ReviewTile(this.review, {super.key, this.trailing});

  final Review review;
  final Widget? trailing; // staff: the hide switch

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final r = review;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.outlineVariant))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.xs,
          children: [
            Row(
              children: [
                StarRating(value: r.rating, size: 16),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(r.name, style: t.titleSmall, overflow: TextOverflow.ellipsis)),
                ?trailing,
              ],
            ),
            Wrap(
              spacing: Space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Tag('Verified purchase', tone: TagTone.ok, icon: PhosphorIconsBold.sealCheck),
                Text(formatDate(r.updatedAt), style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ],
            ),
            if (r.text.isNotEmpty) Text(r.text, style: t.bodyMedium),
            if (r.photos.isNotEmpty)
              Wrap(
                spacing: Space.sm,
                children: [
                  for (final (i, p) in r.photos.indexed)
                    Semantics(
                      button: true,
                      label: 'Photo ${i + 1} of ${r.photos.length}, open',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(Radii.md),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(child: ProductImage(p, fit: BoxFit.contain, padding: 0)),
                        ),
                        child: SizedBox.square(dimension: 72, child: ProductImage(p, radius: Radii.md, padding: 0, fit: BoxFit.cover)),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Every visible review the page loaded (up to 50), newest first.
Future<void> showAllReviews(BuildContext context, String productName, List<Review> all) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg + MediaQuery.paddingOf(context).bottom),
          children: [
            Semantics(header: true, child: Text('Reviews of $productName', style: Theme.of(context).textTheme.titleLarge)),
            const SizedBox(height: Space.sm),
            for (final r in all) ReviewTile(r),
          ],
        ),
      ),
    );

/// The review sheet: stars, words (optional), up to 3 photos. Saving again replaces the review. True once saved.
Future<bool> showReviewSheet(BuildContext context, {required String productId, required String productName, Review? mine}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ReviewSheet(productId: productId, productName: productName, mine: mine),
  );
  if (saved == true && context.mounted) showMessage(context, 'Thanks! Your review helps other buyers.');
  return saved == true;
}

class ReviewSheet extends ConsumerStatefulWidget {
  const ReviewSheet({super.key, required this.productId, required this.productName, this.mine});

  final String productId;
  final String productName;
  final Review? mine;

  @override
  ConsumerState<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<ReviewSheet> {
  late int? _rating = widget.mine?.rating;
  late final _text = TextEditingController(text: widget.mine?.text ?? '');
  late final _photos = [...?widget.mine?.photos];
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message : friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto() async {
    final uid = ref.read(currentUserIdProvider);
    final file = await pickPhoto(context);
    if (file == null || uid == null) return;
    await _run(() async {
      final key = await ref.read(reviewsRepositoryProvider).uploadPhoto(uid, await preparePhoto(await readPhoto(file)));
      if (mounted) setState(() => _photos.add(key));
    });
  }

  Future<void> _save() async {
    final rating = _rating;
    if (rating == null) return setState(() => _error = 'Pick a star.');
    await _run(() async {
      await ref.read(reviewsRepositoryProvider).save(
            productId: widget.productId,
            rating: rating,
            text: tidy(_text.text, multiline: true),
            photos: _photos,
          );
      refreshReviews(ref, widget.productId);
      if (mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Review ${widget.productName}', style: t.titleLarge)),
            Text('Shown with your first name and “Verified purchase”.', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            const SizedBox(height: Space.md),
            Center(child: StarRating(value: _rating, onChanged: _busy ? null : (r) => setState(() => _rating = r))),
            const SizedBox(height: Space.md),
            TextField(
              controller: _text,
              decoration: InputDecoration(
                labelText: 'What did you like or not? (optional)',
                alignLabelWithHint: true,
                counter: LengthCounter(_text, maxReviewText),
              ),
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: textInput(maxReviewText, multiline: true),
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final p in _photos)
                  Stack(
                    children: [
                      SizedBox.square(dimension: 72, child: ProductImage(p, radius: Radii.md, padding: 0, fit: BoxFit.cover)),
                      Positioned(
                        top: -8,
                        right: -8,
                        child: IconButton(
                          tooltip: 'Remove photo',
                          onPressed: _busy ? null : () => setState(() => _photos.remove(p)),
                          icon: CircleAvatar(
                            radius: 12,
                            backgroundColor: c.surface,
                            child: Icon(PhosphorIconsBold.x, size: 14, color: c.onSurface),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_photos.length < maxReviewPhotos)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addPhoto,
                    icon: const Icon(PhosphorIconsRegular.camera, size: 18),
                    label: Text(_photos.isEmpty ? 'Add photos' : 'Add another'),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Text(_error!, style: t.bodySmall?.copyWith(color: c.error)),
            ],
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save review'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Rate this product" on a delivered order's line; "Edit your review" once there is one.
class RateProductButton extends ConsumerWidget {
  const RateProductButton({super.key, required this.productId, required this.productName});

  final String productId;
  final String productName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myReviewProvider(productId));
    final can = ref.watch(reviewableProvider).value?.contains(productId) ?? false;
    if (!can || !mine.hasValue) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => showReviewSheet(context, productId: productId, productName: productName, mine: mine.value),
      icon: const Icon(PhosphorIconsRegular.star, size: 18),
      label: Text(mine.value == null ? 'Rate this product' : 'Edit your review'),
    );
  }
}

/// The tile's "★ 4.3 (12)", only from [minTileReviews] reviews up.
class TileRatingBadge extends ConsumerWidget {
  const TileRatingBadge(this.productId, {super.key});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(tileRatingsProvider.select((m) => m.value?[productId]));
    if (r == null || r.count < minTileReviews) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Rated ${ratingLabel(r.avg10)} by ${r.count} buyers',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.xs)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(PhosphorIconsFill.star, size: 12, color: BrandColors.gold),
              const SizedBox(width: 2),
              Text('${ratingLabel(r.avg10)} (${r.count})', style: t.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "12 bought this week" under the price: units on paid or delivered orders in the last 7 days, shown only from
/// [minBoughtShown] (docs/GROWTH.md §2b). Counted by the server, never typed in.
class BoughtThisWeek extends ConsumerWidget {
  const BoughtThisWeek(this.productId, {super.key});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = boughtThisWeek(ref.watch(productStatsProvider(productId)).value?.sold ?? const {}, DateTime.now());
    if (n < minBoughtShown) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.usersThree, size: IconSizes.sm, color: c.onSurfaceVariant),
          const SizedBox(width: Space.xs),
          Text('$n bought this week',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
