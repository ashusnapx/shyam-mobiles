import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/widgets.dart';
import '../../offers/data/packs.dart';
import '../data/admin.dart';
import '../data/offers_admin.dart';
import '../data/rules.dart';
import '../widgets/admin_widgets.dart';

/// "New pack offer": a phone bought with its glass, case and more gets X% off, automatically (no code). The owner
/// picks the phone categories, the accessory types the cart must hold, the percent and whether the phone is
/// discounted too. Priced by the server (admin_save_pack, private.pack_lines; Firebase savePromotion).
class AdminPackScreen extends ConsumerWidget {
  const AdminPackScreen({super.key, this.promotionId, this.copyOf});

  final String? promotionId; // null: a new pack
  final String? copyOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = promotionId ?? copyOf;
    final promotion = source == null
        ? const AsyncData<Promotion?>(null)
        : ref.watch(adminPromotionsProvider).whenData((l) => l.where((p) => p.id == source).firstOrNull);
    final categories = ref.watch(adminCategoriesProvider);
    final title = promotionId == null ? 'New pack offer' : 'Edit pack offer';
    final error = promotion.error ?? categories.error;
    return AdminGate(
      child: promotion.hasValue && categories.hasValue
          ? _PackForm(
              title: title,
              source: promotion.value,
              copy: copyOf != null,
              phoneCategories: [
                for (final c in categories.value!)
                  if (c.kind == CategoryKind.phone) c,
              ],
            )
          : Scaffold(
              appBar: AppBar(title: Text(title)),
              body: error != null
                  ? ErrorView(error: error, onRetry: () => ref.invalidate(adminPromotionsProvider))
                  : const PageSkeleton(),
            ),
    );
  }
}

class _PackForm extends ConsumerStatefulWidget {
  const _PackForm({required this.title, required this.source, required this.copy, required this.phoneCategories});

  final String title;
  final Promotion? source;
  final bool copy;
  final List<Category> phoneCategories;

  @override
  ConsumerState<_PackForm> createState() => _PackFormState();
}

class _PackFormState extends ConsumerState<_PackForm> {
  final _form = GlobalKey<FormState>();
  late final Promotion? _p = widget.source;
  late final bool _new = _p == null || widget.copy;
  late final _title = TextEditingController(text: _p?.title ?? 'Phone pack');
  late final _percent = TextEditingController(text: '${_p?.value ?? 10}');
  late final _cap = TextEditingController(text: _p?.maxDiscountPaise == null ? '' : rupeesText(_p!.maxDiscountPaise!));
  late final _categories = {
    if (_p != null)
      for (final (type, id) in _p.targets)
        if (type == TargetType.category) id,
    if (_p == null)
      for (final c in widget.phoneCategories) c.id,
  };
  late final _types = {
    ...?_p?.packTypes,
    if (_p == null) ...['glass', 'case'],
  };
  late bool _whole = _p?.packWhole ?? false;
  late bool _active = _p?.isActive ?? true;
  late DateTime _starts = _new ? DateTime.now() : _p!.startsAt.toLocal();
  late DateTime? _ends = _p?.endsAt?.toLocal();
  bool _busy = false;
  String? _pickError;

  @override
  void dispose() {
    for (final c in [_title, _percent, _cap]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final pickError = _categories.isEmpty
        ? 'Pick at least one phone category.'
        : _types.isEmpty
        ? 'Pick at least one accessory type.'
        : null;
    setState(() => _pickError = pickError);
    if (_busy || !_form.currentState!.validate() || pickError != null) return;
    setState(() => _busy = true);
    try {
      final pack = Promotion(
        id: _new ? null : _p!.id,
        title: tidy(_title.text),
        kind: OfferKind.pack,
        value: int.parse(_percent.text),
        maxDiscountPaise: _cap.text.trim().isEmpty ? null : parseRupees(_cap.text),
        wholeOrder: false,
        targets: {for (final id in _categories) (TargetType.category, id)},
        packTypes: [
          for (final t in PackType.values)
            if (_types.contains(t.value)) t.value,
        ],
        packWhole: _whole,
        startsAt: _starts,
        endsAt: _ends,
        perUserLimit: null, // a customer may buy more than one pack
        isActive: _active,
      );
      await ref.read(adminOffersApiProvider).savePromotion(pack.toJson());
      ref
        ..invalidate(adminPromotionsProvider)
        ..invalidate(packOffersProvider);
      if (!mounted) return;
      showMessage(context, _new ? 'Pack offer created' : 'Pack offer saved');
      context.go('/admin/offers');
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: Space.md);
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      bottomNavigationBar: StickyBar(
        child: FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_new ? 'Create pack offer' : 'Save pack offer'),
        ),
      ),
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              gap,
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  helperText: 'Customers see it, e.g. "Phone pack".',
                ),
                inputFormatters: textInput(60),
                validator: (v) => checkText(v, min: 2, max: 60),
              ),
              const ListSection('Phones it applies to'),
              for (final k in widget.phoneCategories)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(k.name),
                  value: _categories.contains(k.id),
                  onChanged: (on) => setState(() => on! ? _categories.add(k.id) : _categories.remove(k.id)),
                ),
              const ListSection('The cart must also hold'),
              for (final t in PackType.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.label),
                  subtitle: switch (t) {
                    PackType.charger || PackType.earphones => const Text('Any one fits every phone'),
                    _ => const Text('One made for that phone'),
                  },
                  value: _types.contains(t.value),
                  onChanged: (on) => setState(() => on! ? _types.add(t.value) : _types.remove(t.value)),
                ),
              if (_pickError != null) Text(_pickError!, style: TextStyle(color: c.error)),
              const ListSection('Discount'),
              TextFormField(
                controller: _percent,
                decoration: const InputDecoration(labelText: 'Percent off', suffixText: '%'),
                keyboardType: TextInputType.number,
                inputFormatters: const [DigitsFormatter(2)],
                validator: (v) => switch (int.tryParse(v ?? '')) {
                  final n? when n >= 1 && n <= 50 => null,
                  _ => 'Enter a percent from 1 to 50.',
                },
              ),
              gap,
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Accessories only')),
                  ButtonSegment(value: true, label: Text('Whole pack')),
                ],
                selected: {_whole},
                onSelectionChanged: (s) => setState(() => _whole = s.first),
              ),
              gap,
              TextFormField(
                controller: _cap,
                decoration: const InputDecoration(labelText: 'Most it takes off (optional)', prefixText: '₹ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [RupeesFormatter(maxDigits: 7)],
                validator: (v) => rupeesError(v, minPaise: 100, maxPaise: maxAmountPaise, optional: true),
              ),
              const ListSection('When'),
              DateTimeField(
                label: 'Starts',
                initialValue: _starts,
                onChanged: (d) => setState(() => _starts = d ?? _starts),
              ),
              gap,
              DateTimeField(
                label: 'Ends',
                initialValue: _ends,
                clearable: true,
                emptyText: 'No end date',
                onChanged: (d) => setState(() => _ends = d),
                validator: (d) => d != null && !d.isAfter(_starts) ? 'End it after it starts.' : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text('Off pauses the pack'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              Text(
                'Customers see a "Complete your pack" card on phone pages and in the cart. Only one offer applies per '
                'order: they always get the bigger saving.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
