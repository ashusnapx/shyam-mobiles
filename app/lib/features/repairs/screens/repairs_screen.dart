import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/repairs.dart';
import '../widgets/repair_widgets.dart';

class RepairsScreen extends ConsumerWidget {
  const RepairsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(currentUserIdProvider) != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Repairs')),
      body: !signedIn
          ? const SignInPrompt(
              icon: PhosphorIconsRegular.wrench,
              title: 'Book a repair',
              message: 'Sign in to book a slot and track your repair.',
              from: '/repairs',
            )
          : AsyncBody<List<RepairBooking>>(
              value: ref.watch(myRepairsProvider),
              onRetry: () => ref.invalidate(myRepairsProvider),
              loading: Skeletonizer(child: _List(bookings: skeletonBookings)),
              data: (bookings) => bookings.isEmpty
                  ? EmptyState(
                      icon: PhosphorIconsRegular.wrench,
                      title: 'No repairs yet',
                      message: 'Pick a slot and bring your phone in. Booking is free.',
                      action: FilledButton.icon(
                        onPressed: () => context.push('/repairs/new'),
                        icon: const Icon(PhosphorIconsRegular.plus),
                        label: const Text('Book a repair'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => ref.refresh(myRepairsProvider.future),
                      child: _List(bookings: bookings),
                    ),
            ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.bookings});

  final List<RepairBooking> bookings;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          const _BookCta(),
          const SectionHeader('Your bookings'),
          for (final b in bookings)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
              child: RepairCard(booking: b, onTap: () => context.push('/repairs/${b.id}')),
            ),
        ],
      );
}

/// Peacock card from the home mockup's repair CTA.
class _BookCta extends StatelessWidget {
  const _BookCta();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.secondaryContainer, borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cracked screen? Weak battery?', style: t.titleMedium?.copyWith(color: c.onSecondaryContainer)),
              const SizedBox(height: Space.xs),
              Text(
                'Pick a slot and walk in. Booking is free.',
                style: t.bodySmall?.copyWith(color: c.onSecondaryContainer),
              ),
              const SizedBox(height: Space.md),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: c.secondary, foregroundColor: c.onSecondary),
                onPressed: () => context.push('/repairs/new'),
                icon: const Icon(PhosphorIconsRegular.wrench),
                label: const Text('Book a repair'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
