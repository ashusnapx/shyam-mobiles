import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../reviews/data/reviews_repository.dart';
import '../../reviews/widgets/review_widgets.dart';
import '../widgets/admin_widgets.dart';

final adminReviewsProvider = FutureProvider.autoDispose<List<Review>>((ref) => ref.watch(reviewsRepositoryProvider).recent());

/// Staff: the newest 50 reviews. Hide one only for abuse, personal data or spam, never for being negative
/// (docs/GROWTH.md §2a); its author still sees it, with a note.
class AdminReviewsScreen extends ConsumerWidget {
  const AdminReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AdminGate(
        child: Scaffold(
          appBar: AppBar(title: const Text('Reviews')),
          body: AsyncBody<List<Review>>(
            value: ref.watch(adminReviewsProvider),
            onRetry: () => ref.invalidate(adminReviewsProvider),
            loading: const Center(child: CircularProgressIndicator()),
            data: (all) => all.isEmpty
                ? const EmptyState(icon: PhosphorIconsRegular.star, title: 'No reviews yet')
                : RefreshIndicator(
                    onRefresh: () => ref.refresh(adminReviewsProvider.future),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
                      children: [
                        Text('Hide only abuse, phone numbers or spam. Low ratings stay: that’s the law and it builds trust.',
                            style: Theme.of(context).textTheme.bodySmall),
                        for (final r in all)
                          ReviewTile(
                            r,
                            trailing: _HideSwitch(r),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      );
}

class _HideSwitch extends ConsumerWidget {
  const _HideSwitch(this.review);

  final Review review;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: () => context.push('/product/${review.productId}'), child: const Text('Product')),
          Semantics(
            label: 'Shown to customers',
            child: Switch(
              value: !review.hidden,
              onChanged: (shown) async {
                try {
                  await ref.read(reviewsRepositoryProvider).setHidden(review.id, hidden: !shown);
                  ref.invalidate(adminReviewsProvider);
                } catch (e) {
                  if (context.mounted) showMessage(context, friendlyError(e));
                }
              },
            ),
          ),
        ],
      );
}
