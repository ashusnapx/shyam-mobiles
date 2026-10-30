import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../feedback/widgets/feedback_widgets.dart';
import '../data/repairs.dart';
import '../widgets/repair_widgets.dart';

const _steps = [
  RepairStatus.requested,
  RepairStatus.confirmed,
  RepairStatus.inProgress,
  RepairStatus.ready,
  RepairStatus.completed,
];

/// What happens next, in the customer's words, for the step they're on (the quote decides most of it).
String repairStepCopy(RepairBooking b) => switch (b.status) {
      _ when b.awaitingApproval => 'Check the price below. Work starts only after you approve it.',
      _ when b.quoteDeclined => b.canCancel
          ? 'You declined the price. We’ll call you with other options, or you can cancel the booking.'
          : 'You declined the new price. We’ll call you about your phone.',
      RepairStatus.requested => 'We’ll call to confirm your slot.',
      RepairStatus.confirmed => b.quoteStatus == RepairQuoteStatus.approved
          ? 'Price approved. We’ll start the repair soon.'
          : 'Bring your phone in at your slot. We’ll check it and send you the price here.',
      RepairStatus.inProgress => 'Our technician is on it.',
      RepairStatus.ready => 'Pick it up from the store.',
      RepairStatus.completed => 'All done. Thanks for coming in.',
      RepairStatus.cancelled => 'This booking is cancelled.',
    };

class RepairDetailScreen extends ConsumerStatefulWidget {
  const RepairDetailScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<RepairDetailScreen> createState() => _RepairDetailScreenState();
}

class _RepairDetailScreenState extends ConsumerState<RepairDetailScreen> {
  bool _busy = false;

  /// One action at a time, its dialog included, so a double tap can't open two or write twice.
  Future<void> _once(Future<void> Function() flow) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await flow();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Runs [write], says [done], and reloads the booking and the list either way (a refusal means it changed).
  Future<void> _write(String done, Future<void> Function(SupabaseClient db) write) async {
    // The container outlives this screen: the lists still refresh if the customer goes back mid-call.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await write(container.read(supabaseProvider));
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      container
        ..invalidate(repairProvider(widget.bookingId))
        ..invalidate(myRepairsProvider);
    }
  }

  Future<void> _cancel() async {
    final ok = await confirmChoice(
      context,
      title: 'Cancel this booking?',
      message: 'Your slot will be released. You can book again any time.',
      action: 'Cancel booking',
      keep: 'Keep booking',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _write('Booking cancelled', (db) => cancelRepair(db, widget.bookingId));
  }

  Future<void> _approve(RepairBooking b) async {
    final quote = formatInr(b.quotePaise!);
    final ok = await confirmChoice(
      context,
      title: 'Approve $quote?',
      message: 'We’ll go ahead with the repair at this price. If we find anything else, we’ll ask you again first.',
      action: 'Approve',
      keep: 'Not now',
    );
    if (!ok || !mounted) return;
    await _write('Price approved', (db) => approveRepairQuote(db, b));
  }

  Future<void> _decline(RepairBooking b) async {
    final reason = await askReason(
      context,
      title: 'Decline ${formatInr(b.quotePaise!)}?',
      message: 'We won’t do the work at this price. We’ll call you with other options.',
      action: 'Decline',
      keep: 'Keep quote',
      label: 'Reason (optional)',
      optional: true,
      maxLength: 300,
    );
    if (reason == null || !mounted) return;
    await _write('Declined. We’ll call you.', (db) => declineRepairQuote(db, b.id, reason));
  }

  @override
  Widget build(BuildContext context) {
    final provider = repairProvider(widget.bookingId);
    final value = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(value.value == null ? 'Repair' : 'Repair ${value.value!.number}')),
      body: AsyncBody<RepairBooking>(
        value: value,
        onRetry: () => ref.invalidate(provider),
        loading: Skeletonizer(child: _Body(booking: skeletonBookings.first, busy: true)),
        data: (b) => RefreshIndicator(
          onRefresh: () => ref.refresh(provider.future),
          child: _Body(
            booking: b,
            busy: _busy,
            onCancel: () => _once(_cancel),
            onApprove: () => _once(() => _approve(b)),
            onDecline: () => _once(() => _decline(b)),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.booking, required this.busy, this.onCancel, this.onApprove, this.onDecline});

  final RepairBooking booking;
  final bool busy;
  final VoidCallback? onCancel;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final b = booking;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.xl + MediaQuery.paddingOf(context).bottom),
      children: [
        RepairStatusHero(booking: b),
        if (b.quotePaise != null) ...[
          const SizedBox(height: Space.md),
          _QuoteCard(booking: b, busy: busy, onApprove: onApprove, onDecline: onDecline),
        ],
        if (b.status != RepairStatus.cancelled) ...[
          const SizedBox(height: Space.lg),
          RepairTimeline(booking: b),
        ],
        if (b.status == RepairStatus.completed) ...[
          const SizedBox(height: Space.md),
          RateCard(title: 'How was your repair?', repairId: b.id),
        ],
        const ListSection('Details'),
        Card(
          child: Column(
            children: [
              InfoRow('Phone', '${b.deviceBrand} ${b.deviceModel}'),
              InfoRow('Issue', b.issue.label),
              if (b.description.isNotEmpty) InfoRow('Notes', b.description),
              InfoRow('Slot', '${repairWhen(b)} (${b.slot.hours})'),
              InfoRow('Contact', displayPhone(b.contactPhone)),
              if (b.quotePaise == null) const InfoRow('Quote', 'After inspection'),
            ],
          ),
        ),
        if (b.events.isNotEmpty) ...[
          const ListSection('Updates'),
          RepairHistory(events: b.events),
        ],
        const SizedBox(height: Space.lg),
        StoreContactButtons(message: 'Hi, about repair ${b.number}'),
        if (b.canCancel) ...[
          const SizedBox(height: Space.sm),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: c.error),
            onPressed: busy ? null : onCancel,
            icon: const Icon(PhosphorIconsRegular.xCircle),
            label: const Text('Cancel booking'),
          ),
        ],
        const SizedBox(height: Space.sm),
        Text(
          'Booked ${formatDateTime(b.createdAt)}',
          textAlign: TextAlign.center,
          style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The quote and, while it waits for the customer, Decline and Approve.
class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.booking, required this.busy, this.onApprove, this.onDecline});

  final RepairBooking booking;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final b = booking;
    final decided = b.quoteDecidedAt == null ? '' : ' on ${formatDate(b.quoteDecidedAt!)}';
    final line = switch (b.quoteStatus) {
      _ when b.awaitingApproval => 'Work starts only after you approve this price.',
      RepairQuoteStatus.approved => 'Price approved$decided.',
      RepairQuoteStatus.declined => 'You declined this price$decided.',
      _ => 'This price wasn’t approved.',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Quote', style: t.labelMedium?.copyWith(color: c.onSurfaceVariant)),
            Text(
              formatInr(b.quotePaise!),
              style: t.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(line, style: t.bodySmall),
            if (b.awaitingApproval) ...[
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: busy ? null : onDecline, child: const Text('Decline')),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: FilledButton(onPressed: busy ? null : onApprove, child: const Text('Approve')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Indigo status card with a serif headline (mockup 6 `.status-hero`). Shared with the admin detail.
class RepairStatusHero extends StatelessWidget {
  const RepairStatusHero({super.key, required this.booking});

  final RepairBooking booking;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final colors = switch (booking.status) {
      RepairStatus.cancelled => (bg: c.surfaceContainerHighest, fg: c.onSurface),
      RepairStatus.ready => toneColors(c, TagTone.ok),
      _ => toneColors(c, TagTone.info),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              booking.number,
              style: t.labelSmall?.copyWith(color: colors.fg, letterSpacing: 1),
            ),
            const SizedBox(height: Space.xs),
            Semantics(
              header: true,
              child: Text(booking.status.label, style: t.displaySmall?.copyWith(color: colors.fg)),
            ),
            const SizedBox(height: Space.xs),
            Text(
              '${repairWhen(booking)} · ${booking.slot.hours}',
              style: t.bodySmall?.copyWith(color: colors.fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// Requested → Confirmed → In repair → Ready → Completed (mockup 6 `.tl`), each done step with when it happened
/// (from repair_events) and, under the current one, what happens next ([hint]; staff turn it off).
class RepairTimeline extends StatelessWidget {
  const RepairTimeline({super.key, required this.booking, this.hint = true});

  final RepairBooking booking;
  final bool hint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final current = _steps.indexOf(booking.status);
    DateTime? reached(RepairStatus s) =>
        booking.events.where((e) => e.status == s && e.quoteStatus == null).firstOrNull?.createdAt;
    return Column(
      children: [
        for (final (i, s) in _steps.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: i <= current ? c.secondary : c.surfaceContainer,
                          shape: BoxShape.circle,
                          border: i <= current ? null : Border.all(color: c.outlineVariant, width: 2),
                        ),
                        child: SizedBox.square(
                          dimension: 28,
                          child: i <= current
                              ? Icon(PhosphorIconsBold.check, size: 15, color: c.onSecondary)
                              : null,
                        ),
                      ),
                      if (i < _steps.length - 1)
                        Expanded(
                          child: Container(width: 2, color: i < current ? c.secondary : c.outlineVariant),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: Space.lg),
                    child: Semantics(
                      label: '${s.label}, ${i <= current ? 'done' : 'not yet'}',
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.label,
                            style: t.titleSmall?.copyWith(color: i <= current ? c.onSurface : c.onSurfaceVariant),
                          ),
                          if (i <= current && reached(s) != null)
                            Text(formatDateTime(reached(s)!), style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                          if (hint && i == current)
                            Text(repairStepCopy(booking), style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Every timeline entry, newest first: steps, quotes and their answers, notes. Shared with the admin detail.
class RepairHistory extends StatelessWidget {
  const RepairHistory({super.key, required this.events});

  final List<RepairEvent> events; // oldest first

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = events.length - 1; i >= 0; i--)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Icon(PhosphorIconsFill.circle, size: 8, color: c.secondary),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(repairEventTitle(events[i], i == 0 ? null : events[i - 1]), style: t.titleSmall),
                      if (events[i].note != null) Text(events[i].note!, style: t.bodySmall),
                      Text(formatDateTime(events[i].createdAt), style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
