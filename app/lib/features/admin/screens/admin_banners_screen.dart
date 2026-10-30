import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
import '../data/photos.dart';
import '../widgets/admin_widgets.dart';
import 'admin_offers_screen.dart' show statusTone;

const toneNames = ['Peacock', 'Marigold', 'Emerald', 'Plum', 'Indigo', 'Rose']; // heroGradients, in order

void _bannersChanged(WidgetRef ref) {
  ref.invalidate(adminBannersProvider);
  ref.invalidate(bannersProvider);
}

class AdminBannersScreen extends ConsumerStatefulWidget {
  const AdminBannersScreen({super.key});

  @override
  ConsumerState<AdminBannersScreen> createState() => _AdminBannersScreenState();
}

class _AdminBannersScreenState extends ConsumerState<AdminBannersScreen> {
  bool _busy = false;

  /// Writes sort = position for every banner whose position changed, like product photos.
  Future<void> _move(List<PromoBanner> list, int i, int to) async {
    if (_busy) return;
    final ordered = [...list];
    ordered.insert(to, ordered.removeAt(i));
    setState(() => _busy = true);
    try {
      final api = ref.read(adminOffersApiProvider);
      for (final (n, b) in ordered.indexed) {
        if (b.sort != n) await api.saveBanner(b.id, {'sort': n});
      }
      _bannersChanged(ref);
      if (mounted) showMessage(context, 'Order saved');
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminBannersProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return AdminGate(
      child: Scaffold(
        appBar: AppBar(title: const Text('Banners')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/admin/banners/new'),
          icon: const Icon(PhosphorIconsRegular.plus),
          label: const Text('New banner'),
        ),
        body: AsyncBody<List<PromoBanner>>(
          value: value,
          onRetry: () => ref.invalidate(adminBannersProvider),
          loading: const Center(child: CircularProgressIndicator()),
          data: (list) => list.isEmpty
              ? const EmptyState(
                  icon: PhosphorIconsRegular.flagBanner,
                  title: 'No banners yet',
                  message: 'Banners show under the featured phones on home. Offers can make one for you too.',
                )
              : RefreshIndicator(
                  onRefresh: () => ref.refresh(adminBannersProvider.future),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
                        child: Text('Shown on home in this order while running.',
                            style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                      ),
                      for (final (i, b) in list.indexed)
                        InkWell(
                          key: ValueKey(b.id),
                          onTap: () => context.push('/admin/banners/${b.id}'),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.xs, Space.sm),
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
                                          Text(b.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                          Tag(b.statusAt(DateTime.now()).label, tone: statusTone(b.statusAt(DateTime.now()))),
                                          if (b.promotionId != null) const Tag('From an offer', icon: PhosphorIconsBold.sealPercent),
                                        ],
                                      ),
                                      Text(b.link, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Move ${b.title} up',
                                  onPressed: _busy || i == 0 ? null : () => _move(list, i, i - 1),
                                  icon: const Icon(PhosphorIconsRegular.arrowUp),
                                ),
                                IconButton(
                                  tooltip: 'Move ${b.title} down',
                                  onPressed: _busy || i == list.length - 1 ? null : () => _move(list, i, i + 1),
                                  icon: const Icon(PhosphorIconsRegular.arrowDown),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// `/admin/banners/new` and `/admin/banners/:id`.
class AdminBannerEditScreen extends ConsumerWidget {
  const AdminBannerEditScreen({super.key, this.bannerId});

  final String? bannerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banners = ref.watch(adminBannersProvider);
    final products = ref.watch(adminProductsProvider);
    final categories = ref.watch(adminCategoriesProvider);
    final brands = ref.watch(adminBrandsProvider);
    final all = [banners, products, categories, brands];
    final error = all.map((v) => v.error).nonNulls.firstOrNull;
    final title = bannerId == null ? 'New banner' : 'Edit banner';
    final banner = banners.value?.where((b) => b.id == bannerId).firstOrNull;
    return AdminGate(
      child: all.every((v) => v.hasValue) && (bannerId == null || banner != null)
          ? _Editor(
              key: ValueKey(bannerId),
              title: title,
              banner: banner,
              nextSort: (banners.value!.map((b) => b.sort).fold(-1, (a, b) => a > b ? a : b)) + 1,
              links: {
                '/offers': 'Offers page',
                '/search': 'All products',
                '/repairs': 'Repairs',
                '/repairs/new': 'Book a repair',
                for (final k in categories.value!) '/search?category=${k.slug}': 'Category · ${k.name}',
                for (final b in brands.value!) '/search?brand=${b.slug}': 'Brand · ${b.name}',
                for (final p in products.value!)
                  if (p.slug.isNotEmpty) '/product/${p.slug}': 'Product · ${p.name}',
              },
            )
          : Scaffold(
              appBar: AppBar(title: Text(title)),
              body: error != null
                  ? ErrorView(
                      error: error,
                      onRetry: () => ref
                        ..invalidate(adminBannersProvider)
                        ..invalidate(adminProductsProvider)
                        ..invalidate(adminCategoriesProvider)
                        ..invalidate(adminBrandsProvider),
                    )
                  : banners.hasValue
                      ? const EmptyState(icon: PhosphorIconsRegular.flagBanner, title: 'This banner was deleted')
                      : const Center(child: CircularProgressIndicator()),
            ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.title, required this.banner, required this.nextSort, required this.links});

  final String title;
  final PromoBanner? banner;
  final int nextSort;
  final Map<String, String> links; // route → label

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _form = GlobalKey<FormState>();
  late final PromoBanner? _b = widget.banner;
  late final bool _fromOffer = _b?.promotionId != null; // the offer's trigger keeps its words, dates, link and on/off
  late final _title = TextEditingController(text: _b?.title);
  late final _subtitle = TextEditingController(text: _b?.subtitle);
  late final _cta = TextEditingController(text: _b?.ctaLabel ?? 'Shop now');
  late String? _link = _b?.link;
  late final int _tone = _b?.tone ?? 0;
  late String? _image = _b?.imagePath;
  late DateTime _starts = _b?.startsAt.toLocal() ?? DateTime.now();
  late DateTime? _ends = _b?.endsAt?.toLocal();
  late bool _active = _b?.isActive ?? true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _subtitle, _cta]) {
      c.addListener(() => setState(() {})); // live preview
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _subtitle, _cta]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() write) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write();
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImage() async {
    final file = await pickPhoto(context);
    if (file == null) return;
    await _run(() async {
      // shortcut: a photo uploaded and then not saved stays in storage (~200 KB); sweep unreferenced banners/ if it grows
      final path = await uploadBannerImage(ref, await readPhoto(file));
      if (mounted) setState(() => _image = path);
    });
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    await _run(() async {
      final before = _b?.imagePath;
      await ref.read(adminOffersApiProvider).saveBanner(_b?.id, {
        'image_path': _image,
        'tone': _tone,
        if (_b == null) 'sort': widget.nextSort,
        if (!_fromOffer) ...{
          'title': tidy(_title.text),
          'subtitle': tidy(_subtitle.text),
          'is_active': _active,
          'cta_label': tidy(_cta.text),
          'link': _link,
          'starts_at': _starts.toUtc().toIso8601String(),
          'ends_at': _ends?.toUtc().toIso8601String(),
        },
      });
      if (before != null && before != _image) await deleteBannerImage(ref, before);
      _bannersChanged(ref);
      if (!mounted) return;
      showMessage(context, 'Banner saved');
      context.go('/admin/banners');
    });
  }

  Future<void> _delete() async {
    final ok = await confirmChoice(
      context,
      title: 'Delete this banner?',
      message: _fromOffer
          ? 'It comes off home. Turn off “Show a banner” on the offer too, or saving the offer brings it back.'
          : 'It comes off home straight away.',
      action: 'Delete banner',
      keep: 'Keep banner',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() async {
      await ref.read(adminOffersApiProvider).deleteBanner(_b!.id);
      if (_b.imagePath case final p?) await deleteBannerImage(ref, p);
      _bannersChanged(ref);
      if (!mounted) return;
      showMessage(context, 'Banner deleted');
      context.go('/admin/banners');
    });
  }

  Widget _gap() => const SizedBox(height: Space.md);

  @override
  Widget build(BuildContext context) {
    final links = {...widget.links, ?_link: widget.links[_link] ?? '$_link'};
    final preview = PromoBannerCard(PromoBanner(
      id: '',
      title: tidy(_title.text).isEmpty ? 'Banner title' : tidy(_title.text),
      subtitle: tidy(_subtitle.text),
      ctaLabel: tidy(_cta.text).isEmpty ? 'Shop now' : tidy(_cta.text),
      link: '',
      imagePath: _image,
      tone: _tone,
      startsAt: _starts,
    ));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_b != null)
            IconButton(tooltip: 'Delete banner', onPressed: _busy ? null : _delete, icon: const Icon(PhosphorIconsRegular.trash)),
        ],
      ),
      bottomNavigationBar: StickyBar(
        child: FilledButton(onPressed: _busy ? null : _save, child: Text(_b == null ? 'Create banner' : 'Save banner')),
      ),
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(child: preview),
              if (_fromOffer) ...[
                const SizedBox(height: Space.sm),
                const NoteBox(
                  'Made by an offer: its words, dates, link and on/off follow the offer. Change its colour and photo here.',
                  tone: TagTone.info,
                ),
              ],
              if (!_fromOffer) ...[
                const ListSection('Words'),
                TextFormField(
                controller: _title,
                decoration: InputDecoration(labelText: 'Title', counter: LengthCounter(_title, 60)),
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: textInput(60),
                textInputAction: TextInputAction.next,
                validator: (v) => checkText(v, min: 2, max: 60, what: 'a title', mustHave: hasLetterOrDigit),
                ),
                _gap(),
                TextFormField(
                controller: _subtitle,
                decoration: InputDecoration(labelText: 'Line under it (optional)', counter: LengthCounter(_subtitle, 120)),
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: textInput(120),
                textInputAction: TextInputAction.next,
                validator: (v) => checkText(v, max: 120),
                ),
                _gap(),
                TextFormField(
                  controller: _cta,
                  decoration: const InputDecoration(labelText: 'Button text'),
                  inputFormatters: textInput(20),
                  textInputAction: TextInputAction.done,
                  validator: (v) => checkText(v, min: 1, max: 20, what: 'the button text', mustHave: hasLetterOrDigit),
                ),
                _gap(),
                PickerField<String>(
                  label: 'Opens',
                  options: links.keys.toList(),
                  labelOf: (l) => links[l]!,
                  initialValue: _link,
                  searchHint: 'Search pages, products, brands',
                  onChanged: (v) => setState(() => _link = v),
                  validator: (v) => v != null && isBannerLink(v) ? null : 'Pick where the banner goes',
                ),
              ],
              const ListSection('Look'),
              // colours come from the banner's id (core/theme/generative.dart), so there's nothing to pick
              Text(
                'Colours are made for each banner automatically, so every banner looks different.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              _gap(),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickImage,
                    icon: _busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(PhosphorIconsRegular.image),
                    label: Text(_image == null ? 'Add photo' : 'Replace photo'),
                  ),
                  if (_image != null)
                    TextButton.icon(
                      onPressed: _busy ? null : () => setState(() => _image = null),
                      icon: const Icon(PhosphorIconsRegular.trash),
                      label: const Text('Remove photo'),
                    ),
                ],
              ),
              if (!_fromOffer) ...[
                const ListSection('When'),
                DateTimeField(label: 'Starts', initialValue: _starts, onChanged: (d) => setState(() => _starts = d ?? _starts)),
                _gap(),
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
                  title: const Text('Show it'),
                  subtitle: const Text('Off hides it without deleting it'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
