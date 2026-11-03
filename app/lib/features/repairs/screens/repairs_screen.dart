import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/models/models.dart';
import '../../../core/paging.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/widgets.dart';
import '../../account/widgets/store_card.dart';
import '../data/repairs.dart';
import '../widgets/repair_widgets.dart';

// Promises the owner hasn't confirmed yet ("Your old part is given back to you", "Repair warranty: N days", same day,
// GST bill) stay out of this page until they do.

/// Opens the booking form, with [issue] already picked. Signed out, the router asks to sign in first and comes back.
void _book(BuildContext context, [RepairIssue? issue]) =>
    context.push(issue == null ? '/repairs/new' : '/repairs/new?issue=${issue.value}');

/// The Repairs tab sells the service to everyone, signed in or not: what we fix, how it works, the promise and the
/// shop. Your bookings come first when you have some.
class RepairsScreen extends ConsumerWidget {
  const RepairsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(currentUserIdProvider) != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Repairs')),
      body: !signedIn
          ? const _Page(bookings: [])
          : AsyncBody<Paged<RepairBooking>>(
              value: ref.watch(myRepairsProvider),
              onRetry: () => ref.invalidate(myRepairsProvider),
              loading: Skeletonizer(child: _Page(bookings: skeletonBookings)),
              data: (page) => RefreshIndicator(
                onRefresh: () => ref.refresh(myRepairsProvider.future),
                child: LoadMoreListener(
                  hasMore: page.hasMore,
                  onMore: ref.read(myRepairsProvider.notifier).loadMore,
                  child: _Page(
                    bookings: page.items,
                    footer: page.hasMore
                        ? PagedFooter(
                            failed: page.moreFailed,
                            onRetry: () => ref.read(myRepairsProvider.notifier).loadMore(retry: true),
                            what: 'more repairs',
                          )
                        : null,
                  ),
                ),
              ),
            ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.bookings, this.footer});

  final List<RepairBooking> bookings;
  final Widget? footer; // the next page's spinner or retry

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          if (bookings.isEmpty)
            const _Hero()
          else ...[
            const SectionHeader('Your bookings'),
            for (final b in bookings)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
                child: RepairCard(booking: b, onTap: () => context.push('/repairs/${b.id}')),
              ),
            ?footer,
            const _BookAnother(),
          ],
          const SectionHeader('What we fix'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: IssueGrid(selected: null, onSelected: (issue) => _book(context, issue)),
          ),
          const SectionHeader('How it works'),
          const _Steps(),
          const SectionHeader('Our promise'),
          const _Promise(),
          const SectionHeader('Visit the shop'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Space.lg),
            child: StoreCard(whatsAppText: 'Hi, I have a question about a repair'),
          ),
        ],
      );
}

/// The pitch at the top: what we do, the promise in one line, and the two ways to start.
class _Hero extends ConsumerWidget {
  const _Hero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final phone = ref.watch(storeSettingsProvider).value?.storePhone;
    final (bg, fg) = Worlds.repairs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.hero)),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(PhosphorIconsFill.wrench, color: fg, size: IconSizes.lg),
              const SizedBox(height: Space.sm),
              Semantics(
                header: true,
                child: Text('Phone repair at Shyam Mobiles', style: t.displaySmall?.copyWith(fontSize: 22, color: BrandColors.creamInk)),
              ),
              const SizedBox(height: Space.xs),
              Text(
                'We check your phone, tell you the price, and start only after you say yes.',
                style: t.bodyMedium?.copyWith(color: BrandColors.creamInk),
              ),
              const SizedBox(height: Space.lg),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: c.tertiary, foregroundColor: c.onTertiary),
                onPressed: () => _book(context),
                icon: const Icon(PhosphorIconsRegular.wrench),
                label: const Text('Book a repair · Free'),
              ),
              if (phone != null) ...[
                const SizedBox(height: Space.sm),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(backgroundColor: c.surface),
                  onPressed: () => openUri(context, whatsAppUri(phone, text: 'Hi, my phone has a problem. Photo attached.')),
                  icon: const WhatsAppIcon(),
                  label: const Text('Send a photo on WhatsApp'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact Book button under your bookings.
class _BookAnother extends StatelessWidget {
  const _BookAnother();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, 0),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: c.tertiary, foregroundColor: c.onTertiary),
        onPressed: () => _book(context),
        icon: const Icon(PhosphorIconsRegular.wrench),
        label: const Text('Book a repair · Free'),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  static const _steps = [
    ('Book a time', 'It’s free, no payment now.'),
    ('Bring your phone', 'We check it and send the price to this app.'),
    ('Say yes and we repair it', 'Pay when you pick it up.'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final (bg, fg) = Worlds.repairs;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Column(
        children: [
          for (final (i, (title, line)) in _steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                      child: SizedBox.square(
                        dimension: 32,
                        child: Center(child: Text('${i + 1}', style: t.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w800))),
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: t.titleSmall),
                          Text(line, style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise();

  // only what the app itself guarantees; see the note at the top of this file
  static const _lines = [
    (PhosphorIconsRegular.handshake, 'No surprise price: work starts only after you approve'),
    (PhosphorIconsRegular.calendarCheck, 'Booking is free: cancel any time before the repair starts'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Column(
        children: [
          for (final (icon, text) in _lines)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(
                children: [
                  IconWell(icon, tint: Worlds.cart), // emerald: a promise kept is a success colour
                  const SizedBox(width: Space.md),
                  Expanded(child: Text(text, style: t.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
