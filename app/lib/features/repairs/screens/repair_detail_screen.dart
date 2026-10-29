import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/repairs.dart';
import '../widgets/repair_widgets.dart';

const _steps = {
  RepairStatus.requested: 'We’ll call to confirm your slot.',
  RepairStatus.confirmed: 'Bring your phone in at your slot.',
  RepairStatus.inProgress: 'Our technician is on it.',
  RepairStatus.ready: 'Pick it up from the store.',
  RepairStatus.completed: 'All done. Thanks for coming in.',
};

class RepairDetailScreen extends ConsumerWidget {
  const RepairDetailScreen({super.key, required this.bookingId});

  final String bookingId;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text('Your slot will be released. You can book again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep booking')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel booking')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await cancelRepair(ref.read(supabaseProvider), bookingId);
      ref.invalidate(repairProvider(bookingId));
      ref.invalidate(myRepairsProvider);
      if (context.mounted) showMessage(context, 'Booking cancelled');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(repairProvider(bookingId));
    return Scaffold(
      appBar: AppBar(title: Text(value.value == null ? 'Repair' : 'Repair ${value.value!.number}')),
      body: AsyncBody<RepairBooking>(
        value: value,
        onRetry: () => ref.invalidate(repairProvider(bookingId)),
        loading: Skeletonizer(child: _Body(booking: skeletonBookings.first, onCancel: () {})),
        data: (b) => RefreshIndicator(
          onRefresh: () => ref.refresh(repairProvider(bookingId).future),
          child: _Body(booking: b, onCancel: () => _cancel(context, ref)),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.booking, required this.onCancel});

  final RepairBooking booking;
  final VoidCallback onCancel;

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
        if (b.status != RepairStatus.cancelled) ...[
          const SizedBox(height: Space.lg),
          RepairTimeline(status: b.status),
        ],
        if (b.adminNote != null && b.adminNote!.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          NoteBox('From the store: ${b.adminNote!}', tone: TagTone.info, icon: PhosphorIconsFill.chatText),
        ],
        if (b.quotePaise != null) ...[
          const SizedBox(height: Space.md),
          _QuoteCard(booking: b),
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
        const SizedBox(height: Space.lg),
        StoreContactButtons(message: 'Hi, about repair ${b.number}'),
        if (b.canCancel) ...[
          const SizedBox(height: Space.sm),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: c.error),
            onPressed: onCancel,
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

/// Quote with the approval promise; "Approve on WhatsApp" while the booking is confirmed.
class _QuoteCard extends ConsumerWidget {
  const _QuoteCard({required this.booking});

  final RepairBooking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final b = booking;
    final quote = formatInr(b.quotePaise!);
    final phone = ref.watch(storeSettingsProvider).value?.storePhone;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quote', style: t.labelMedium?.copyWith(color: c.onSurfaceVariant)),
            Text(
              quote,
              style: t.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: Space.xs),
            Text('Work starts only after you approve this price.', style: t.bodySmall),
            if (b.status == RepairStatus.confirmed && phone != null) ...[
              const SizedBox(height: Space.md),
              FilledButton.icon(
                onPressed: () =>
                    openUri(context, whatsAppUri(phone, text: 'I approve the quote of $quote for ${b.number}')),
                icon: const Icon(PhosphorIconsRegular.whatsappLogo),
                label: const Text('Approve on WhatsApp'),
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

/// Requested → Confirmed → In repair → Ready → Completed (mockup 6 `.tl`).
class RepairTimeline extends StatelessWidget {
  const RepairTimeline({super.key, required this.status});

  final RepairStatus status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final steps = _steps.keys.toList();
    final current = steps.indexOf(status);
    return Column(
      children: [
        for (final (i, s) in steps.indexed)
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
                      if (i < steps.length - 1)
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
                          if (i == current)
                            Text(_steps[s]!, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
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
