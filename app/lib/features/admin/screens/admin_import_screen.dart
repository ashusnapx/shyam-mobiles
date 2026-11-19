import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/widgets.dart';
import '../data/admin.dart';
import '../data/ai_catalogue.dart';
import '../data/rules.dart';
import '../widgets/admin_widgets.dart';

/// A file staff picked: name and bytes (kept in memory while the import runs).
typedef PickedFile = ({String name, Uint8List bytes});

/// Picks supplier files. A provider so tests need no file dialog.
final filePickerProvider = Provider<Future<List<PickedFile>> Function()>((ref) => () async {
      final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'xlsx', 'csv', 'jpg', 'jpeg', 'png', 'webp']);
      return [for (final f in r) (name: f.name, bytes: await f.readAsBytes())];
    });

const _maxPdfBytes = 18 * 1024 * 1024; // Gemini's inline request limit is 20 MB

/// Staff only. Supplier PDFs, Excel/CSV and photos → a draft list to review, then "Publish selected" saves them
/// hidden; "Show in shop" is a separate tap. Drafts and finished chunks are kept on the phone.
class AdminImportScreen extends ConsumerStatefulWidget {
  const AdminImportScreen({super.key});

  @override
  ConsumerState<AdminImportScreen> createState() => _ImportState();
}

class _ImportState extends ConsumerState<AdminImportScreen> {
  var _drafts = <ProductDraft>[];
  final _done = <String, int>{}; // "name:size" → chunks already read
  final _saved = <String>[]; // product ids saved hidden, waiting for "Show in shop"
  final _failed = <String, String>{}; // draft id → why it did not save
  String? _progress, _error;
  bool _busy = false;
  int _unmatched = 0;
  List<PickedFile> _files = const [];
  int _discount = 0;

  @override
  void initState() {
    super.initState();
    loadDiscount().then((v) => _discount = v);
    DraftStore.import.load().then((s) {
      if (mounted) {
        setState(() {
          _drafts = s.drafts;
          _done.addAll(s.done);
        });
      }
    });
  }

  Future<void> _persist() => DraftStore.import.save(_drafts, _done);

  Future<void> _pick() async {
    final files = await ref.read(filePickerProvider)();
    if (files.isEmpty || !mounted) return;
    _files = files;
    await _run();
  }

  /// Reads every file chunk by chunk; stops at the first failure and keeps what was read. Retry resumes.
  Future<void> _run() async {
    final ai = ref.read(catalogueAiProvider);
    final cats = [for (final k in ref.read(adminCategoriesProvider).value ?? const <Category>[]) k.name];
    setState(() {
      _busy = true;
      _error = null;
      _unmatched = 0;
    });
    try {
      final images = <PickedFile>[];
      for (final (i, f) in _files.indexed) {
        final ext = f.name.split('.').last.toLowerCase();
        if (const ['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
          images.add(f);
          continue;
        }
        final key = '${f.name}:${f.bytes.length}';
        final chunks = _chunks(f, ext);
        for (var c = _done[key] ?? 0; c < chunks.length; c++) {
          setState(() => _progress = 'File ${i + 1} of ${_files.length} · part ${c + 1} of ${chunks.length}');
          final got = await ai.readCatalogue(chunks[c], categories: cats, fileHint: f.name);
          _drafts = [..._drafts, ...got];
          _done[key] = c + 1;
          await _persist();
        }
      }
      await _images(images, ai, cats);
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException && e.message.startsWith('That file') ? e.message : aiErrorMessage(e));
    } finally {
      _classify();
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  List<AiInput> _chunks(PickedFile f, String ext) {
    switch (ext) {
      case 'pdf':
        if (f.bytes.length > _maxPdfBytes) throw const FormatException('That file is too big (over 18 MB). Split the PDF and pick the parts.');
        final pages = pdfPageCount(f.bytes);
        if (pages <= pdfChunkPages) return [(instruction: 'This is a supplier price list or catalogue (India).', text: null, bytes: f.bytes, mime: 'application/pdf')];
        return [
          for (var a = 1; a <= pages; a += pdfChunkPages)
            (
              instruction: 'This is a supplier price list or catalogue (India). Read ONLY pages $a to ${a + pdfChunkPages - 1 > pages ? pages : a + pdfChunkPages - 1} of $pages.',
              text: null,
              bytes: f.bytes,
              mime: 'application/pdf',
            )
        ];
      case 'csv' || 'xlsx':
        final text = ext == 'csv' ? utf8.decode(f.bytes, allowMalformed: true) : sheetsText(f.bytes);
        return [for (final t in textChunks(text)) (instruction: 'This is a supplier price list as text rows (India).', text: t, bytes: null, mime: null)];
      default:
        return const [];
    }
  }

  /// Photos go to the draft named in the file name, else the one Gemini says they show.
  Future<void> _images(List<PickedFile> images, CatalogueAi ai, List<String> cats) async {
    for (final img in images) {
      if (_drafts.isEmpty) {
        // only photos picked: each is a box label or product
        final d = await ai.readLabel(img.bytes, categories: cats);
        d.photo = img.bytes;
        _drafts = [..._drafts, d];
        continue;
      }
      var d = draftForFile(img.name, _drafts);
      if (d == null) {
        final i = await ai.matchImage(img.bytes, [for (final x in _drafts) '${x.brand} ${x.model} ${x.variantLabel}']);
        d = i == null ? null : _drafts[i];
      }
      if (d == null) {
        _unmatched++;
      } else {
        d.photo ??= img.bytes;
      }
    }
    await _persist();
  }

  /// Existing products (this becomes a variant of them) and the price a file gave.
  void _classify() {
    final rows = ref.read(adminProductsProvider).value ?? const [];
    for (final d in _drafts) {
      d.existingProductId ??= existingProductId(d, rows);
    }
  }

  String? _problem(ProductDraft d, Set<String> repeats) {
    if (_failed[d.id] case final why?) {
      return why;
    }
    if (d.pricePaise == null) return 'Enter the selling price';
    if (d.mrpPaise != null && d.mrpPaise! < d.pricePaise!) return 'MRP is below the price';
    if (d.existingProductId == null && d.categoryName.isEmpty) return 'Pick a category';
    return null;
  }

  Future<void> _publish() async {
    final rows = _drafts.where((d) => d.selected && _problem(d, const {}) == null).toList();
    if (rows.isEmpty) return showMessage(context, 'Tick rows that have a price and a category.');
    final cats = ref.read(adminCategoriesProvider).value ?? const <Category>[];
    var brands = ref.read(adminBrandsProvider).value ?? const <Brand>[];
    setState(() {
      _busy = true;
      _failed.clear();
    });
    var n = 0;
    for (final d in rows) {
      setState(() => _progress = 'Saving ${++n} of ${rows.length}');
      try {
        final id = await saveDraft(ref, d, categories: cats, brands: brands);
        _saved.add(id);
        _drafts.remove(d);
        brands = ref.read(adminBrandsProvider).value ?? brands;
      } catch (e) {
        _failed[d.id] = e is FormatException ? e.message : adminError(e);
      }
      await _persist();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
    });
    showMessage(context, '${rows.length - _failed.length} saved, hidden from customers.');
  }

  Future<void> _show() async {
    setState(() => _busy = true);
    try {
      await showInShop(ref, _saved);
      _saved.clear();
      if (mounted) showMessage(context, 'Now showing in the shop.');
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillPrices() {
    setState(() {
      for (final d in _drafts) {
        if (d.selected && d.pricePaise == null) d.pricePaise = prefillPrice(d.mrpPaise, _discount);
      }
    });
    unawaited(_persist());
  }

  Future<void> _edit(ProductDraft d) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditSheet(draft: d, categories: [for (final k in ref.read(adminCategoriesProvider).value ?? const <Category>[]) k.name]),
    );
    if (mounted) setState(() => _classifyOne(d));
    unawaited(_persist());
  }

  void _classifyOne(ProductDraft d) => d.existingProductId = existingProductId(d, ref.read(adminProductsProvider).value ?? const []);

  @override
  Widget build(BuildContext context) {
    final repeats = repeatedDrafts(_drafts);
    final selected = _drafts.where((d) => d.selected).length;
    return AdminGate(
      child: Scaffold(
        appBar: AppBar(title: const Text('Import catalogue')),
        bottomNavigationBar: _drafts.isEmpty && _saved.isEmpty
            ? null
            : StickyBar(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_saved.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _show,
                        icon: const Icon(PhosphorIconsRegular.eye),
                        label: Text('Show ${_saved.length} saved in shop'),
                      ),
                    ),
                  if (_drafts.isNotEmpty)
                    FilledButton(onPressed: _busy ? null : _publish, child: Text('Publish selected ($selected)')),
                ]),
              ),
        body: ListView.builder(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.xl),
          itemCount: _drafts.length + 1,
          itemBuilder: (context, i) {
            if (i > 0) return _row(_drafts[i - 1], repeats);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const NoteBox('Pick supplier PDFs, Excel/CSV files or product photos. Drafts are saved hidden; you tap “Show in shop” after checking.', tone: TagTone.info),
              const SizedBox(height: Space.md),
              FilledButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(PhosphorIconsRegular.fileArrowUp),
                label: Text(_files.isEmpty && _drafts.isEmpty ? 'Pick files' : 'Pick more files'),
              ),
              if (_progress != null) ...[const SizedBox(height: Space.md), const LinearProgressIndicator(), const SizedBox(height: Space.xs), Text(_progress!)],
              if (_error != null) ...[
                const SizedBox(height: Space.md),
                NoteBox(_error!, icon: PhosphorIconsBold.warning),
                if (_files.isNotEmpty) TextButton(onPressed: _busy ? null : _run, child: const Text('Retry from where it stopped')),
              ],
              if (_unmatched > 0) Padding(padding: const EdgeInsets.only(top: Space.sm), child: Text('$_unmatched photos matched no product and were skipped.')),
              if (_drafts.isNotEmpty)
                Wrap(spacing: Space.sm, children: [
                  TextButton(
                    onPressed: () => setState(() {
                      final all = _drafts.every((d) => d.selected);
                      for (final d in _drafts) {
                        d.selected = !all;
                      }
                    }),
                    child: const Text('Select all / none'),
                  ),
                  TextButton(onPressed: _fillPrices, child: Text('Price = MRP − $_discount% where empty')),
                ]),
            ]);
          },
        ),
      ),
    );
  }

  Widget _row(ProductDraft d, Set<String> repeats) {
    final problem = _problem(d, repeats);
    final notes = [
      if (repeats.contains(d.id)) 'Repeated in this list',
      if (d.existingProductId != null) 'Exists: added as a variant',
      if (d.ai.isNotEmpty) aiFlag,
    ];
    return Card(
      child: ListTile(
        key: ValueKey(d.id),
        contentPadding: const EdgeInsets.only(left: Space.xs, right: Space.sm),
        leading: Checkbox(value: d.selected, onChanged: (v) => setState(() => d.selected = v ?? false)),
        title: Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          if (d.variantLabel.isNotEmpty) d.variantLabel,
          if (d.mrpPaise != null) 'MRP ${formatInr(d.mrpPaise!)}',
          ...notes,
          ?problem,
        ].join(' · ')),
        trailing: SizedBox(
          width: 96,
          child: TextFormField(
            key: ValueKey('${d.id}-${d.pricePaise}'),
            initialValue: d.pricePaise == null ? '' : rupeesText(d.pricePaise!),
            decoration: const InputDecoration(labelText: 'Price ₹', isDense: true),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              d.pricePaise = parseRupees(v);
              d.confirm('price');
            },
            onFieldSubmitted: (_) => setState(() {}),
          ),
        ),
        onTap: () => _edit(d),
      ),
    );
  }
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.draft, required this.categories});

  final ProductDraft draft;
  final List<String> categories;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _name = TextEditingController(text: widget.draft.name);
  late final _brand = TextEditingController(text: widget.draft.brand);
  late final _model = TextEditingController(text: widget.draft.model);
  late final _ram = TextEditingController(text: widget.draft.ram);
  late final _storage = TextEditingController(text: widget.draft.storage);
  late final _color = TextEditingController(text: widget.draft.color);
  late final _mrp = TextEditingController(text: widget.draft.mrpPaise == null ? '' : rupeesText(widget.draft.mrpPaise!));
  late final _stock = TextEditingController(text: '${widget.draft.stock}');
  late String _category = widget.draft.categoryName;

  @override
  void dispose() {
    for (final c in [_name, _brand, _model, _ram, _storage, _color, _mrp, _stock]) {
      c.dispose();
    }
    super.dispose();
  }

  void _done() {
    widget.draft
      ..name = tidy(_name.text)
      ..brand = brandDisplayName(tidy(_brand.text))
      ..model = tidy(_model.text)
      ..ram = tidy(_ram.text)
      ..storage = tidy(_storage.text)
      ..color = tidy(_color.text)
      ..mrpPaise = parseRupees(_mrp.text)
      ..stock = int.tryParse(_stock.text) ?? 0
      ..categoryName = _category
      ..ai.clear(); // staff looked at every field
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    Widget f(String label, TextEditingController c, {TextInputType? type}) => Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: TextField(controller: c, decoration: InputDecoration(labelText: label), keyboardType: type),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, MediaQuery.viewInsetsOf(context).bottom + Space.lg),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          f('Name', _name),
          f('Brand', _brand),
          f('Model', _model),
          f('RAM', _ram),
          f('Storage', _storage),
          f('Colour', _color),
          f('MRP (₹)', _mrp, type: TextInputType.number),
          f('Stock', _stock, type: TextInputType.number),
          DropdownButtonFormField<String>(
            initialValue: widget.categories.contains(_category) ? _category : null,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in widget.categories) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => _category = v ?? '',
          ),
          const SizedBox(height: Space.md),
          FilledButton(onPressed: _done, child: const Text('Done')),
        ]),
      ),
    );
  }
}
