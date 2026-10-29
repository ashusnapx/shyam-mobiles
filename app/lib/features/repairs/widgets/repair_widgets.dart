import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';

/// Container colours for a [TagTone] (same as the core [Tag]); used by notes and heroes.
({Color bg, Color fg}) toneColors(ColorScheme c, TagTone t) => switch (t) {
      TagTone.info => (bg: c.primaryContainer, fg: c.onPrimaryContainer),
      TagTone.ok => (bg: c.secondaryContainer, fg: c.onSecondaryContainer),
      TagTone.deal => (bg: c.tertiaryContainer, fg: c.onTertiaryContainer),
      TagTone.bad => (bg: c.errorContainer, fg: c.onErrorContainer),
    };

TagTone repairTone(RepairStatus s) => switch (s) {
      RepairStatus.requested => TagTone.deal,
      RepairStatus.confirmed || RepairStatus.inProgress => TagTone.info,
      RepairStatus.ready => TagTone.ok,
      RepairStatus.completed => TagTone.ok,
      RepairStatus.cancelled => TagTone.bad,
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

/// Bottom action bar for pushed screens; keeps clear of the gesture/nav bar (edge-to-edge).
class StickyBar extends StatelessWidget {
  const StickyBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.outlineVariant))),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
        child: child,
      ),
    );
  }
}

/// Small bold label above a form group (mockup `.label`).
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
        child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleSmall)),
      );
}

/// Tinted info box (mockup `.note`).
class NoteBox extends StatelessWidget {
  const NoteBox(this.text, {super.key, this.tone = TagTone.deal, this.icon = PhosphorIconsFill.info});

  final String text;
  final TagTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(Theme.of(context).colorScheme, tone);
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(Radii.md)),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: colors.fg),
            const SizedBox(width: Space.sm + 2),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.fg))),
          ],
        ),
      ),
    );
  }
}

Uri telUri(String e164) => Uri(scheme: 'tel', path: e164);

Uri whatsAppUri(String e164, {String? text}) =>
    Uri.https('wa.me', '/${e164.replaceAll('+', '')}', text == null ? null : {'text': text});

Future<void> openUri(BuildContext context, Uri uri) async {
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) showMessage(context, 'Couldn’t open that on this phone.');
}

/// "Ask on WhatsApp" and "Call store" buttons, from store_settings.store_phone.
class StoreContactButtons extends ConsumerWidget {
  const StoreContactButtons({super.key, required this.message});

  final String message; // prefilled WhatsApp text, e.g. "Hi, about repair RP100012"

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = ref.watch(storeSettingsProvider).value?.storePhone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: phone == null ? null : () => openUri(context, whatsAppUri(phone, text: message)),
          icon: const Icon(PhosphorIconsRegular.whatsappLogo),
          label: const Text('Ask on WhatsApp'),
        ),
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(
          onPressed: phone == null ? null : () => openUri(context, telUri(phone)),
          icon: const Icon(PhosphorIconsRegular.phone),
          label: const Text('Call store'),
        ),
      ],
    );
  }
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

/// Section title for already-padded lists.
class ListSection extends StatelessWidget {
  const ListSection(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
        child: Row(
          children: [
            Expanded(
              child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ),
            ?trailing,
          ],
        ),
      );
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
