import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/paging.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/picker.dart';
import '../../../core/widgets/widgets.dart';
import '../../feedback/data/feedback.dart';
import '../../feedback/widgets/feedback_widgets.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../widgets/admin_widgets.dart';

const _statusFilters = {'new': 'New', 'seen': 'Seen', 'resolved': 'Resolved', 'all': 'All'};

TagTone feedbackTone(FeedbackStatus s) => switch (s) {
  FeedbackStatus.unread => TagTone.deal,
  FeedbackStatus.seen => TagTone.info,
  FeedbackStatus.resolved => TagTone.ok,
};

/// "Asha Verma · +91 98765 43210", else the order or repair number, else "A customer".
String feedbackFrom(FeedbackEntry e) => [
  e.customerName ?? e.orderNumber ?? e.repairNumber ?? 'A customer',
  if (e.customerPhone case final p?) displayPhone(p),
].join(' · ');

void _feedbackChanged(WidgetRef ref, String id) {
  ref.invalidate(adminFeedbackProvider);
  ref.invalidate(listingReportsProvider);
  ref.invalidate(adminFeedbackEntryProvider(id));
  ref.invalidate(feedbackNewCountProvider);
}

/// Staff inbox: newest first, a page at a time, by status and kind; `?product=<id>` shows one listing's reports.
class AdminFeedbackScreen extends ConsumerStatefulWidget {
  const AdminFeedbackScreen({super.key, this.productId});

  final String? productId;

  @override
  ConsumerState<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends ConsumerState<AdminFeedbackScreen> {
  late String? _productId = widget.productId;
  late String _status = _productId == null ? 'new' : 'all'; // a listing's reports: all of them, read or not
  FeedbackKind? _kind;

  @override
  Widget build(BuildContext context) {
    final provider = adminFeedbackProvider((
      status: _status == 'all' ? null : FeedbackStatus.parse(_status),
      kind: _kind,
      productId: _productId,
    ));
    return AdminGate(
      child: Scaffold(
        appBar: AppBar(title: const Text('Feedback')),
        body: Column(
          children: [
            ChipBar(options: _statusFilters, selected: _status, onSelected: (s) => setState(() => _status = s)),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.sm),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  if (_productId != null)
                    InputChip(
                      label: const Text('One listing'),
                      onDeleted: () => setState(() => _productId = null),
                      deleteButtonTooltipMessage: 'Show feedback about everything',
                    ),
                  PickerChip(
                    label: _kind?.label ?? 'Any kind',
                    selected: _kind != null,
                    onTap: () async {
                      final picked = await showPickerSheet<FeedbackKind>(
                        context,
                        title: 'Kind',
                        options: [(null, 'Any kind'), for (final k in FeedbackKind.values) (k, k.label)],
                        selected: _kind,
                      );
                      if (picked != null && mounted) setState(() => _kind = picked.$1);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: AsyncBody<Paged<FeedbackEntry>>(
                value: ref.watch(provider),
                onRetry: () => ref.invalidate(provider),
                loading: const Center(child: CircularProgressIndicator()),
                data: (page) => page.items.isEmpty
                    ? EmptyState(
                        icon: PhosphorIconsRegular.chatCircleText,
                        title: _status == 'new' ? 'All caught up' : 'Nothing here',
                        message: 'Ratings, comments and problem reports from customers show up here.',
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref.refresh(provider.future),
                        child: LoadMoreListener(
                          hasMore: page.hasMore,
                          onMore: ref.read(provider.notifier).loadMore,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.only(bottom: Space.xl + MediaQuery.paddingOf(context).bottom),
                            itemCount: page.items.length + (page.hasMore ? 1 : 0),
                            itemBuilder: (context, i) => i == page.items.length
                                ? PagedFooter(
                                    failed: page.moreFailed,
                                    onRetry: () => ref.read(provider.notifier).loadMore(retry: true),
                                    what: 'more feedback',
                                  )
                                : _Row(page.items[i]),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.e);

  final FeedbackEntry e;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final firstLine = e.message.split('\n').first;
    return InkWell(
      onTap: () => context.push('/admin/feedback/${e.id}'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (e.rating != null) StarRating(value: e.rating, size: 16),
                  Tag(e.kind.label),
                  Tag(e.status.label, tone: feedbackTone(e.status)),
                ],
              ),
              if (firstLine.isNotEmpty) ...[
                const SizedBox(height: Space.xs),
                Text(firstLine, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
              ],
              const SizedBox(height: 2),
              Text(
                '${feedbackFrom(e)} · ${formatDateTime(e.createdAt)}',
                style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One message: everything it says, what it's about (with links), and the shop's note and status. Opening a new
/// one marks it seen.
class AdminFeedbackDetailScreen extends ConsumerWidget {
  const AdminFeedbackDetailScreen({super.key, required this.feedbackId});

  final String feedbackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminFeedbackEntryProvider(feedbackId));
    return AdminGate(
      child: Scaffold(
        appBar: AppBar(title: const Text('Feedback')),
        body: AsyncBody<FeedbackEntry>(
          value: value,
          onRetry: () => ref.invalidate(adminFeedbackEntryProvider(feedbackId)),
          loading: const Center(child: CircularProgressIndicator()),
          data: (e) => _Detail(key: ValueKey(e.id), entry: e),
        ),
      ),
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({super.key, required this.entry});

  final FeedbackEntry entry;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  late final _note = TextEditingController(text: widget.entry.adminNote);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.entry.status == FeedbackStatus.unread) {
      // seen once it's opened; quietly, a failure just leaves it new
      ref.read(feedbackApiProvider).update(widget.entry.id, status: FeedbackStatus.seen).then((_) {
        if (mounted) {
          ref
            ..invalidate(adminFeedbackProvider)
            ..invalidate(feedbackNewCountProvider);
        }
      }, onError: (Object _) {});
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(String done, {FeedbackStatus? status, String? note}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(feedbackApiProvider).update(widget.entry.id, status: status, adminNote: note);
      _feedbackChanged(ref, widget.entry.id);
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final e = widget.entry;
    final resolved = e.status == FeedbackStatus.resolved;
    return ListView(
      padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl + MediaQuery.paddingOf(context).bottom),
      children: [
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (e.rating != null) StarRating(value: e.rating, size: 22),
            Tag(e.kind.label),
            Tag(e.status == FeedbackStatus.unread ? 'Seen' : e.status.label, tone: feedbackTone(e.status)),
          ],
        ),
        const SizedBox(height: Space.md),
        SelectableText(e.message.isEmpty ? 'No comment, just the rating.' : e.message, style: t.bodyLarge),
        const SizedBox(height: Space.md),
        Text(feedbackFrom(e), style: t.bodyMedium),
        Text(formatDateTime(e.createdAt), style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        if (e.screen != null) Text('Sent from ${e.screen}', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.xs,
          children: [
            if (e.orderId case final id?)
              OutlinedButton.icon(
                onPressed: () => context.push('/admin/orders/$id'),
                icon: const Icon(PhosphorIconsRegular.receipt),
                label: Text('Order ${e.orderNumber ?? ''}'.trim()),
              ),
            if (e.repairId case final id?)
              OutlinedButton.icon(
                onPressed: () => context.push('/admin/repairs/$id'),
                icon: const Icon(PhosphorIconsRegular.wrench),
                label: Text('Repair ${e.repairNumber ?? ''}'.trim()),
              ),
            if (e.productId case final id?)
              OutlinedButton.icon(
                onPressed: () => context.push('/admin/products/$id'),
                icon: const Icon(PhosphorIconsRegular.deviceMobile),
                label: Text(e.productName ?? 'Product'),
              ),
          ],
        ),
        const ListSection('Shop note'),
        TextField(
          controller: _note,
          decoration: InputDecoration(
            labelText: 'Only staff see this',
            alignLabelWithHint: true,
            counter: LengthCounter(_note, maxFeedbackNote),
          ),
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: textInput(maxFeedbackNote, multiline: true),
        ),
        const SizedBox(height: Space.sm),
        OutlinedButton(
          onPressed: _busy ? null : () => _save('Note saved', note: tidy(_note.text, multiline: true)),
          child: const Text('Save note'),
        ),
        const SizedBox(height: Space.md),
        FilledButton(
          onPressed: _busy
              ? null
              : () => resolved
                    ? _save('Opened again', status: FeedbackStatus.seen)
                    : _save(
                        'Marked resolved',
                        status: FeedbackStatus.resolved,
                        note: tidy(_note.text, multiline: true),
                      ),
          child: Text(resolved ? 'Open it again' : 'Mark resolved'),
        ),
      ],
    );
  }
}

/// "Reports about this listing · 3" on the admin product editor; opens the inbox filtered to this product.
class ListingReportsRow extends ConsumerWidget {
  const ListingReportsRow({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(listingReportsProvider(productId)).value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(PhosphorIconsRegular.flag),
      title: const Text('Reports about this listing'),
      subtitle: Text(
        n == null
            ? 'Problems customers reported on the product page'
            : n == 0
            ? 'None so far'
            : '$n',
      ),
      trailing: const Icon(PhosphorIconsRegular.caretRight, size: 18),
      onTap: () => context.push('/admin/feedback?product=$productId'),
    );
  }
}
