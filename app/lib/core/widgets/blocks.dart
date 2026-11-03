import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/models.dart';
import '../supabase.dart';
import '../theme/tokens.dart';
import 'widgets.dart';

// Shared blocks for every screen: the tone table, notes, the sticky bar, list headers, the shop's contact links and
// the returns sheet. Import this file directly (it began as copies in features/repairs/widgets).

/// A [TagTone]'s background and text colour: the one table behind tags, notes, tinted cards and status heroes.
Tint toneColors(TagTone t) => switch (t) {
      TagTone.info => (BrandColors.peacockMist, BrandColors.peacockInk),
      TagTone.ok => (BrandColors.mint, BrandColors.mintInk),
      TagTone.deal => (BrandColors.goldSoft, BrandColors.goldInk), // never solid gold under text
      TagTone.repair => (BrandColors.cream, BrandColors.creamInk),
      TagTone.neutral => (lightScheme.surfaceContainerHigh, BrandColors.graphite),
      TagTone.bad => (lightScheme.errorContainer, lightScheme.onErrorContainer),
    };

/// Tinted info box (mockup `.note`).
class NoteBox extends StatelessWidget {
  const NoteBox(this.text, {super.key, this.tone = TagTone.deal, this.icon = PhosphorIconsFill.info});

  final String text;
  final TagTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(tone);
    return DecoratedBox(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.md)),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: Space.sm),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg))),
          ],
        ),
      ),
    );
  }
}

/// Bottom action bar for pushed screens (Add to cart, Checkout, Book); keeps clear of the gesture / nav bar.
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

/// [SectionHeader] for lists that already have side padding (detail cards, admin forms).
class ListSection extends StatelessWidget {
  const ListSection(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SectionHeader(title, inset: false, trailing: trailing);
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

/// The returns & warranty policy from the shop's settings, in a sheet (product page, Account).
void showReturnsSheet(BuildContext context, StoreSettings settings) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Returns & warranty', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: Space.md),
              Text(settings.returnsPolicy, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );

// Store links ---------------------------------------------------------------------------------------------------

Uri telUri(String e164) => Uri(scheme: 'tel', path: e164);

/// wa.me chat with [phone] (any format: digits are kept), optionally prefilled with [text]. Spaces as %20, not +.
Uri whatsAppUri(String phone, {String? text}) => Uri.parse(
      'https://wa.me/${phone.replaceAll(RegExp(r'\D'), '')}${text == null ? '' : '?text=${Uri.encodeComponent(text)}'}',
    );

/// Opens [uri] in another app; says which app couldn't open when nothing could.
Future<void> openUri(BuildContext context, Uri uri) async {
  if (await launchExternal(uri) || !context.mounted) return;
  final what = switch (uri) {
    Uri(scheme: 'tel') => 'the phone app',
    Uri(host: 'wa.me') => 'WhatsApp',
    Uri(host: final h) when h.contains('google') => 'Google Maps',
    _ => 'that on this phone',
  };
  showMessage(context, 'Couldn’t open $what.');
}

/// "WhatsApp" next to "Call shop", from store_settings.store_phone, wherever there's a person to ask.
class StoreContactButtons extends ConsumerWidget {
  const StoreContactButtons({super.key, required this.message});

  final String message; // prefilled WhatsApp text, e.g. "Hi, about repair RP100012"

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = ref.watch(storeSettingsProvider).value?.storePhone;
    return Row(
      spacing: Space.sm,
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: phone == null ? null : () => openUri(context, whatsAppUri(phone, text: message)),
            icon: const WhatsAppIcon(),
            label: const Text('WhatsApp'),
          ),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: phone == null ? null : () => openUri(context, telUri(phone)),
            icon: const Icon(PhosphorIconsRegular.phone),
            label: const Text('Call shop'),
          ),
        ),
      ],
    );
  }
}
