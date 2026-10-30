import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/picker.dart';
import '../../../core/widgets/widgets.dart';
import '../../offers/data/offers.dart';
import '../../offers/widgets/offer_widgets.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../data/admin.dart';
import '../data/offers_admin.dart';
import '../data/rules.dart';
import '../widgets/admin_widgets.dart';

TagTone statusTone(PromotionStatus s) => switch (s) {
      PromotionStatus.running => TagTone.ok,
      PromotionStatus.scheduled => TagTone.info,
      PromotionStatus.paused => TagTone.deal,
      PromotionStatus.ended => TagTone.bad,
    };

/// Customers' copies of offers and banners are stale after any staff change.
void _offersChanged(WidgetRef ref) {
  ref.invalidate(adminPromotionsProvider);
  ref.invalidate(adminBannersProvider);
  ref.invalidate(availableOffersProvider);
  ref.invalidate(bannersProvider);
}

final _fake = Promotion(id: 'x', title: 'Diwali dhamaka on phones', code: 'DIWALI10', kind: OfferKind.percent, value: 10, startsAt: DateTime(2026));

class AdminOffersScreen extends ConsumerStatefulWidget {
  const AdminOffersScreen({super.key});

  @override
  ConsumerState<AdminOffersScreen> createState() => _AdminOffersScreenState();
}

class _AdminOffersScreenState extends ConsumerState<AdminOffersScreen> {
  String _filter = 'shop'; // personal referral coupons would bury the shop's own offers
  bool _busy = false;

  Future<void> _run(Future<void> Function() write, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write();
      _offersChanged(ref);
      if (mounted) showMessage(context, done);
    } on PostgrestException catch (e) {
      // only a delete reaches here with no row: RLS keeps an offer that a live order used
      if (mounted) showMessage(context, e.code == 'PGRST116' ? 'Already used, so it can’t be deleted. End it instead.' : adminError(e));
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _actions(Promotion p) async {
    final api = ref.read(adminOffersApiProvider);
    final ended = p.statusAt(DateTime.now()) == PromotionStatus.ended;
    final picked = await showPickerSheet<String>(context, title: p.title, options: [
      ('edit', 'Edit'),
      ('copy', 'Duplicate'),
      if (!ended) p.isActive ? ('pause', 'Pause') : ('resume', 'Resume'),
      if (!ended) ('end', 'End now'),
      if (p.uses == 0) ('delete', 'Delete'),
    ]);
    if (!mounted || picked == null) return;
    switch (picked.$1) {
      case 'edit':
        await context.push('/admin/offers/${p.id}');
      case 'copy':
        await context.push('/admin/offers/new?copy=${p.id}');
      case 'pause' || 'resume':
        await _run(() => api.savePromotion({'id': p.id, 'is_active': !p.isActive}), p.isActive ? 'Offer paused' : 'Offer resumed');
      case 'end':
        final ok = await confirmChoice(
          context,
          title: 'End “${p.title}” now?',
          message: 'Customers can’t use it after this, and its banner comes down. You can duplicate it later.',
          action: 'End now',
          keep: 'Keep it running',
          destructive: true,
        );
        if (ok) {
          final now = DateTime.now().toUtc();
          await _run(
            () => api.savePromotion({
              'id': p.id,
              'ends_at': now.toIso8601String(),
              // a scheduled one never starts: its start moves back too, or the end would come before it
              if (p.startsAt.isAfter(now)) 'starts_at': now.subtract(const Duration(minutes: 1)).toIso8601String(),
            }),
            'Offer ended',
          );
        }
      case 'delete':
        final ok = await confirmChoice(
          context,
          title: 'Delete “${p.title}”?',
          message: 'Nobody has used it yet, so it goes for good, with its banner.',
          action: 'Delete',
          keep: 'Keep offer',
          destructive: true,
        );
        if (ok) await _run(() => api.deletePromotion(p.id!), 'Offer deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminPromotionsProvider);
    return AdminGate(
      child: Scaffold(
        appBar: AppBar(title: const Text('Offers')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/admin/offers/new'),
          icon: const Icon(PhosphorIconsRegular.plus),
          label: const Text('New offer'),
        ),
        body: Column(
          children: [
            ChipBar(
              options: const {'shop': 'Shop offers', 'personal': 'Referral coupons'},
              selected: _filter,
              onSelected: (k) => setState(() => _filter = k),
            ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: AsyncBody<List<Promotion>>(
                value: value,
                onRetry: () => ref.invalidate(adminPromotionsProvider),
                loading: Skeletonizer(
                  child: ListView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [for (var i = 0; i < 4; i++) _Row(_fake, onMore: () {})],
                  ),
                ),
                data: (all) {
                  final list = all.where((p) => (p.userId != null) == (_filter == 'personal')).toList();
                  if (list.isEmpty) {
                    return EmptyState(
                      icon: PhosphorIconsRegular.sealPercent,
                      title: _filter == 'personal' ? 'No referral coupons yet' : 'No offers yet',
                      message: _filter == 'personal'
                          ? 'Refer & earn makes these for customers. They show up here.'
                          : 'Make a coupon code or a sale. It can show on the home screen too.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () => ref.refresh(adminPromotionsProvider.future),
                    // shortcut: admin_promotions() returns every row (a JSON array, no paging), built lazily here;
                    // give it p_offset/p_limit if referral coupons ever run into the thousands
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 96), // clear of the button
                      itemCount: list.length,
                      itemBuilder: (_, i) => _Row(list[i], key: ValueKey(list[i].id), onMore: _busy ? null : () => _actions(list[i])),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.p, {super.key, required this.onMore});

  final Promotion p;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final status = p.statusAt(DateTime.now());
    final details = [
      p.code ?? 'Automatic sale',
      valueHeadline(p.kind, p.value),
      if (!p.isPublic) 'Hidden',
      '${p.uses} use${p.uses == 1 ? '' : 's'}',
      // waived delivery fees aren't counted in the total
      if (p.kind != OfferKind.freeDelivery) '${shortInr(p.discountTotalPaise)} given',
    ].join(' · ');
    return InkWell(
      onTap: () => context.push('/admin/offers/${p.id}'),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.outlineVariant))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.xs, Space.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(p.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Tag(status.label, tone: statusTone(status)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(details, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Actions for ${p.title}',
                onPressed: onMore,
                icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Editor ----------------------------------------------------------------------

/// `/admin/offers/new` (optionally `?copy=<id>` to start from another offer) and `/admin/offers/:id`.
class AdminOfferEditScreen extends ConsumerWidget {
  const AdminOfferEditScreen({super.key, this.promotionId, this.copyOf});

  final String? promotionId; // null = new offer
  final String? copyOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = promotionId ?? copyOf;
    final AsyncValue<Promotion?> promotion = source == null
        ? const AsyncData(null)
        : ref.watch(adminPromotionsProvider).whenData((list) => list.where((p) => p.id == source).firstOrNull);
    final products = ref.watch(adminProductsProvider);
    final categories = ref.watch(adminCategoriesProvider);
    final brands = ref.watch(adminBrandsProvider);
    final groups = ref.watch(adminCollectionsProvider);
    final all = [promotion, products, categories, brands, groups];
    final error = all.map((v) => v.error).nonNulls.firstOrNull;
    final title = promotionId == null ? 'New offer' : 'Edit offer';
    return AdminGate(
      child: all.every((v) => v.hasValue) && (source == null || promotion.value != null)
          ? _Editor(
              key: ValueKey(source),
              title: title,
              source: promotion.value,
              copy: copyOf != null,
              targets: {
                for (final p in products.value!) (TargetType.product, p.id): 'Product · ${p.name}',
                for (final k in categories.value!) (TargetType.category, k.id): 'Category · ${k.name}',
                for (final b in brands.value!) (TargetType.brand, b.id): 'Brand · ${b.name}',
                for (final g in groups.value!) (TargetType.collection, g.id!): 'Group · ${g.name}',
              },
            )
          : Scaffold(
              appBar: AppBar(title: Text(title)),
              body: error != null
                  ? ErrorView(
                      error: error,
                      onRetry: () {
                        ref.invalidate(adminPromotionsProvider);
                        ref.invalidate(adminProductsProvider);
                        ref.invalidate(adminCategoriesProvider);
                        ref.invalidate(adminBrandsProvider);
                        ref.invalidate(adminCollectionsProvider);
                      },
                    )
                  : promotion.hasValue
                      ? const EmptyState(icon: PhosphorIconsRegular.sealPercent, title: 'This offer was deleted')
                      : const Center(child: CircularProgressIndicator()),
            ),
    );
  }
}

/// "3 products · 1 brand"
String targetsSummary(Set<(TargetType, String)> targets) {
  const names = {
    TargetType.product: ('product', 'products'),
    TargetType.category: ('category', 'categories'),
    TargetType.brand: ('brand', 'brands'),
    TargetType.collection: ('group', 'groups'),
  };
  return [
    for (final type in TargetType.values)
      if (targets.where((t) => t.$1 == type).length case final n when n > 0) '$n ${n == 1 ? names[type]!.$1 : names[type]!.$2}',
  ].join(' · ');
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.title, required this.source, required this.copy, required this.targets});

  final String title;
  final Promotion? source; // the offer being edited, or the one being copied
  final bool copy;
  final Map<(TargetType, String), String> targets; // everything an offer can cover, with its label

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _form = GlobalKey<FormState>();
  late final Promotion? _p = widget.source;
  late final bool _new = _p == null || widget.copy;
  late OfferKind _kind = _p?.kind ?? OfferKind.percent;
  late final _value = TextEditingController(
    text: switch (_p) {
      null => '',
      Promotion(kind: OfferKind.percent, :final value) => '$value',
      Promotion(kind: OfferKind.flat, :final value) => rupeesText(value),
      _ => '',
    },
  );
  late final _cap = TextEditingController(text: _p?.maxDiscountPaise == null ? '' : rupeesText(_p!.maxDiscountPaise!));
  late bool _withCode = _p == null || _p.code != null;
  late final _code = TextEditingController(text: widget.copy ? '' : _p?.code); // codes are unique
  late bool _public = _p?.isPublic ?? true;
  late final _title = TextEditingController(text: _p?.title);
  late final _description = TextEditingController(text: _p?.description);
  late bool _wholeOrder = _p?.wholeOrder ?? true;
  late Set<(TargetType, String)> _targets = {...?_p?.targets.where(widget.targets.containsKey)};
  late final _min = TextEditingController(text: (_p?.minSubtotalPaise ?? 0) == 0 ? '' : rupeesText(_p!.minSubtotalPaise));
  late DateTime _starts = _new ? _minute(DateTime.now()) : _p!.startsAt.toLocal();
  late DateTime? _ends = _p?.endsAt == null || (widget.copy && !_p!.endsAt!.isAfter(DateTime.now())) ? null : _p!.endsAt!.toLocal();
  late final _usageLimit = TextEditingController(text: widget.copy ? '' : '${_p?.usageLimit ?? ''}');
  late final _perUser = TextEditingController(text: _p == null ? '1' : '${_p.perUserLimit ?? ''}');
  late bool _firstOrder = _p?.firstOrderOnly ?? false;
  late bool _onlineOnly = _p?.onlineOnly ?? false;
  late bool _showBanner = _p?.showBanner ?? false;
  bool _busy = false;

  static DateTime _minute(DateTime d) => DateTime(d.year, d.month, d.day, d.hour, d.minute);

  @override
  void dispose() {
    for (final c in [_value, _cap, _code, _title, _description, _min, _usageLimit, _perUser]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _valueError(String? v) => switch (_kind) {
        OfferKind.percent => switch (int.tryParse(v ?? '')) {
            final n? when n >= 1 && n <= maxPercentOff => null,
            _ => 'Enter a percent from 1 to $maxPercentOff.',
          },
        OfferKind.flat => rupeesError(v, minPaise: minFlatPaise, maxPaise: maxAmountPaise),
        OfferKind.freeDelivery => null,
      };

  String? _limitError(String? v) => (v ?? '').isEmpty || (int.tryParse(v!) ?? 0) >= 1 ? null : 'Enter 1 or more, or leave it blank.';

  Promotion _build() => Promotion(
        id: _new ? null : _p!.id,
        title: tidy(_title.text),
        description: tidy(_description.text, multiline: true),
        code: _withCode ? _code.text.trim() : null,
        kind: _kind,
        value: switch (_kind) {
          OfferKind.percent => int.parse(_value.text),
          OfferKind.flat => parseRupees(_value.text)!,
          OfferKind.freeDelivery => 0,
        },
        maxDiscountPaise: _kind == OfferKind.percent && _cap.text.trim().isNotEmpty ? parseRupees(_cap.text) : null,
        minSubtotalPaise: _min.text.trim().isEmpty ? 0 : parseRupees(_min.text)!,
        wholeOrder: _wholeOrder,
        targets: _wholeOrder ? const {} : _targets,
        startsAt: _starts,
        endsAt: _ends,
        usageLimit: int.tryParse(_usageLimit.text),
        perUserLimit: int.tryParse(_perUser.text),
        firstOrderOnly: _firstOrder,
        onlineOnly: _onlineOnly,
        isPublic: _public,
        isActive: _new || _p!.isActive,
        showBanner: _canBanner && _showBanner,
        userId: _new ? null : _p!.userId,
      );

  // a banner prints the code, so hidden and personal codes can't have one (DB: promotions_banner_check)
  bool get _canBanner => _public && (_new || _p!.userId == null);

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminOffersApiProvider).savePromotion(_build().toJson());
      _offersChanged(ref);
      if (!mounted) return;
      showMessage(context, _new ? 'Offer created' : 'Offer saved');
      context.go('/admin/offers');
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _gap() => const SizedBox(height: Space.md);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final money = [const RupeesFormatter(maxDigits: 7)];
    const rupees = TextInputType.numberWithOptions(decimal: true);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      bottomNavigationBar: StickyBar(
        child: FilledButton(onPressed: _busy ? null : _save, child: Text(_new ? 'Create offer' : 'Save offer')),
      ),
      body: Form(
        key: _form,
        // not a ListView: a lazy list drops fields scrolled far away, and Form.validate() would skip them
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_new && _p!.userId != null)
                const Padding(
                  padding: EdgeInsets.only(top: Space.sm),
                  child: NoteBox('A personal coupon from Refer & earn. Only that customer can see or use it.', tone: TagTone.info),
                ),
              const ListSection('Offer'),
              TextFormField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: 'Title',
                  hintText: 'Diwali dhamaka on phones',
                  helperText: 'Customers see this, and so does the banner.',
                  counter: LengthCounter(_title, 60),
                ),
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: textInput(60),
                textInputAction: TextInputAction.next,
                validator: (v) => checkText(v, min: 2, max: 60, what: 'a title', mustHave: hasLetterOrDigit),
              ),
              _gap(),
              TextFormField(
                controller: _description,
                decoration: InputDecoration(
                  labelText: 'Terms (optional)',
                  hintText: 'On all smartphones. Not with exchange offers.',
                  alignLabelWithHint: true,
                  counter: LengthCounter(_description, 300),
                ),
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: textInput(300, multiline: true),
                validator: (v) => checkText(v, max: 300, multiline: true),
              ),
              _gap(),
              PickerField<OfferKind>(
                label: 'Type',
                options: OfferKind.values,
                labelOf: (k) => k.label,
                initialValue: _kind,
                onChanged: (k) => setState(() {
                  _kind = k;
                  _value.clear();
                }),
              ),
              if (_kind != OfferKind.freeDelivery) ...[
                _gap(),
                TextFormField(
                  key: ValueKey(_kind),
                  controller: _value,
                  decoration: InputDecoration(
                    labelText: _kind == OfferKind.percent ? 'Percent off' : 'Amount off',
                    prefixText: _kind == OfferKind.flat ? '₹ ' : null,
                    suffixText: _kind == OfferKind.percent ? '%' : null,
                  ),
                  keyboardType: _kind == OfferKind.percent ? TextInputType.number : rupees,
                  inputFormatters: _kind == OfferKind.percent ? const [DigitsFormatter(2)] : money,
                  textInputAction: TextInputAction.next,
                  validator: _valueError,
                ),
              ],
              if (_kind == OfferKind.percent) ...[
                _gap(),
                TextFormField(
                  controller: _cap,
                  decoration: const InputDecoration(
                    labelText: 'Most it can take off (optional)',
                    prefixText: '₹ ',
                    helperText: 'Blank: no cap.',
                  ),
                  keyboardType: rupees,
                  inputFormatters: money,
                  textInputAction: TextInputAction.next,
                  validator: (v) => rupeesError(v, minPaise: minFlatPaise, maxPaise: maxAmountPaise, optional: true),
                ),
              ],
              const ListSection('How customers get it'),
              PickerField<bool>(
                label: 'Applies',
                options: const [true, false],
                labelOf: (code) => code ? 'With a coupon code' : 'Automatically (a sale)',
                initialValue: _withCode,
                onChanged: (v) => setState(() => _withCode = v),
              ),
              if (_withCode) ...[
                _gap(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _code,
                        decoration: const InputDecoration(labelText: 'Code', hintText: 'DIWALI10'),
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        enableSuggestions: false,
                        inputFormatters: couponCodeInput,
                        textInputAction: TextInputAction.next,
                        validator: (v) => validateCode(v),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: TextButton.icon(
                        onPressed: () => setState(() => _code.text = generateCode()),
                        icon: const Icon(PhosphorIconsRegular.magicWand),
                        label: const Text('Generate'),
                      ),
                    ),
                  ],
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('List it in Offers'),
                subtitle: Text(_withCode
                    ? 'Off: the code works only when typed, like one you send on WhatsApp.'
                    : 'Off: the sale still applies, it just isn’t listed.'),
                value: _public,
                onChanged: (v) => setState(() => _public = v),
              ),
              const ListSection('What it covers'),
              PickerField<bool>(
                label: 'Covers',
                options: const [true, false],
                labelOf: (whole) => whole ? 'The whole order' : 'Some products',
                initialValue: _wholeOrder,
                onChanged: (v) => setState(() => _wholeOrder = v),
              ),
              if (!_wholeOrder) ...[
                _gap(),
                MultiPickerField<(TargetType, String)>(
                  label: 'Products, categories, brands or groups',
                  options: widget.targets.keys.toList(),
                  labelOf: (k) => widget.targets[k]!,
                  initialValue: _targets,
                  searchHint: 'Search products, brands, groups',
                  helperText: _targets.isEmpty ? 'Any mix. A product counts if any of these covers it.' : targetsSummary(_targets),
                  onChanged: (v) => setState(() => _targets = v),
                  validator: (v) => (v ?? const {}).isEmpty ? 'Pick at least one product, category, brand or group.' : null,
                ),
              ],
              _gap(),
              TextFormField(
                controller: _min,
                decoration: InputDecoration(
                  labelText: 'Minimum order (optional)',
                  prefixText: '₹ ',
                  helperText: _wholeOrder ? 'Cart total before delivery.' : 'Counts only the covered products.',
                ),
                keyboardType: rupees,
                inputFormatters: money,
                textInputAction: TextInputAction.next,
                validator: (v) => rupeesError(v, maxPaise: maxAmountPaise, optional: true),
              ),
              const ListSection('When'),
              DateTimeField(
                label: 'Starts',
                initialValue: _starts,
                onChanged: (d) => setState(() => _starts = d ?? _starts),
              ),
              _gap(),
              DateTimeField(
                label: 'Ends',
                initialValue: _ends,
                clearable: true,
                emptyText: 'No end date',
                onChanged: (d) => setState(() => _ends = d),
                validator: (d) => d != null && !d.isAfter(_starts) ? 'End it after it starts.' : null,
              ),
              const ListSection('Limits'),
              TextFormField(
                controller: _usageLimit,
                decoration: const InputDecoration(labelText: 'Total uses (optional)', helperText: 'Across the whole shop. Blank: no limit.'),
                keyboardType: TextInputType.number,
                inputFormatters: const [DigitsFormatter(6)],
                textInputAction: TextInputAction.next,
                validator: _limitError,
              ),
              _gap(),
              TextFormField(
                controller: _perUser,
                decoration: const InputDecoration(labelText: 'Uses per customer', helperText: 'Blank: no limit.'),
                keyboardType: TextInputType.number,
                inputFormatters: const [DigitsFormatter(3)],
                textInputAction: TextInputAction.done,
                validator: _limitError,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('First order only'),
                subtitle: const Text('For customers who haven’t ordered yet'),
                value: _firstOrder,
                onChanged: (v) => setState(() => _firstOrder = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Online payment only'),
                subtitle: const Text('Not with cash on delivery'),
                value: _onlineOnly,
                onChanged: (v) => setState(() => _onlineOnly = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show a banner on home'),
                subtitle: Text(_canBanner
                    ? 'Uses the title and these dates. Edit its look in Banners.'
                    : 'Only for offers listed in Offers: a banner shows the code to everyone.'),
                value: _canBanner && _showBanner,
                onChanged: _canBanner ? (v) => setState(() => _showBanner = v) : null,
              ),
              const SizedBox(height: Space.sm),
              Text(
                'The shop checks every order against these rules. An order always costs at least ₹1 before delivery.',
                style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
