import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../feedback/data/feedback.dart';
import '../../feedback/widgets/feedback_widgets.dart' show StarRating;
import '../../repairs/widgets/repair_widgets.dart' show ListSection;
import '../screens/admin_feedback_screen.dart' show feedbackTone;

/// Staff: the customer's rating of this order or repair (one per order/repair), or null. Only reads: opening the
/// order or repair doesn't mark it seen; the inbox does.
final aboutFeedbackProvider =
    FutureProvider.autoDispose.family<FeedbackEntry?, (FeedbackKind, String)>((ref, key) async {
  final (kind, id) = key;
  final row = await ref
      .watch(supabaseProvider)
      .from('feedback')
      .select()
      .eq('kind', kind.name)
      .eq(kind == FeedbackKind.order ? 'order_id' : 'repair_id', id)
      .maybeSingle();
  return row == null ? null : FeedbackEntry.fromJson(row);
});

/// "Customer feedback" on the admin order and repair screens: stars, comment, when and its status; opens the inbox
/// entry. Nothing while loading, without feedback, or if it can't load (the inbox still has it).
class CustomerFeedbackCard extends ConsumerWidget {
  const CustomerFeedbackCard({super.key, required this.kind, required this.id});

  final FeedbackKind kind; // order or repair
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(aboutFeedbackProvider((kind, id))).value;
    if (e == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListSection('Customer feedback'),
        Card(
          child: InkWell(
            onTap: () => context.push('/admin/feedback/${e.id}'),
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (e.rating != null) StarRating(value: e.rating, size: 18),
                            Tag(e.status.label, tone: feedbackTone(e.status)),
                          ],
                        ),
                        if (e.message.isNotEmpty) ...[
                          const SizedBox(height: Space.xs),
                          Text(e.message, style: t.bodyMedium),
                        ],
                        const SizedBox(height: Space.xs),
                        Text(formatDateTime(e.createdAt), style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Icon(PhosphorIconsRegular.caretRight, color: c.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
