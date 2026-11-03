import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';

TagTone repairTone(RepairStatus s) => switch (s) {
      RepairStatus.requested => TagTone.repair,
      RepairStatus.confirmed || RepairStatus.inProgress => TagTone.info,
      RepairStatus.ready => TagTone.ok,
      RepairStatus.completed => TagTone.ok,
      RepairStatus.cancelled => TagTone.neutral,
    };

const issueIcons = <RepairIssue, IconData>{
  RepairIssue.screen: PhosphorIconsRegular.deviceMobileSlash,
  RepairIssue.battery: PhosphorIconsRegular.batteryWarning,
  RepairIssue.charging: PhosphorIconsRegular.plug,
  RepairIssue.camera: PhosphorIconsRegular.camera,
  RepairIssue.audio: PhosphorIconsRegular.speakerHigh,
  RepairIssue.waterDamage: PhosphorIconsRegular.drop,
  RepairIssue.software: PhosphorIconsRegular.gear,
  RepairIssue.other: PhosphorIconsRegular.dotsThreeCircle,
};

/// 4-column grid of what we fix (mockup `.issues`): the booking form's picker, and the Repairs tab's way in. Tiles
/// grow with text scale instead of clipping.
class IssueGrid extends StatelessWidget {
  const IssueGrid({super.key, required this.selected, required this.onSelected});

  final RepairIssue? selected;
  final ValueChanged<RepairIssue> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - Space.sm * 3) / 4;
        return Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final issue in RepairIssue.values)
              Builder(builder: (context) {
                final on = issue == selected;
                final fg = on ? c.onPrimary : c.onSurface;
                return SizedBox(
                  width: width,
                  child: Semantics(
                    selected: on,
                    button: true,
                    child: Material(
                      color: on ? c.primary : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.button),
                        side: on ? BorderSide.none : BorderSide(color: c.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onSelected(issue),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 76),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.sm),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(issueIcons[issue], size: IconSizes.lg, color: on ? fg : BrandColors.saffron),
                                const SizedBox(height: Space.xs),
                                Text(
                                  issue.label,
                                  textAlign: TextAlign.center,
                                  style: t.labelSmall?.copyWith(color: fg, height: 1.15),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

/// "Thu 30 Oct · Afternoon"
String repairWhen(RepairBooking b) => '${DateFormat('EEE d MMM').format(b.preferredDate)} · ${b.slot.label}';

/// Mockup chip: outlined, indigo-tinted when selected, 48dp tap target.
class PickChip extends StatelessWidget {
  const PickChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: c.primaryContainer,
      side: selected ? BorderSide.none : BorderSide(color: c.outlineVariant),
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(color: selected ? c.onPrimaryContainer : c.onSurface),
    );
  }
}

/// Horizontally scrolling row of [PickChip]s keyed by value.
class ChipBar extends StatelessWidget {
  const ChipBar({super.key, required this.options, required this.selected, required this.onSelected});

  final Map<String, String> options; // value → label
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        child: Row(
          children: [
            for (final e in options.entries)
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: PickChip(label: e.value, selected: e.key == selected, onTap: () => onSelected(e.key)),
              ),
          ],
        ),
      );
}

/// List card for a booking; used by the customer list and the admin list.
class RepairCard extends StatelessWidget {
  const RepairCard({super.key, required this.booking, required this.onTap, this.showPhone = false});

  final RepairBooking booking;
  final VoidCallback onTap;
  final bool showPhone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final b = booking;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: c.surfaceContainer, borderRadius: BorderRadius.circular(Radii.md)),
                child: SizedBox.square(
                  dimension: 44,
                  child: Icon(issueIcons[b.issue], color: c.onSurfaceVariant, size: 22),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(b.number, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Tag(b.status.label, tone: repairTone(b.status)),
                        if (b.awaitingApproval) const Tag('Awaiting approval', tone: TagTone.deal),
                        if (b.quoteDeclined) const Tag('Quote declined', tone: TagTone.neutral),
                      ],
                    ),
                    const SizedBox(height: Space.xs),
                    Text('${b.deviceBrand} ${b.deviceModel} · ${b.issue.label}', style: t.bodyMedium),
                    Text(
                      [repairWhen(b), if (showPhone) displayPhone(b.contactPhone)].join(' · '),
                      style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (b.quotePaise != null) ...[
                const SizedBox(width: Space.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Quote', style: t.labelSmall?.copyWith(color: c.onSurfaceVariant)),
                    Text(
                      formatInr(b.quotePaise!),
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Title of a timeline entry: the quote event, the new status, or "Note" when the status didn't change.
String repairEventTitle(RepairEvent e, RepairEvent? before) => switch (e.quoteStatus) {
      RepairQuoteStatus.pending => 'Quote sent · ${formatInr(e.quotePaise!)}',
      RepairQuoteStatus.approved => 'Quote approved · ${formatInr(e.quotePaise!)}',
      RepairQuoteStatus.declined => 'Quote declined · ${formatInr(e.quotePaise!)}',
      _ => before == null || before.status != e.status ? e.status.label : 'Note from the shop',
    };

/// A destructive choice with a reason (decline a quote, cancel a booking): quiet red [action] on the left, the safe
/// [keep] filled on the right, as in confirmChoice. Returns the tidied reason ('' when [optional] and left blank),
/// or null when kept.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  required String keep,
  String label = 'Reason',
  bool optional = false,
  int maxLength = 200,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: title,
        message: message,
        action: action,
        keep: keep,
        label: label,
        optional: optional,
        maxLength: maxLength,
      ),
    );

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.action,
    required this.keep,
    required this.label,
    required this.optional,
    required this.maxLength,
  });

  final String title;
  final String message;
  final String action;
  final String keep;
  final String label;
  final bool optional;
  final int maxLength;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool missing() => !widget.optional && tidy(_reason.text).isEmpty; // read on tap: the last frame may predate typing
    return AlertDialog(
      scrollable: true, // the keyboard and large text can leave little room
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: Space.md),
          TextField(
            controller: _reason,
            autofocus: !widget.optional,
            inputFormatters: textInput(widget.maxLength),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: widget.label,
              errorText: _tried && missing() ? 'Add a short reason.' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => missing() ? setState(() => _tried = true) : Navigator.pop(context, tidy(_reason.text)),
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error, minimumSize: const Size(64, 44)),
          child: Text(widget.action),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          child: Text(widget.keep),
        ),
      ],
    );
  }
}

/// Label / value row for detail cards.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: Space.md),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: (strong ? t.titleSmall?.copyWith(fontWeight: FontWeight.w800) : t.bodyMedium)
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fake bookings for skeletons, so the skeleton matches the real card.
final skeletonBookings = [
  for (var i = 0; i < 4; i++)
    RepairBooking(
      id: '$i',
      number: 'RP100000',
      deviceBrand: 'Samsung',
      deviceModel: 'Galaxy S23',
      issue: RepairIssue.screen,
      preferredDate: DateTime(2026, 10, 30),
      slot: RepairSlot.afternoon,
      contactPhone: '+919999999999',
      status: RepairStatus.requested,
      createdAt: DateTime(2026, 10, 29),
    ),
];
