import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart' show currentUserIdProvider, storeSettingsProvider;
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/blocks.dart' show openUri, whatsAppUri;
import '../../../core/widgets/widgets.dart';
import '../../admin/data/photos.dart' show preparePhoto, readPhoto;
import '../../admin/widgets/admin_widgets.dart' show pickPhoto;
import '../../catalog/data/catalog.dart' show productProvider;
import '../data/exchange_repository.dart';

/// "₹4,000–₹5,000", or one amount when both ends match.
String estimateRange(int low, int high) => low == high ? formatInr(low) : '${formatInr(low)}–${formatInr(high)}';

/// The WhatsApp text: what the customer picked, no price (the shop gives one).
String exchangeMessage({required String brand, required String model, required ExchangeAge age, required ExchangeCondition condition, String? forPhone}) =>
    [
      'Hi, I’d like to exchange my old phone${forPhone == null ? '' : ' for the $forPhone'}.',
      'Phone: ${[brand, model].where((s) => s.isNotEmpty).join(' ')}',
      'Age: ${age.label}',
      'Condition: ${condition.label} (${condition.hint.toLowerCase()})',
      'I’ll send photos here. What can you offer?',
    ].join('\n');

/// The phone page's and the cart's "Exchange your old phone" row: opens the sheet. Never shows a price.
class ExchangeCard extends StatelessWidget {
  const ExchangeCard({super.key, this.forProductId, this.forPhone});

  final String? forProductId;
  final String? forPhone; // the phone it's for, named in the WhatsApp text

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showExchangeSheet(context, forProductId: forProductId, forPhone: forPhone),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.arrowsLeftRight, size: IconSizes.lg, color: c.primary),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Exchange your old phone', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Tell us about it. The shop replies with an estimate.',
                        style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(PhosphorIconsRegular.caretRight, size: IconSizes.sm, color: c.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// The cart's [ExchangeCard], only when the cart holds a phone.
class ExchangeCartCard extends ConsumerWidget {
  const ExchangeCartCard({super.key, required this.slugs});

  final List<String> slugs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = [
      for (final s in slugs) ref.watch(productProvider(s)).value,
    ].where((p) => p?.category.kind == CategoryKind.phone).firstOrNull;
    if (phone == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
      child: ExchangeCard(forProductId: phone.id, forPhone: phone.name),
    );
  }
}

Future<void> showExchangeSheet(BuildContext context, {String? forProductId, String? forPhone}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ExchangeSheet(forProductId: forProductId, forPhone: forPhone),
    );

/// Brand, model, age and condition chips, up to 3 photos; "Send to the shop" saves it (Firebase builds), "Send on
/// WhatsApp" works everywhere. No price is shown or promised here (docs/GROWTH.md §2c).
class ExchangeSheet extends ConsumerStatefulWidget {
  const ExchangeSheet({super.key, this.forProductId, this.forPhone});

  final String? forProductId;
  final String? forPhone;

  @override
  ConsumerState<ExchangeSheet> createState() => _ExchangeSheetState();
}

class _ExchangeSheetState extends ConsumerState<ExchangeSheet> {
  final _brand = TextEditingController();
  final _model = TextEditingController();
  ExchangeAge? _age;
  ExchangeCondition? _condition;
  final _photos = <String>[];
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    super.dispose();
  }

  /// The form's answers, or null with [_error] set.
  ({String brand, String model, ExchangeAge age, ExchangeCondition condition})? _answers() {
    final brand = tidy(_brand.text), model = tidy(_model.text);
    final (age, condition) = (_age, _condition);
    final missing = [
      if (brand.isEmpty) 'the brand',
      if (model.isEmpty) 'the model',
      if (age == null) 'its age',
      if (condition == null) 'its condition',
    ];
    if (missing.isNotEmpty || age == null || condition == null) {
      setState(() => _error = 'Add ${missing.join(', ')}.');
      return null;
    }
    return (brand: brand, model: model, age: age, condition: condition);
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message : friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto() async {
    final uid = ref.read(currentUserIdProvider);
    final file = await pickPhoto(context);
    if (file == null || uid == null) return;
    await _run(() async {
      final key = await ref.read(exchangeRepositoryProvider).uploadPhoto(uid, await preparePhoto(await readPhoto(file)));
      if (mounted) setState(() => _photos.add(key));
    });
  }

  Future<void> _send() async {
    if (ref.read(currentUserIdProvider) == null) {
      final from = GoRouter.of(context).state.uri.toString();
      Navigator.pop(context);
      unawaited(context.push('/sign-in?from=${Uri.encodeComponent(from)}'));
      return;
    }
    final a = _answers();
    if (a == null) return;
    await _run(() async {
      await ref.read(exchangeRepositoryProvider).request(
            brand: a.brand,
            model: a.model,
            age: a.age,
            condition: a.condition,
            photos: _photos,
            forProductId: widget.forProductId,
          );
      if (!mounted) return;
      final router = GoRouter.of(context);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      showMessageOn(messenger, 'Sent. The shop will reply with an estimate.',
          action: SnackBarAction(label: 'View', onPressed: () => router.push('/repairs/exchanges')));
    });
  }

  void _whatsApp(String phone) {
    final a = _answers();
    if (a == null) return;
    openUri(context, whatsAppUri(phone, text: exchangeMessage(
      brand: a.brand, model: a.model, age: a.age, condition: a.condition, forPhone: widget.forPhone)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final enabled = ref.watch(exchangeRepositoryProvider).enabled;
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final shopPhone = ref.watch(storeSettingsProvider).value?.storePhone;
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
          child: Text(s, style: t.titleSmall),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Exchange your old phone', style: t.titleLarge)),
            Text(
              'The shop replies with an estimate. The final value is set when the shop checks the phone.',
              style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _brand,
              decoration: const InputDecoration(labelText: 'Brand', hintText: 'Samsung, Vivo, Redmi…'),
              textCapitalization: TextCapitalization.words,
              inputFormatters: textInput(40),
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _model,
              decoration: const InputDecoration(labelText: 'Model', hintText: 'Galaxy A12'),
              textCapitalization: TextCapitalization.words,
              inputFormatters: textInput(60),
            ),
            label('How old is it?'),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final a in ExchangeAge.values)
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text(a.label),
                    selected: _age == a,
                    onSelected: _busy ? null : (_) => setState(() => _age = a),
                  ),
              ],
            ),
            label('Condition'),
            RadioGroup<ExchangeCondition>(
              groupValue: _condition,
              onChanged: (v) {
                if (!_busy) setState(() => _condition = v);
              },
              child: Column(
                children: [
                  for (final k in ExchangeCondition.values)
                    RadioListTile<ExchangeCondition>(
                      contentPadding: EdgeInsets.zero,
                      value: k,
                      title: Text(k.label),
                      subtitle: Text(k.hint),
                    ),
                ],
              ),
            ),
            if (enabled && signedIn) ...[
              label('Photos (up to 3, optional)'),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final p in _photos)
                    Chip(
                      avatar: const Icon(PhosphorIconsRegular.image, size: 16),
                      label: Text('Photo ${_photos.indexOf(p) + 1}'),
                      onDeleted: _busy ? null : () => setState(() => _photos.remove(p)),
                      deleteButtonTooltipMessage: 'Remove photo',
                    ),
                  if (_photos.length < 3)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _addPhoto,
                      icon: const Icon(PhosphorIconsRegular.camera, size: 18),
                      label: Text(_photos.isEmpty ? 'Add photos' : 'Add another'),
                    ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Text(_error!, style: t.bodySmall?.copyWith(color: c.error)),
            ],
            const SizedBox(height: Space.md),
            if (enabled)
              FilledButton(
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(signedIn ? 'Send to the shop' : 'Sign in to send'),
              ),
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(
              onPressed: _busy || shopPhone == null ? null : () => _whatsApp(shopPhone),
              icon: const WhatsAppIcon(),
              label: const Text('Send on WhatsApp'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One request as the customer sees it: what they sent, and the shop's estimate once there is one.
class ExchangeRequestCard extends StatelessWidget {
  const ExchangeRequestCard(this.request, {super.key, this.trailing});

  final ExchangeRequest request;
  final Widget? trailing; // staff: Estimate

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final r = request;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.xs,
          children: [
            Row(
              children: [
                Expanded(child: Text('${r.brand} ${r.model}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                r.estimated ? const Tag('Estimate ready', tone: TagTone.ok) : const Tag('Waiting for the shop', tone: TagTone.neutral),
              ],
            ),
            Text('${r.age.label} · ${r.condition.label}${r.photos.isEmpty ? '' : ' · ${r.photos.length} photo${r.photos.length == 1 ? '' : 's'}'}'
                ' · ${formatDate(r.createdAt)}', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            if (r.estimated) ...[
              Text('About ${estimateRange(r.lowPaise!, r.highPaise!)}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              if (r.note.isNotEmpty) Text(r.note, style: t.bodyMedium),
              Text('An estimate: the final value is set when the shop checks the phone.',
                  style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            ],
            ?trailing,
          ],
        ),
      ),
    );
  }
}
