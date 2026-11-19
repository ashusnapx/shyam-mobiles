import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/picker.dart';
import '../../../core/widgets/widgets.dart';
import '../data/admin.dart';
import '../data/ai_catalogue.dart';
import '../data/photos.dart' show autoProductPhoto, formatBytes;
import '../data/rules.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/photo_editor.dart';

/// Staff only. One item in about 20 seconds: photo of the box's back label, photo of the product, confirm, save.
/// Nothing is shown to customers unless staff switch "Show in shop" on.
class AdminQuickAddScreen extends ConsumerStatefulWidget {
  const AdminQuickAddScreen({super.key});

  @override
  ConsumerState<AdminQuickAddScreen> createState() => _QuickAddState();
}

class _QuickAddState extends ConsumerState<AdminQuickAddScreen> {
  final _form = GlobalKey<FormState>();
  final _c = {for (final k in ['name', 'brand', 'model', 'ram', 'storage', 'color', 'mrp', 'price', 'stock', 'about']) k: TextEditingController()};
  int _step = 0; // 0 label photo, 1 product photo, 2 confirm
  ProductDraft? _d;
  Uint8List? _cut; // the automatic clean-up of the product photo (the editor's "Reset to auto"); null: none
  String? _category;
  bool _busy = false, _show = false;
  String? _error;
  int _discount = 0;
  int _saved = 0;

  @override
  void initState() {
    super.initState();
    loadDiscount().then((v) => _discount = v);
    DraftStore.quick.load().then((s) {
      // an unsaved draft from before a crash or lost signal
      if (mounted && s.drafts.isNotEmpty && _d == null) _open(s.drafts.first, step: 2);
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _open(ProductDraft d, {required int step}) => setState(() {
        _d = d;
        _cut = null;
        _step = step;
        _error = null;
        _category = d.categoryName.isEmpty ? null : d.categoryName;
        _c['name']!.text = d.name;
        _c['brand']!.text = d.brand;
        _c['model']!.text = d.model;
        _c['ram']!.text = d.ram;
        _c['storage']!.text = d.storage;
        _c['color']!.text = d.color;
        _c['mrp']!.text = d.mrpPaise == null ? '' : rupeesText(d.mrpPaise!);
        d.existingProductId ??= existingProductId(d, ref.read(adminProductsProvider).value ?? const []);
        d.pricePaise ??= prefillPrice(d.mrpPaise, _discount);
        _c['price']!.text = d.pricePaise == null ? '' : rupeesText(d.pricePaise!);
        _c['stock']!.text = '${d.stock}';
        _c['about']!.text = d.bullets.join('\n');
      });

  Future<void> _scanLabel({bool gallery = false}) async {
    final bytes = await ref.read(photoPickerProvider)(gallery: gallery);
    if (bytes == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cats = [for (final k in ref.read(adminCategoriesProvider).value ?? const <Category>[]) k.name];
      final d = await ref.read(catalogueAiProvider).readLabel(bytes, categories: cats)
        ..labelPhoto = bytes;
      if (mounted) _open(d, step: 1);
    } catch (e) {
      if (mounted) setState(() => _error = aiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo({bool gallery = false}) async {
    final Uint8List? bytes = await ref.read(photoPickerProvider)(gallery: gallery);
    if (bytes == null || !mounted) return;
    _d!.photo = bytes;
    await DraftStore.quick.save([_d!]);
    setState(() => _busy = true);
    // free, on this phone (ML Kit): cut out, straightened, light evened, on the shop's white square; shown before saving
    Uint8List? auto;
    try {
      final r = await autoProductPhoto(bytes);
      _d!
        ..photo = r.upright
        ..photoFinal = r.auto;
      auto = r.auto;
    } catch (_) {} // not a photo the phone can read: saving says so
    if (mounted) {
      setState(() {
        _cut = auto;
        _busy = false;
        _step = 2;
      });
    }
  }

  Future<void> _editPhoto() async {
    final d = _d!;
    final edited = await editProductPhoto(context, upright: d.photo!, auto: _cut);
    if (edited != null && mounted) setState(() => d.photoFinal = edited);
  }

  /// Copies the form into the draft.
  ProductDraft _apply() {
    final d = _d!;
    d
      ..name = tidy(_c['name']!.text)
      ..brand = brandDisplayName(tidy(_c['brand']!.text))
      ..model = tidy(_c['model']!.text)
      ..ram = tidy(_c['ram']!.text)
      ..storage = tidy(_c['storage']!.text)
      ..color = tidy(_c['color']!.text)
      ..mrpPaise = parseRupees(_c['mrp']!.text)
      ..pricePaise = parseRupees(_c['price']!.text)
      ..stock = int.tryParse(_c['stock']!.text) ?? 0
      ..categoryName = _category ?? ''
      ..bullets = [for (final l in tidy(_c['about']!.text, multiline: true).split('\n')) if (l.isNotEmpty) l.replaceFirst(RegExp(r'^[•\-]\s*'), '')];
    return d;
  }

  Future<void> _save({required bool next}) async {
    if (_busy || !_form.currentState!.validate()) return;
    final d = _apply();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Object? photoError;
      final id = await saveDraft(ref, d,
          categories: ref.read(adminCategoriesProvider).value ?? const [],
          brands: ref.read(adminBrandsProvider).value ?? const [],
          show: _show,
          photoFailed: (e) => photoError ??= e);
      await DraftStore.quick.clear();
      if (!mounted) return;
      _saved++;
      showMessage(
          context,
          photoError != null
              ? '${d.name} saved, but a photo didn’t upload: ${adminError(photoError!)} Add it on the product page.'
              : '${d.name} saved${_show ? '' : ' (hidden from customers)'}');
      setState(() {
        _d = null;
        _step = 0;
        _show = false;
      });
      if (next) {
        await _scanLabel();
      } else if (mounted) {
        context.pushReplacement('/admin/products/$id'); // check it, add more photos or variants
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message : adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirmed(String field) => setState(() {
        _d!.confirm(field);
        final rows = ref.read(adminProductsProvider).value ?? const [];
        _d!
          ..brand = tidy(_c['brand']!.text)
          ..model = tidy(_c['model']!.text);
        _d!.existingProductId = existingProductId(_d!, rows);
      });

  String? _flag(String field) => _d!.ai.contains(field) ? aiFlag : null;

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(adminCategoriesProvider).value ?? const <Category>[];
    return AdminGate(
      child: Scaffold(
        appBar: AppBar(title: Text(_saved == 0 ? 'Quick add' : 'Quick add · $_saved saved')),
        bottomNavigationBar: _step == 2
            ? StickyBar(
                child: Row(children: [
                  Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _save(next: true), child: const Text('Save & add next'))),
                  const SizedBox(width: Space.md),
                  Expanded(child: FilledButton(onPressed: _busy ? null : () => _save(next: false), child: const Text('Save'))),
                ]),
              )
            : null,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.xl),
          child: switch (_step) {
            0 => _capture(
                icon: PhosphorIconsRegular.barcode,
                title: 'Step 1 of 3 · Back label',
                message: 'Photograph the back of the box, or pick a photo of it: model, RAM/storage, colour and MRP are read for you.',
                button: 'Photograph label',
                onTap: _scanLabel,
              ),
            1 => _capture(
                icon: PhosphorIconsRegular.camera,
                title: 'Step 2 of 3 · The product',
                message: 'Photograph the phone or the front of the box, or pick a photo. The background is removed free, on this phone.',
                button: 'Photograph product',
                onTap: _photo,
                skip: () => setState(() => _step = 2),
              ),
            _ => _confirm(cats),
          },
        ),
      ),
    );
  }

  Widget _capture({
    required IconData icon,
    required String title,
    required String message,
    required String button,
    required void Function({bool gallery}) onTap,
    VoidCallback? skip,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: Space.xl),
        Icon(icon, size: 56),
        const SizedBox(height: Space.md),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Space.sm),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: Space.xl),
        if (_error != null) ...[NoteBox(_error!, icon: PhosphorIconsBold.warning), const SizedBox(height: Space.md)],
        FilledButton.icon(
          onPressed: _busy ? null : () => onTap(),
          icon: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(PhosphorIconsRegular.camera),
          label: Text(_busy ? (_step == 0 ? 'Reading…' : 'Removing background…') : _error != null ? 'Retry' : button),
        ),
        TextButton.icon(
          onPressed: _busy ? null : () => onTap(gallery: true),
          icon: const Icon(PhosphorIconsRegular.images),
          label: const Text('Choose from gallery'),
        ),
        if (skip != null) TextButton(onPressed: skip, child: const Text('Skip the photo')),
        if (_error != null && _step == 0)
          TextButton(
            onPressed: () => _open(ProductDraft(id: 'manual'), step: 2),
            child: const Text('Fill in by hand'),
          ),
      ]);

  Widget _field(String key, String label, {String? flag, TextInputType? type, bool multi = false, String? Function(String?)? validator}) => Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: TextFormField(
          controller: _c[key],
          decoration: InputDecoration(labelText: label, helperText: flag == null ? null : _flag(flag)),
          keyboardType: type,
          minLines: multi ? 3 : 1,
          maxLines: multi ? 6 : 1,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => _confirmed(flag ?? key),
          validator: validator,
        ),
      );

  Widget _confirm(List<Category> cats) {
    final d = _d!;
    final existing = d.existingProductId != null;
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        NoteBox(
          existing
              ? 'You already have ${d.brand} ${d.model}. This is saved as a new variant of it.'
              : d.ai.isEmpty
                  ? 'Step 3 of 3 · Check and save.'
                  : 'Step 3 of 3 · $aiFlag. Fields marked AI-filled were read from the photo. Fix anything wrong.',
          tone: existing ? TagTone.deal : TagTone.info,
        ),
        const SizedBox(height: Space.md),
        if (_error != null) ...[NoteBox(_error!, icon: PhosphorIconsBold.warning), const SizedBox(height: Space.md)],
        _field('name', 'Name', flag: 'name', validator: (v) => checkText(v, max: MaxLen.productName, min: 2, what: 'The name')),
        _field('brand', 'Brand', flag: 'brand', validator: (v) => checkText(v, max: 40, min: 1, what: 'The brand')),
        _field('model', 'Model', flag: 'model', validator: (v) => checkText(v, max: 80, min: 1, what: 'The model')),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _field('ram', 'RAM', flag: 'variant')),
          const SizedBox(width: Space.sm),
          Expanded(child: _field('storage', 'Storage', flag: 'variant')),
        ]),
        _field('color', 'Colour', flag: 'variant'),
        PickerField<String>(
          key: ValueKey(_category),
          label: 'Category',
          options: [for (final k in cats) k.name],
          labelOf: (n) => n,
          initialValue: existing ? (_category ?? d.categoryName) : _category,
          onChanged: (v) => setState(() {
            _category = v;
            d.confirm('category');
          }),
          validator: (v) => v == null && !existing ? 'Pick a category.' : null,
        ),
        if (!existing && _flag('category') != null) Text(aiFlag, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: Space.md),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _field('mrp', 'MRP (₹)', flag: 'mrp', type: TextInputType.number, validator: (v) => rupeesError(v, maxPaise: maxAmountPaise, optional: true))),
          const SizedBox(width: Space.sm),
          Expanded(
            child: _field('price', 'Selling price (₹)', type: TextInputType.number, validator: (v) => rupeesError(v, maxPaise: maxAmountPaise, minPaise: 1)),
          ),
        ]),
        if (d.mrpPaise != null && _discount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Text('Price starts at MRP ${formatInr(d.mrpPaise!)} minus $_discount% (Settings).', style: Theme.of(context).textTheme.bodySmall),
          ),
        _field('stock', 'Stock', type: TextInputType.number, validator: (v) => int.tryParse(v ?? '') == null ? 'Enter a whole number.' : null),
        _field('about', 'Description bullets', flag: 'description', multi: true),
        if (d.specs.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: Text('${d.specs.length} specs from the label${_flag('specs') == null ? '' : ' · $aiFlag'}')),
        if (d.photo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.md),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Image.memory(d.photoFinal ?? d.photo!, width: 96, height: 96, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(_cut != null
                    ? 'Background removed, straightened and evened out, like every shop photo'
                    : 'Product photo ready · ${formatBytes(d.photo!.length)}'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _editPhoto,
                icon: const Icon(PhosphorIconsRegular.pencilSimple, size: IconSizes.sm),
                label: const Text('Edit'),
              ),
            ]),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show in shop'),
          subtitle: const Text('Off: saved, hidden from customers until you switch it on'),
          value: _show,
          onChanged: (v) => setState(() => _show = v),
        ),
      ]),
    );
  }
}
