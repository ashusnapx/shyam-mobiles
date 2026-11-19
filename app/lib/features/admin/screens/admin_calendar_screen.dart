import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../offers/data/offers.dart' show availableOffersProvider;
import '../../offers/widgets/offer_widgets.dart' show valueHeadline;
import '../data/campaign_calendar.dart';
import '../data/offers_admin.dart';
import '../widgets/admin_widgets.dart';

/// The dot colour of each kind of day. Never red: red means an error here.
Color eventColor(EventKind k) => switch (k) {
      EventKind.holiday => BrandColors.saffron,
      EventKind.observance => BrandColors.indigo,
      EventKind.shopDay => BrandColors.plum,
      EventKind.season => BrandColors.slate,
    };

const _kindLabel = {
  EventKind.holiday: 'Public holiday',
  EventKind.observance: 'Observance',
  EventKind.shopDay: 'Shop day',
  EventKind.season: 'Season',
};

const _offerBar = BrandColors.emerald;
final _first = DateTime(2025);

/// Admin → Settings → Campaign calendar: festivals, shop days and seasons on a month grid with the offers running each
/// day, an agenda per day ("Create offer" prefills the offer editor), and the next 45 days below.
class AdminCalendarScreen extends ConsumerStatefulWidget {
  const AdminCalendarScreen({super.key});

  @override
  ConsumerState<AdminCalendarScreen> createState() => _AdminCalendarScreenState();
}

class _AdminCalendarScreenState extends ConsumerState<AdminCalendarScreen> {
  late final DateTime _today = istToday(ref.read(calendarNowProvider));
  late final _pages = PageController(initialPage: _index(_today));
  late int _page = _index(_today);
  bool _seasons = true;

  int _index(DateTime d) => (d.year - _first.year) * 12 + d.month - 1;
  DateTime _month(int i) => DateTime(_first.year + i ~/ 12, i % 12 + 1);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) => MediaQuery.disableAnimationsOf(context)
      ? _pages.jumpToPage(_page + delta)
      : _pages.animateToPage(_page + delta, duration: Motion.normal, curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(campaignEventsProvider(_seasons)).value ?? const <CalendarEvent>[];
    final offers = ref.watch(adminPromotionsProvider).value ?? const <Promotion>[];
    final t = Theme.of(context).textTheme;
    final month = _month(_page);
    final cell = math.max(52.0, MediaQuery.textScalerOf(context).scale(16) + 36);
    final upcoming = [
      for (final e in events)
        if (!e.end.isBefore(_today) && e.start.difference(_today).inDays <= 45) e,
    ];
    return AdminGate(
      child: Scaffold(
        appBar: AppBar(title: const Text('Campaign calendar')),
        body: ListView(
          padding: EdgeInsets.only(bottom: Space.xxl + MediaQuery.paddingOf(context).bottom),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.lg, 0),
              child: Row(
                children: [
                  IconButton(tooltip: 'Previous month', onPressed: _page > 0 ? () => _go(-1) : null, icon: const Icon(PhosphorIconsRegular.caretLeft)),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(DateFormat('MMMM y').format(month), textAlign: TextAlign.center, style: t.titleMedium),
                    ),
                  ),
                  IconButton(tooltip: 'Next month', onPressed: () => _go(1), icon: const Icon(PhosphorIconsRegular.caretRight)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Row(
                children: [
                  for (final d in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                    Expanded(child: ExcludeSemantics(child: Text(d, textAlign: TextAlign.center, style: t.labelSmall))),
                ],
              ),
            ),
            SizedBox(
              height: cell * 6 + Space.sm, // six weeks at most; a fixed height keeps the swipe steady
              child: PageView.builder(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _MonthGrid(
                  month: _month(i),
                  today: _today,
                  cell: cell,
                  events: events,
                  offers: offers,
                  onDay: (d) => showDaySheet(context, d, events: events),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Wrap(
                spacing: Space.md,
                runSpacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final k in [EventKind.holiday, EventKind.observance, EventKind.shopDay]) _Legend(color: eventColor(k), label: _kindLabel[k]!),
                  const _Legend(color: _offerBar, label: 'Offer on', bar: true),
                  FilterChip(
                    label: const Text('Shop seasons'),
                    selected: _seasons,
                    onSelected: (v) => setState(() => _seasons = v),
                  ),
                ],
              ),
            ),
            const SectionHeader('Upcoming: next 45 days'),
            if (upcoming.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(horizontal: Space.lg), child: Text('Nothing in the next 45 days.')),
            for (final e in upcoming)
              _UpcomingTile(event: e, today: _today, planned: _planned(offers, e), onTap: () => showDaySheet(context, e.start, events: events)),
          ],
        ),
      ),
    );
  }

  static bool _planned(List<Promotion> offers, CalendarEvent e) {
    for (var d = e.start; !d.isAfter(e.end); d = DateTime(d.year, d.month, d.day + 1)) {
      if (offersOn(offers, d).isNotEmpty) return true;
    }
    return false;
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.bar = false});

  final Color color;
  final String label;
  final bool bar;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: bar ? 14 : 8,
            height: bar ? 3 : 8,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: Space.xs),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}

/// Mon–Sun weeks; each day a 48 dp+ button with its number (today ringed), a dot per event and a green bar per offer.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.today, required this.cell, required this.events, required this.offers, required this.onDay});

  final DateTime month;
  final DateTime today;
  final double cell;
  final List<CalendarEvent> events;
  final List<Promotion> offers;
  final ValueChanged<DateTime> onDay;

  @override
  Widget build(BuildContext context) {
    final lead = month.weekday - 1;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final weeks = (days + lead + 6) ~/ 7;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Column(
        children: [
          for (var w = 0; w < weeks; w++)
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: switch (w * 7 + i - lead + 1) {
                      final n when n >= 1 && n <= days => DayCell(
                          day: DateTime(month.year, month.month, n),
                          today: today,
                          height: cell,
                          events: [for (final e in events) if (e.kind != EventKind.season && e.covers(DateTime(month.year, month.month, n))) e],
                          offers: offersOn(offers, DateTime(month.year, month.month, n)).length,
                          onTap: onDay,
                        ),
                      _ => SizedBox(height: cell),
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class DayCell extends StatelessWidget {
  const DayCell({super.key, required this.day, required this.today, required this.height, required this.events, required this.offers, required this.onTap});

  final DateTime day;
  final DateTime today;
  final double height;
  final List<CalendarEvent> events; // seasons left out: they'd colour weeks at a time
  final int offers;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final isToday = day == today;
    final label = [
      DateFormat('EEEE d MMMM').format(day),
      if (isToday) 'today',
      ...events.map((e) => e.name),
      if (offers > 0) '$offers offer${offers == 1 ? '' : 's'} on' else if (events.any((e) => e.big)) 'no offer planned',
    ].join(', ');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () => onTap(day),
        child: SizedBox(
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: isToday ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.primary, width: 2)) : null,
                child: Text('${day.day}',
                    style: t.bodyMedium?.copyWith(fontWeight: isToday || events.any((e) => e.big) ? FontWeight.w800 : FontWeight.w400)),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final e in events.take(3))
                    Container(
                      key: ValueKey('dot ${e.name}'),
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(color: eventColor(e.kind), shape: BoxShape.circle),
                    ),
                ],
              ),
              for (var i = 0; i < math.min(offers, 2); i++)
                Container(
                  key: ValueKey('bar $i'),
                  width: 20,
                  height: 3,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(color: _offerBar, borderRadius: BorderRadius.circular(2)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({required this.event, required this.today, required this.planned, required this.onTap});

  final CalendarEvent event;
  final DateTime today;
  final bool planned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final days = event.start.difference(today).inDays;
    final when = days <= 0 ? (event.end == event.start ? 'today' : 'on now') : inDays(days);
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(radius: 6, backgroundColor: eventColor(event.kind)),
      title: Text(event.name, style: event.big ? const TextStyle(fontWeight: FontWeight.w700) : null),
      subtitle: Text([
        DateFormat('EEE d MMM').format(event.start),
        if (event.end != event.start) 'to ${DateFormat('d MMM').format(event.end)}',
        when,
        _kindLabel[event.kind]!,
      ].join(' · ')),
      trailing: planned
          ? const Tag('Offer planned', tone: TagTone.ok, icon: PhosphorIconsBold.check)
          : event.big
              ? Text('No offer', style: TextStyle(color: c.onSurfaceVariant))
              : null,
    );
  }
}

/// The day's agenda: its events (each with "Create offer") and the offers on that day (edit, pause or resume, delete).
Future<void> showDaySheet(BuildContext context, DateTime day, {required List<CalendarEvent> events}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DaySheet(day: day, events: [for (final e in events) if (e.covers(day)) e]),
    );

class DaySheet extends ConsumerStatefulWidget {
  const DaySheet({super.key, required this.day, required this.events});

  final DateTime day;
  final List<CalendarEvent> events;

  @override
  ConsumerState<DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends ConsumerState<DaySheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() write, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write();
      ref
        ..invalidate(adminPromotionsProvider)
        ..invalidate(availableOffersProvider);
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
    final offers = offersOn(ref.watch(adminPromotionsProvider).value ?? const [], widget.day);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(DateFormat('EEEE, d MMMM').format(widget.day), style: t.titleLarge)),
          const SizedBox(height: Space.sm),
          if (widget.events.isEmpty) Text('No festival or shop day.', style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
          for (final e in widget.events)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 6, backgroundColor: eventColor(e.kind)),
              title: Text(e.name),
              subtitle: Text(_kindLabel[e.kind]!),
              trailing: FilledButton.tonal(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/admin/offers/new', extra: draftFor(e));
                },
                child: const Text('Create offer'),
              ),
            ),
          const SectionHeader('Offers on this day', inset: false),
          if (offers.isEmpty) Text('No offer on this day.', style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
          for (final p in offers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(PhosphorIconsRegular.sealPercent, color: _offerBar),
              title: Text(p.title),
              subtitle: Text([
                if (p.code != null) p.code!,
                valueHeadline(p.kind, p.value),
                if (p.autoApply) 'applies itself',
              ].join(' · ')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit ${p.title}',
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/admin/offers/${p.id}');
                    },
                    icon: const Icon(PhosphorIconsRegular.pencilSimple),
                  ),
                  IconButton(
                    tooltip: 'Pause ${p.title}',
                    onPressed: _busy ? null : () => _run(() => ref.read(adminOffersApiProvider).savePromotion({'id': p.id, 'is_active': false}), 'Offer paused'),
                    icon: const Icon(PhosphorIconsRegular.pause),
                  ),
                  if (p.uses == 0)
                    IconButton(
                      tooltip: 'Delete ${p.title}',
                      onPressed: _busy
                          ? null
                          : () async {
                              final ok = await confirmChoice(
                                context,
                                title: 'Delete “${p.title}”?',
                                message: 'Nobody has used it yet, so it goes for good, with its banner.',
                                action: 'Delete',
                                keep: 'Keep offer',
                                destructive: true,
                              );
                              if (ok) await _run(() => ref.read(adminOffersApiProvider).deletePromotion(p.id!), 'Offer deleted');
                            },
                      icon: const Icon(PhosphorIconsRegular.trash),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The dashboard's nudge: "Next: Men’s Day today · no offer planned", only for a big event ≤ 7 days away with no
/// offer on any of its days. Tapping opens the calendar.
class NextEventCard extends ConsumerWidget {
  const NextEventCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(campaignEventsProvider(false)).value;
    final offers = ref.watch(adminPromotionsProvider).value;
    if (events == null || offers == null) return const SizedBox.shrink();
    final next = nextUnplanned(events, offers, ref.watch(calendarNowProvider));
    if (next == null) return const SizedBox.shrink();
    final (bg, fg) = Worlds.offers;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
      child: Card(
        margin: EdgeInsets.zero,
        color: bg,
        child: ListTile(
          onTap: () => context.push('/admin/calendar'),
          leading: Icon(PhosphorIconsRegular.calendarStar, color: fg),
          title: Text('Next: ${next.event.name} ${inDays(next.days)}', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
          subtitle: Text('No offer planned. Tap to create one.', style: TextStyle(color: fg)),
          trailing: Icon(PhosphorIconsRegular.caretRight, color: fg, size: IconSizes.sm),
        ),
      ),
    );
  }
}
