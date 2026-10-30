import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/picker.dart';
import '../../../core/widgets/widgets.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../data/admin.dart';
import '../data/photos.dart';
import '../data/rules.dart';
import '../widgets/admin_widgets.dart';
import 'admin_feedback_screen.dart' show ListingReportsRow;

const _gstRates = <num>[0, 5, 12, 18, 28];

// specs is jsonb with no per-field limit (only 20 kB in all); these keep one row readable on a phone
const _specLabelMax = 40;
const _specValueMax = 200;

// variant attributes: short enough that "RAM · storage · colour" always fits the 80-character variant name
const _ramMax = 20, _storageMax = 20, _colorMax = 30;

/// The slug suggested for a product name, cut to the DB's 160 without a trailing dash.
String slugFor(String name) {
  final s = slugify(name);
  return s.length <= MaxLen.slug ? s : s.substring(0, MaxLen.slug).replaceAll(RegExp(r'-+$'), '');
}

String _pct(num g) => g == g.roundToDouble() ? '${g.toInt()}%' : '$g%';

class AdminProductEditScreen extends ConsumerWidget {
  const AdminProductEditScreen({super.key, this.productId});

  final String? productId; // null = new product

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brands = ref.watch(adminBrandsProvider);
    final categories = ref.watch(adminCategoriesProvider);
    final AsyncValue<Product?> product = productId == null ? const AsyncData(null) : ref.watch(adminProductProvider(productId!));
    final error = brands.error ?? categories.error ?? product.error;
    final ready = brands.hasValue && categories.hasValue && product.hasValue;
    return AdminGate(
      child: ready
          ? _Editor(
              key: ValueKey(productId),
              product: product.value,
              brands: brands.value!,
              categories: categories.value!,
            )
          : Scaffold(
              appBar: AppBar(title: Text(productId == null ? 'New product' : 'Edit product')),
              body: error != null
                  ? ErrorView(
                      error: error,
                      onRetry: () {
                        ref.invalidate(adminBrandsProvider);
                        ref.invalidate(adminCategoriesProvider);
                        if (productId != null) ref.invalidate(adminProductProvider(productId!));
                      },
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
    );
  }
}

class _SpecRow {
  _SpecRow([Spec? s])
      : label = TextEditingController(text: s?.label),
        value = TextEditingController(text: s?.value);

  final TextEditingController label;
  final TextEditingController value;

  void dispose() {
    label.dispose();
    value.dispose();
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.product, required this.brands, required this.categories});

  final Product? product;
  final List<Brand> brands;
  final List<Category> categories;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _form = GlobalKey<FormState>();
  late final Product? _p = widget.product; // the row the form was opened with
  late final _name = TextEditingController(text: _p?.name);
  late final _slug = TextEditingController(text: _p?.slug);
  late final _description = TextEditingController(text: _p?.description);
  late final _specs = [for (final s in _p?.specs ?? const <Spec>[]) _SpecRow(s)];
  late final _brands = [...widget.brands]; // grows when staff add a brand from the picker
  late String? _brandId = _p?.brand.id;
  late String? _categoryId = _p?.category.id;
  late num _gst = _p?.gstRate ?? 18;
  late bool _active = _p?.isActive ?? true;
  late bool _featured = _p?.isFeatured ?? false;
  late bool _slugEdited = _p != null; // existing slugs stay put: shared links use them
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _slug, _description]) {
      c.dispose();
    }
    for (final s in _specs) {
      s.dispose();
    }
    super.dispose();
  }

  void _moveSpec(int i, int to) => setState(() => _specs.insert(to, _specs.removeAt(i)));

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final specs = [
      for (final s in _specs)
        if (tidy(s.label.text).isNotEmpty) Spec(tidy(s.label.text), tidy(s.value.text)).toJson(),
    ];
    // DB: specs ≤ 20 kB; Postgres prints jsonb with a few more spaces than jsonEncode, hence the margin
    if (utf8.encode(jsonEncode(specs)).length > 19000) {
      return showMessage(context, 'The specs are too long to save. Shorten or remove some.');
    }
    setState(() => _busy = true);
    final fields = {
      'name': tidy(_name.text),
      'slug': _slug.text.trim(),
      'brand_id': _brandId,
      'category_id': _categoryId,
      'description': tidy(_description.text, multiline: true),
      'specs': specs,
      'gst_rate': _gst,
      'is_active': _active,
      'is_featured': _featured,
    };
    try {
      final id = await saveProduct(ref, _p?.id, fields);
      if (!mounted) return;
      if (_p == null) {
        showMessage(context, 'Product created. Now add photos and variants.');
        context.pushReplacement('/admin/products/$id');
      } else {
        showMessage(context, 'Details saved');
      }
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
    final live = widget.product; // refreshed after photo/variant changes
    final gstOptions = {..._gstRates, _gst}.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text(_p == null ? 'New product' : 'Edit product')),
      bottomNavigationBar: StickyBar(
        child: FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_p == null ? 'Create product' : 'Save details'),
        ),
      ),
      body: Form(
        key: _form,
        // not a ListView: a lazy list drops fields scrolled far away, and Form.validate() would skip them
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NoteBox(
                _p == null
                    ? 'Save the details first. Then you can add photos and variants.'
                    : 'Details save with the button below. Photos and variants save as soon as you change them.',
                tone: TagTone.info,
              ),
              if (live != null && live.isActive && live.activeVariants.isEmpty) ...[
                const SizedBox(height: Space.sm),
                const NoteBox('Customers can’t see this product until it has an active variant.',
                    icon: PhosphorIconsBold.warning),
              ],
              if (live != null) ListingReportsRow(productId: live.id),
              const ListSection('Details'),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'Start with the brand: Samsung Galaxy S25',
                  counter: LengthCounter(_name, MaxLen.productName),
                ),
                textCapitalization: TextCapitalization.words,
                inputFormatters: textInput(MaxLen.productName),
                textInputAction: TextInputAction.next,
                onChanged: (v) {
                  if (!_slugEdited) _slug.text = slugFor(v);
                },
                validator: (v) =>
                    checkText(v, min: 2, max: MaxLen.productName, what: 'the product name', mustHave: hasLetterOrDigit),
              ),
              const SizedBox(height: Space.sm),
              TextFormField(
                controller: _slug,
                decoration: const InputDecoration(labelText: 'Slug (web address)', helperText: 'Lowercase letters, numbers and dashes'),
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                inputFormatters: slugInput,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _slugEdited = true,
                validator: (v) => slugPattern.hasMatch(v ?? '') ? null : 'Use a-z, 0-9 and dashes only',
              ),
              const SizedBox(height: Space.md),
              PickerField<String>(
                label: 'Brand',
                options: [for (final b in _brands) b.id],
                labelOf: (id) => _brands.firstWhere((b) => b.id == id).name,
                initialValue: _brandId,
                onChanged: (v) => setState(() => _brandId = v),
                validator: (v) => v == null ? 'Pick a brand' : null,
                searchHint: 'Search or type a new brand',
                createLabel: 'Add brand',
                createName: brandDisplayName,
                onCreate: (name) async {
                  final b = await createBrand(ref, name);
                  if (mounted && !_brands.any((x) => x.id == b.id)) setState(() => _brands.add(b));
                  return b.id;
                },
              ),
              const SizedBox(height: Space.md),
              PickerField<String>(
                label: 'Category',
                options: [for (final k in widget.categories) k.id],
                labelOf: (id) => widget.categories.firstWhere((k) => k.id == id).name,
                initialValue: _categoryId,
                onChanged: (v) => setState(() => _categoryId = v),
                validator: (v) => v == null ? 'Pick a category' : null,
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _description,
                decoration: InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                  counter: LengthCounter(_description, MaxLen.productDescription),
                ),
                minLines: 3,
                maxLines: 8,
                inputFormatters: textInput(MaxLen.productDescription, multiline: true),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: Space.sm),
              PickerField<num>(
                label: 'GST rate',
                helperText: 'Prices include GST. Phones are 18%.',
                options: gstOptions,
                labelOf: _pct,
                initialValue: _gst,
                onChanged: (v) => setState(() => _gst = v),
              ),
              const SizedBox(height: Space.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show in the shop'),
                subtitle: const Text('Off hides it from customers'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Featured on home'),
                value: _featured,
                onChanged: (v) => setState(() => _featured = v),
              ),
              ListSection(
                'Specs',
                trailing: TextButton.icon(
                  onPressed: () => setState(() => _specs.add(_SpecRow())),
                  icon: const Icon(PhosphorIconsRegular.plus),
                  label: const Text('Add spec'),
                ),
              ),
              if (_specs.isEmpty)
                Text('Add rows like Display · 6.2 in AMOLED.', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              for (final (i, s) in _specs.indexed)
                Padding(
                  key: ObjectKey(s),
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            TextFormField(
                              controller: s.label,
                              decoration: InputDecoration(labelText: 'Label ${i + 1}', hintText: 'Display'),
                              textCapitalization: TextCapitalization.words,
                              inputFormatters: textInput(_specLabelMax),
                              textInputAction: TextInputAction.next,
                              validator: (v) =>
                                  tidy(v).isEmpty && tidy(s.value.text).isNotEmpty ? 'Add a label' : null,
                            ),
                            const SizedBox(height: Space.xs),
                            TextFormField(
                              controller: s.value,
                              decoration: const InputDecoration(labelText: 'Value', hintText: '6.2 in AMOLED, 120 Hz'),
                              inputFormatters: textInput(_specValueMax),
                              textInputAction: TextInputAction.next,
                              validator: (v) =>
                                  tidy(v).isEmpty && tidy(s.label.text).isNotEmpty ? 'Add a value' : null,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          IconButton(
                            tooltip: 'Move spec ${i + 1} up',
                            onPressed: i == 0 ? null : () => _moveSpec(i, i - 1),
                            icon: const Icon(PhosphorIconsRegular.arrowUp),
                          ),
                          IconButton(
                            tooltip: 'Move spec ${i + 1} down',
                            onPressed: i == _specs.length - 1 ? null : () => _moveSpec(i, i + 1),
                            icon: const Icon(PhosphorIconsRegular.arrowDown),
                          ),
                          IconButton(
                            tooltip: 'Remove spec ${i + 1}',
                            onPressed: () {
                              final row = _specs[i];
                              setState(() => _specs.removeAt(i));
                              // its fields still hold the controllers until this frame is built
                              WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
                            },
                            icon: const Icon(PhosphorIconsRegular.trash),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (live == null) ...[
                const ListSection('Photos and variants'),
                Text('Create the product first. Photos and variants come next.',
                    style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ] else ...[
                _Photos(product: live),
                _Variants(product: live),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Photos ----------------------------------------------------------------------

class _Photos extends ConsumerStatefulWidget {
  const _Photos({required this.product});

  final Product product;

  @override
  ConsumerState<_Photos> createState() => _PhotosState();
}

class _PhotosState extends ConsumerState<_Photos> {
  bool _busy = false;
  int _failures = 0;

  /// The variants' colours (and any a photo still names): a photo can show one of them, or every colour.
  List<String> get _colors => {
        for (final v in widget.product.variants)
          if (v.color case final c? when c.isNotEmpty) c,
        for (final img in widget.product.images) ?img.color,
      }.toList();

  Future<void> _run(Future<void> Function() write, [String? done]) async {
    setState(() => _busy = true);
    try {
      await write();
      if (mounted && done != null) showMessage(context, done);
    } catch (e) {
      _failures++;
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    String? color;
    if (_colors.isNotEmpty) {
      final picked = await showPickerSheet<String>(
        context,
        title: 'Photo of which colour?',
        options: [(null, 'Any colour'), for (final c in _colors) (c, c)],
      );
      if (picked == null || !mounted) return;
      color = picked.$1;
    }
    final file = await pickPhoto(context);
    if (file == null) return;
    final images = widget.product.images;
    await _run(() async {
      final saved = await addProductImage(
          ref, widget.product.id, await readPhoto(file), images.isEmpty ? 0 : images.last.sort + 1, color: color);
      if (mounted) showMessage(context, 'Photo added · ${formatBytes(saved.before)} → ${formatBytes(saved.after)}');
    });
  }

  void _move(int i, int to) {
    final list = [...widget.product.images];
    list.insert(to, list.removeAt(i));
    _run(() => reorderImages(ref, widget.product.id, list));
  }

  Future<void> _delete(ProductPhoto image) async {
    final ok = await confirmAction(
      context,
      title: 'Delete this photo?',
      message: 'It’s removed from the shop right away.',
      action: 'Delete',
      cancel: 'Keep photo',
      destructive: true,
    );
    if (ok) await _run(() => deleteProductImage(ref, widget.product.id, image), 'Photo deleted');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final images = widget.product.images;
    final colors = _colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSection(
          'Photos',
          trailing: TextButton.icon(
            onPressed: _busy ? null : _add,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(PhosphorIconsRegular.plus),
            label: const Text('Add photo'),
          ),
        ),
        if (images.isEmpty)
          Text('No photos yet. The first photo is the cover.', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        for (final (i, img) in images.indexed)
          Padding(
            key: ValueKey(img.id),
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(width: 64, child: ProductImage(img.path, radius: Radii.md, padding: Space.xs)),
                    const SizedBox(width: Space.md),
                    Expanded(child: Text(i == 0 ? 'Cover photo' : 'Photo ${i + 1}', style: t.bodyMedium)),
                    IconButton(
                      tooltip: 'Move photo ${i + 1} up',
                      onPressed: _busy || i == 0 ? null : () => _move(i, i - 1),
                      icon: const Icon(PhosphorIconsRegular.arrowUp),
                    ),
                    IconButton(
                      tooltip: 'Move photo ${i + 1} down',
                      onPressed: _busy || i == images.length - 1 ? null : () => _move(i, i + 1),
                      icon: const Icon(PhosphorIconsRegular.arrowDown),
                    ),
                    IconButton(
                      tooltip: 'Delete photo ${i + 1}',
                      onPressed: _busy ? null : () => _delete(img),
                      icon: const Icon(PhosphorIconsRegular.trash),
                    ),
                  ],
                ),
                if (colors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 64 + Space.md, top: Space.xs),
                    child: PickerField<String>(
                      key: ValueKey('${img.color}/$_failures'), // back to what's saved after a refused write
                      label: 'Colour',
                      options: ['', ...colors],
                      labelOf: (c) => c.isEmpty ? 'Any colour' : c,
                      initialValue: img.color ?? '',
                      onChanged: (c) => _run(() => setImageColor(ref, widget.product.id, img, c.isEmpty ? null : c)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// Variants --------------------------------------------------------------------

class _Variants extends StatelessWidget {
  const _Variants({required this.product});

  final Product product;

  void _open(BuildContext context, Variant? v) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _VariantSheet(
          productId: product.id,
          variant: v,
          sort: product.variants.isEmpty ? 0 : product.variants.last.sort + 1,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSection(
          'Variants',
          trailing: TextButton.icon(
            onPressed: () => _open(context, null),
            icon: const Icon(PhosphorIconsRegular.plus),
            label: const Text('Add variant'),
          ),
        ),
        if (product.variants.isEmpty)
          Text('Add at least one: RAM, storage, colour, price and stock.',
              style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        for (final v in product.variants)
          Padding(
            key: ValueKey(v.id),
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Card(
              child: InkWell(
                onTap: () => _open(context, v),
                child: Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Row(
                    children: [
                      if (v.colorHex != null && hexColorPattern.hasMatch(v.colorHex!)) ...[
                        _Swatch(v.colorHex!),
                        const SizedBox(width: Space.md),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.name, style: t.titleSmall),
                            Text(
                              '${v.sku} · ${v.stock == 0 ? 'out of stock' : '${v.stock} in stock'}',
                              style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                            ),
                            if (!v.isActive || v.stock <= 3)
                              Padding(
                                padding: const EdgeInsets.only(top: Space.xs),
                                child: Wrap(spacing: Space.xs, children: [
                                  if (!v.isActive) const Tag('Hidden', tone: TagTone.bad),
                                  if (v.isActive && v.stock <= 3) const Tag('Low stock', tone: TagTone.deal),
                                ]),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      PriceTag(pricePaise: v.pricePaise, mrpPaise: v.mrpPaise),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.hex);

  final String hex;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFF000000 | int.parse(hex.substring(1), radix: 16)), // a product colour, not a theme colour
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: const SizedBox.square(dimension: 24),
      );
}

class _VariantSheet extends ConsumerStatefulWidget {
  const _VariantSheet({required this.productId, required this.variant, required this.sort});

  final String productId;
  final Variant? variant; // null = new
  final int sort;

  @override
  ConsumerState<_VariantSheet> createState() => _VariantSheetState();
}

class _VariantSheetState extends ConsumerState<_VariantSheet> {
  final _form = GlobalKey<FormState>();
  late final Variant? _v = widget.variant;
  late final _ram = TextEditingController(text: _v?.ram);
  late final _storage = TextEditingController(text: _v?.storage);
  late final _color = TextEditingController(text: _v?.color);
  late final _hex = TextEditingController(text: _v?.colorHex);
  late final _name = TextEditingController(text: _v?.name);
  late final _sku = TextEditingController(text: _v?.sku);
  late final _price = TextEditingController(text: _v == null ? '' : rupeesText(_v.pricePaise));
  late final _mrp = TextEditingController(text: _v == null ? '' : rupeesText(_v.mrpPaise));
  late final _stock = TextEditingController(text: '${_v?.stock ?? 0}');
  late bool _active = _v?.isActive ?? true;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_ram, _storage, _color, _hex, _name, _sku, _price, _mrp, _stock]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _autoName => variantName([tidy(_ram.text), tidy(_storage.text), tidy(_color.text)]);

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final attributes = {...?_v?.attributes}; // keeps any keys this form doesn't edit
    for (final (key, c) in [('ram', _ram), ('storage', _storage), ('color', _color), ('color_hex', _hex)]) {
      tidy(c.text).isEmpty ? attributes.remove(key) : attributes[key] = tidy(c.text);
    }
    final fields = {
      'sku': _sku.text.trim(),
      'name': tidy(_name.text).isEmpty ? _autoName : tidy(_name.text),
      'attributes': attributes,
      'price_paise': parseRupees(_price.text),
      'mrp_paise': parseRupees(_mrp.text),
      'stock': int.parse(_stock.text),
      'is_active': _active,
      if (_v == null) 'sort': widget.sort,
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await saveVariant(ref, widget.productId, _v?.id, fields);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, _v == null ? 'Variant added' : 'Variant saved');
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hexOk = hexColorPattern.hasMatch(_hex.text.trim());
    const gap = SizedBox(width: Space.md);
    return SheetForm(
      formKey: _form,
      title: _v == null ? 'New variant' : 'Edit variant',
      children: [
        Row(children: [
          Expanded(child: _field(_ram, 'RAM', hint: '8 GB', max: _ramMax)),
          gap,
          Expanded(child: _field(_storage, 'Storage', hint: '256 GB', max: _storageMax)),
        ]),
        Row(children: [
          Expanded(child: _field(_color, 'Colour', hint: 'Navy', max: _colorMax)),
          gap,
          Expanded(
            child: TextFormField(
              controller: _hex,
              decoration: InputDecoration(
                labelText: 'Colour code',
                hintText: '#1F2B4D',
                suffixIcon: hexOk ? Padding(padding: const EdgeInsets.all(12), child: _Swatch(_hex.text.trim())) : null,
              ),
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: const [HexColorFormatter()],
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              validator: (v) => (v ?? '').trim().isEmpty || hexColorPattern.hasMatch(v!.trim()) ? null : 'Like #1F2B4D',
            ),
          ),
        ]),
        const SizedBox(height: Space.md),
        TextFormField(
          controller: _name,
          decoration: InputDecoration(
            labelText: 'Name',
            helperText: 'Blank uses RAM · storage · colour',
            hintText: _autoName.isEmpty ? '8 GB · 256 GB · Navy' : _autoName,
          ),
          inputFormatters: textInput(MaxLen.name),
          textInputAction: TextInputAction.next,
          validator: (v) => tidy(v).isEmpty
              ? (_autoName.isEmpty ? 'Add a name or RAM/storage/colour' : checkText(_autoName, max: MaxLen.name))
              : checkText(v, max: MaxLen.name),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: TextFormField(
            controller: _sku,
            decoration: const InputDecoration(labelText: 'SKU', hintText: 'SAM-S25-8-256-NVY'),
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: skuInput,
            textInputAction: TextInputAction.next,
            validator: (v) => (v ?? '').isEmpty
                ? 'Enter the SKU'
                : skuPattern.hasMatch(v!)
                    ? null
                    : 'Start with a letter or digit; then letters, digits and . _ / - only',
          ),
        ),
        const SizedBox(height: Space.md),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextFormField(
              controller: _price,
              decoration: const InputDecoration(labelText: 'Price', prefixText: '₹ ', errorMaxLines: 3),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [RupeesFormatter(maxDigits: 7)],
              textInputAction: TextInputAction.next,
              validator: (v) => rupeesError(v, minPaise: 1, maxPaise: maxAmountPaise),
            ),
          ),
          gap,
          Expanded(
            child: TextFormField(
              controller: _mrp,
              decoration: const InputDecoration(labelText: 'MRP', prefixText: '₹ ', errorMaxLines: 3),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [RupeesFormatter(maxDigits: 7)],
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (rupeesError(v, minPaise: 1, maxPaise: maxAmountPaise) case final error?) return error;
                final mrp = parseRupees(v!)!;
                final price = parseRupees(_price.text);
                return price != null && mrp < price ? 'Can’t be below ${formatInr(price)}' : null;
              },
            ),
          ),
        ]),
        const SizedBox(height: Space.md),
        TextFormField(
          controller: _stock,
          decoration: const InputDecoration(labelText: 'Stock'),
          keyboardType: TextInputType.number,
          // business cap 99,999 (5 digits), well inside the DB's 0..1,000,000
          inputFormatters: const [DigitsFormatter(5)],
          textInputAction: TextInputAction.done,
          validator: (v) => (v ?? '').isEmpty ? 'Enter the stock (0 if none)' : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: const Text('Off hides this variant from customers'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_v == null ? 'Add variant' : 'Save variant')),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, {required String hint, required int max}) => Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: TextFormField(
          controller: c,
          decoration: InputDecoration(labelText: label, hintText: hint),
          inputFormatters: textInput(max),
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}), // refreshes the auto name hint
        ),
      );
}
