import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/backend.dart';
import '../../../core/firebase.dart' show firebaseOptions;
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import 'admin.dart';
import 'catalog_admin_repository.dart';
import 'rules.dart';

/// The Gemini models, the one place to change them (Gemini Developer API through Firebase AI Logic, no billing needed).
/// Flash-Lite reads labels and lists first; Flash only runs when Flash-Lite's answer fails validation.
const aiModelFast = 'gemini-3.5-flash-lite';
const aiModelStrong = 'gemini-3.8-flash';

/// AI-filled fields show "AI-filled · check" until staff edit them.
const aiFlag = 'AI-filled · check';

/// One product (or variant) as the AI read it, before staff save it. Fields in [ai] are unconfirmed.
class ProductDraft {
  ProductDraft({
    required this.id,
    this.brand = '',
    this.model = '',
    this.ram = '',
    this.storage = '',
    this.color = '',
    this.mrpPaise,
    this.pricePaise,
    this.stock = 0,
    this.ean = '',
    this.categoryName = '',
    this.name = '',
    this.bullets = const [],
    this.specs = const [],
    Set<String>? ai,
    this.selected = true,
    this.existingProductId,
    this.photo,
    this.fileHint = '',
  }) : ai = ai ?? {};

  final String id;
  String brand, model, ram, storage, color, ean, categoryName, name, fileHint;
  int? mrpPaise, pricePaise; // selling price: only from the file or typed by staff, never guessed
  int stock;
  List<String> bullets;
  List<Spec> specs;
  final Set<String> ai;
  bool selected;
  String? existingProductId;
  Uint8List? photo; // kept in memory only
  Uint8List? photoFinal; // cleaned up (and maybe edited) on this phone: uploaded as it is
  Uint8List? labelPhoto; // the box label read in Quick add; the product's second photo

  /// Editing a field confirms it.
  void confirm(String field) => ai.remove(field);

  String get variantLabel => variantName([ram, storage, color]);

  Map<String, dynamic> toJson() => {
        'id': id, 'brand': brand, 'model': model, 'ram': ram, 'storage': storage, 'color': color, 'mrp': mrpPaise,
        'price': pricePaise, 'stock': stock, 'ean': ean, 'category': categoryName, 'name': name, 'bullets': bullets,
        'specs': [for (final s in specs) s.toJson()], 'ai': ai.toList(), 'selected': selected, 'file': fileHint,
      };

  factory ProductDraft.fromJson(Map<String, dynamic> j) => ProductDraft(
        id: j['id'] as String, brand: j['brand'] ?? '', model: j['model'] ?? '', ram: j['ram'] ?? '',
        storage: j['storage'] ?? '', color: j['color'] ?? '', mrpPaise: j['mrp'] as int?, pricePaise: j['price'] as int?,
        stock: j['stock'] ?? 0, ean: j['ean'] ?? '', categoryName: j['category'] ?? '', name: j['name'] ?? '',
        bullets: [for (final b in j['bullets'] as List? ?? const []) '$b'],
        specs: [for (final s in j['specs'] as List? ?? const []) Spec(s['label'], s['value'])],
        ai: {for (final a in j['ai'] as List? ?? const []) '$a'}, selected: j['selected'] ?? true, fileHint: j['file'] ?? '',
      );
}

int _seq = 0;
String _draftId() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

/// 74999 / "74,999" / "₹74999.50" → paise; null for blank, zero, negative or over the shop's cap.
int? paiseOf(Object? v) {
  final text = switch (v) {
    num n => n.toString(),
    String s => s,
    _ => '',
  };
  final p = parseRupees(text);
  return p == null || p <= 0 || p > maxAmountPaise ? null : p;
}

String _s(Object? v, int max) {
  final t = tidy(v is String ? v : v == null ? '' : '$v');
  return t.length <= max ? t : t.substring(0, max).trim();
}

/// One AI product object → a draft, with everything it filled flagged. Null when it has neither brand nor model
/// (the answer is not usable: the caller retries with the stronger model). [categories]: the shop's category names.
ProductDraft? draftFromJson(Object? json, {List<String> categories = const [], String fileHint = ''}) {
  if (json is! Map) return null;
  final brand = brandDisplayName(_s(json['brand'], 40));
  final model = _s(json['model'], 80);
  if (brand.isEmpty || model.isEmpty) return null;
  final cat = _s(json['category'], 60);
  final category = categories.firstWhere((c) => c.toLowerCase() == cat.toLowerCase(), orElse: () => '');
  final name = _s(json['name'], MaxLen.productName);
  final d = ProductDraft(
    id: _draftId(),
    brand: brand,
    model: model,
    ram: _s(json['ram'], 20),
    storage: _s(json['storage'], 20),
    color: _s(json['color'], 40),
    mrpPaise: paiseOf(json['mrpRupees']),
    pricePaise: paiseOf(json['sellingRupees']),
    ean: _s(json['ean'], 20).replaceAll(RegExp(r'[^0-9A-Za-z]'), ''),
    categoryName: category,
    name: name.isEmpty ? '$brand $model' : name,
    bullets: [for (final b in (json['bullets'] as List? ?? const []).take(4)) if (_s(b, 200).isNotEmpty) _s(b, 200)],
    specs: [
      for (final s in (json['specs'] as List? ?? const []).take(20))
        if (s is Map && _s(s['label'], 40).isNotEmpty && _s(s['value'], 120).isNotEmpty) Spec(_s(s['label'], 40), _s(s['value'], 120))
    ],
    fileHint: fileHint,
  );
  d.ai.addAll([
    'name', 'brand', 'model',
    if (d.ram.isNotEmpty || d.storage.isNotEmpty || d.color.isNotEmpty) 'variant',
    if (d.mrpPaise != null) 'mrp',
    if (d.pricePaise != null) 'price',
    if (category.isNotEmpty) 'category',
    if (d.bullets.isNotEmpty) 'description',
    if (d.specs.isNotEmpty) 'specs',
  ]);
  return d;
}

/// The AI's `{"products": [...]}` text → drafts. Throws FormatException on broken JSON.
List<ProductDraft> draftsFromText(String text, {List<String> categories = const [], String fileHint = ''}) {
  final json = jsonDecode(text);
  final list = json is Map ? json['products'] : json;
  if (list is! List) throw const FormatException('No product list in the answer.');
  return [for (final p in list) ?draftFromJson(p, categories: categories, fileHint: fileHint)];
}

/// Selling price prefill: MRP minus the shop's default discount, to the whole rupee. Null without an MRP. 0% → the MRP.
int? prefillPrice(int? mrpPaise, num discountPct) {
  if (mrpPaise == null) return null;
  final pct = discountPct.clamp(0, 90);
  return ((mrpPaise * (100 - pct) / 100) / 100).round() * 100;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// The saved product with the same brand and model (exact match after dropping case, spaces and punctuation; the
/// product name may or may not start with the brand). Null when none.
String? existingProductId(ProductDraft d, List<AdminProductRow> rows) {
  final brand = _norm(d.brand), model = _norm(d.model);
  if (brand.isEmpty || model.isEmpty) return null;
  for (final r in rows) {
    if (_norm(r.brandName) != brand) continue;
    var n = _norm(r.name);
    if (n.startsWith(brand)) n = n.substring(brand.length);
    if (n == model) return r.id;
  }
  return null;
}

/// Ids of drafts that repeat an earlier draft (same brand, model and variant).
Set<String> repeatedDrafts(List<ProductDraft> drafts) {
  final seen = <String>{};
  return {
    for (final d in drafts)
      if (!seen.add(_norm('${d.brand}|${d.model}|${d.ram}|${d.storage}|${d.color}'))) d.id
  };
}

/// Drafts whose brand+model matches [others]'s image file name tokens: "galaxy-a55-blue.jpg" → the A55 draft.
ProductDraft? draftForFile(String fileName, List<ProductDraft> drafts) {
  final f = _norm(fileName.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), ''));
  ProductDraft? best;
  for (final d in drafts) {
    final m = _norm(d.model);
    if (m.length >= 3 && f.contains(m) && (best == null || m.length > _norm(best.model).length)) best = d;
  }
  return best;
}

/// What the AI is given: text, a PDF or an image, plus what to do with it. Never any customer data.
typedef AiInput = ({String instruction, String? text, Uint8List? bytes, String? mime});

/// The Gemini call, behind an interface so screens and tests don't need Firebase.
abstract interface class CatalogueAi {
  /// Reads a box's back label (or a product photo) into one draft. Throws on an unusable answer.
  Future<ProductDraft> readLabel(Uint8List image, {List<String> categories = const []});

  /// Reads a price list / catalogue chunk into drafts (may be empty).
  Future<List<ProductDraft>> readCatalogue(AiInput input, {List<String> categories = const [], String fileHint = ''});

  /// The index in [names] the photo shows, or null.
  Future<int?> matchImage(Uint8List image, List<String> names);
}

/// A message staff can act on for any failure of the AI call.
String aiErrorMessage(Object e) => switch (e) {
      QuotaExceeded() => 'The free AI limit is used up for now. Wait a minute, then tap Retry.',
      ServiceApiNotEnabled() || InvalidApiKey() => 'The AI is not switched on for this shop yet. Ask the developer.',
      UnsupportedUserLocation() => 'The AI is not available in this location.',
      FormatException() => 'The AI could not read that. Try a clearer, closer photo or file, then Retry.',
      _ => 'Could not reach the AI. Check the internet, then tap Retry.',
    };

const _productProps = <String, String>{
  'brand': 'Brand on the pack, e.g. Samsung',
  'model': 'Model name without brand, e.g. Galaxy A55 5G',
  'ram': 'RAM like "8 GB", else empty',
  'storage': 'Storage like "256 GB", else empty',
  'color': 'Colour name, else empty',
  'ean': 'EAN / barcode digits only if printed, else empty',
  'name': '"Brand Model" display name',
};

Schema _productSchema(List<String> categories) => Schema.object(
      properties: {
        for (final e in _productProps.entries) e.key: Schema.string(description: e.value),
        'mrpRupees': Schema.number(description: 'Printed MRP in rupees (Indian boxes: "MRP ₹... incl. of all taxes"); omit if not printed'),
        'sellingRupees': Schema.number(description: 'A selling/offer price ONLY if the document explicitly gives one; never compute or guess'),
        if (categories.isNotEmpty) 'category': Schema.enumString(enumValues: categories, description: 'Closest category'),
        'bullets': Schema.array(items: Schema.string(), description: 'Up to 4 short description bullets, facts you are confident about'),
        'specs': Schema.array(
          items: Schema.object(properties: {'label': Schema.string(), 'value': Schema.string()}),
          description: 'Key specs you are confident about',
        ),
      },
      optionalProperties: ['ram', 'storage', 'color', 'ean', 'name', 'mrpRupees', 'sellingRupees', 'category', 'bullets', 'specs'],
    );

const _rules = 'Only state facts visible in the input. Never invent prices, specs or barcodes: omit what you cannot see.';

/// Gemini through Firebase AI Logic. App Check is required by AI Logic: Play Integrity in release, the debug provider
/// otherwise (register its token in the Firebase console, see docs).
class GeminiCatalogueAi implements CatalogueAi {
  static Future<void>? _ready;

  static Future<void> _init() => _ready ??= _start();

  static Future<void> _start() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: firebaseOptions);
      if (!useEmulators) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: kReleaseMode ? const AndroidPlayIntegrityProvider() : const AndroidDebugProvider(),
        );
      }
    } catch (_) {
      _ready = null; // try again on the next call
      rethrow;
    }
  }

  Future<String> _generate(String model, Schema schema, List<Part> parts) async {
    await _init();
    final m = FirebaseAI.googleAI().generativeModel(
      model: model,
      generationConfig: GenerationConfig(responseMimeType: 'application/json', responseSchema: schema, temperature: 0),
    );
    final text = (await m.generateContent([Content.multi(parts)])).text;
    if (text == null || text.isEmpty) throw const FormatException('Empty answer.');
    return text;
  }

  /// Flash-Lite first; Flash when the answer is not a usable result. Quota and network errors are not retried.
  Future<T> _validated<T>(Future<T> Function(String model) run) async {
    try {
      return await run(aiModelFast);
    } on FormatException {
      return run(aiModelStrong);
    }
  }

  @override
  Future<ProductDraft> readLabel(Uint8List image, {List<String> categories = const []}) => _validated((model) async {
        final text = await _generate(
          model,
          Schema.object(properties: {'products': Schema.array(items: _productSchema(categories))}),
          [
            const TextPart('This is the back label or front of a phone-shop product box (India). Return one product in `products`. $_rules'),
            InlineDataPart('image/jpeg', image),
          ],
        );
        final drafts = draftsFromText(text, categories: categories);
        if (drafts.isEmpty) throw const FormatException('No product found.');
        return drafts.first;
      });

  @override
  Future<List<ProductDraft>> readCatalogue(AiInput input, {List<String> categories = const [], String fileHint = ''}) =>
      _validated((model) async {
        final text = await _generate(
          model,
          Schema.object(properties: {'products': Schema.array(items: _productSchema(categories))}),
          [
            TextPart('${input.instruction}\nList each product variant (one per RAM/storage/colour row) with its MRP. $_rules'),
            if (input.text != null) TextPart(input.text!),
            if (input.bytes != null) InlineDataPart(input.mime!, input.bytes!),
          ],
        );
        return draftsFromText(text, categories: categories, fileHint: fileHint);
      });

  @override
  Future<int?> matchImage(Uint8List image, List<String> names) async {
    final text = await _generate(
      aiModelFast,
      Schema.object(properties: {'index': Schema.integer(description: 'Index of the matching product, -1 when none')}),
      [
        TextPart('Which product does this photo show? Products:\n${[for (final (i, n) in names.indexed) '$i: $n'].join('\n')}\nAnswer -1 if unsure.'),
        InlineDataPart('image/jpeg', image),
      ],
    );
    final i = (jsonDecode(text) as Map)['index'];
    return i is int && i >= 0 && i < names.length ? i : null;
  }
}

final catalogueAiProvider = Provider<CatalogueAi>((ref) => GeminiCatalogueAi());

/// Takes a photo (camera) and returns its bytes; null when cancelled. A provider so tests need no camera.
final photoPickerProvider = Provider<Future<Uint8List?> Function({bool gallery})>((ref) => ({bool gallery = false}) async {
      final f = await ImagePicker()
          .pickImage(source: gallery ? ImageSource.gallery : ImageSource.camera, maxWidth: 2000, imageQuality: 85);
      return f?.readAsBytes();
    });

// Local state -------------------------------------------------------------------

const _discountKey = 'ai_default_discount_pct';
const _importKey = 'ai_import_v1';
const _quickKey = 'ai_quick_v1';

/// Admin → Settings → default discount % (kept on this phone), 0 when never set.
Future<int> loadDiscount() async => (await SharedPreferences.getInstance()).getInt(_discountKey) ?? 0;
Future<void> saveDiscount(int pct) async => (await SharedPreferences.getInstance()).setInt(_discountKey, pct.clamp(0, 90));

/// Unsaved drafts live here until saved, so a crash or no signal loses nothing. Photos are not kept.
class DraftStore {
  const DraftStore(this.key);

  static const quick = DraftStore(_quickKey);
  static const import = DraftStore(_importKey);

  final String key;

  Future<({List<ProductDraft> drafts, Map<String, int> done})> load() async {
    try {
      final j = jsonDecode((await SharedPreferences.getInstance()).getString(key) ?? '') as Map<String, dynamic>;
      return (
        drafts: [for (final d in j['drafts'] as List) ProductDraft.fromJson(d as Map<String, dynamic>)],
        done: {for (final e in (j['done'] as Map? ?? const {}).entries) '${e.key}': e.value as int},
      );
    } catch (_) {
      return (drafts: <ProductDraft>[], done: <String, int>{});
    }
  }

  /// [done]: chunks already read per file ("name:size" → count), so a retry resumes after the last good chunk.
  Future<void> save(List<ProductDraft> drafts, [Map<String, int> done = const {}]) async => (await SharedPreferences.getInstance())
      .setString(key, jsonEncode({'drafts': [for (final d in drafts) d.toJson()], 'done': done}));

  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(key);
}

// Saving ------------------------------------------------------------------------

String _slugFor(String name) {
  final s = slugify(name);
  return s.length <= MaxLen.slug ? s : s.substring(0, MaxLen.slug).replaceAll(RegExp(r'-+$'), '');
}

String skuFor(ProductDraft d) {
  final base = slugify('${d.brand} ${d.model} ${d.ram} ${d.storage} ${d.color}').toUpperCase();
  final tail = DateTime.now().microsecondsSinceEpoch.toRadixString(36).toUpperCase();
  final cut = base.length > 50 ? base.substring(0, 50).replaceAll(RegExp(r'-+$'), '') : base;
  return '$cut-${tail.substring(tail.length - 6)}';
}

/// Saves [d] through the normal admin paths (both backends): the product (hidden unless [show]) or, when
/// [ProductDraft.existingProductId] is set, a new variant on it; then its photo. Returns the product id.
/// Throws FormatException when the price is missing or the variant already exists.
/// [photoFailed]: told when a photo didn't upload (the product is saved; add it again from its edit screen).
Future<String> saveDraft(WidgetRef ref, ProductDraft d,
    {required List<Category> categories, required List<Brand> brands, bool show = false, void Function(Object)? photoFailed}) async {
  final price = d.pricePaise;
  if (price == null) throw const FormatException('Enter the selling price first.');
  final mrp = d.mrpPaise ?? price;
  if (mrp < price) throw const FormatException('The MRP can’t be below the selling price.');
  String? pid = d.existingProductId;
  var sort = 0;
  if (pid != null) {
    final p = await ref.read(catalogAdminRepositoryProvider).product(pid);
    final label = _norm(d.variantLabel);
    if (p.variants.any((v) => _norm(variantName([v.attributes['ram'] as String?, v.attributes['storage'] as String?, v.attributes['color'] as String?].whereType<String>().toList())) == label)) {
      throw const FormatException('That product already has this variant.');
    }
    sort = p.variants.length;
  } else {
    final category = categories.where((c) => c.name.toLowerCase() == d.categoryName.toLowerCase()).firstOrNull;
    if (category == null) throw const FormatException('Pick a category first.');
    final brand = brands.where((b) => b.name.toLowerCase() == d.brand.toLowerCase()).firstOrNull ?? await createBrand(ref, d.brand);
    final name = tidy(d.name).isEmpty ? '${d.brand} ${d.model}' : tidy(d.name);
    pid = await saveProduct(ref, null, {
      'name': name,
      'slug': _slugFor(name),
      'brand_id': brand.id,
      'category_id': category.id,
      'description': d.bullets.map((b) => '• $b').join('\n'),
      'specs': [for (final s in d.specs) s.toJson()],
      'gst_rate': 18,
      'is_active': show,
      'is_featured': false,
    });
  }
  await saveVariant(ref, pid, null, {
    'sku': skuFor(d),
    'name': d.variantLabel.isEmpty ? 'Standard' : d.variantLabel,
    'attributes': {
      if (d.ram.isNotEmpty) 'ram': d.ram,
      if (d.storage.isNotEmpty) 'storage': d.storage,
      if (d.color.isNotEmpty) 'color': d.color,
      if (d.ean.isNotEmpty) 'ean': d.ean,
    },
    'price_paise': price,
    'mrp_paise': mrp,
    'stock': d.stock,
    'is_active': true,
    'made_to_order': false,
    'lead_days': 2,
    'sort': sort,
  });
  if (d.existingProductId == null) {
    // the product first (the cover), then its box label
    final photos = [
      if (d.photoFinal ?? d.photo case final p?) (p, d.photoFinal != null),
      if (d.labelPhoto case final l?) (l, false),
    ];
    for (final (i, (photo, ready)) in photos.indexed) {
      try {
        await addProductImage(ref, pid, photo, i, ready: ready);
      } catch (e) {
        photoFailed?.call(e);
      }
    }
  }
  return pid;
}

/// Makes saved products visible to customers (staff tapped "Show in shop"). Full fields are re-sent: the Firebase
/// saveProduct callable replaces the product.
Future<void> showInShop(WidgetRef ref, Iterable<String> productIds) async {
  for (final id in productIds) {
    final p = await ref.read(catalogAdminRepositoryProvider).product(id);
    await saveProduct(ref, id, {
      'name': p.name,
      'slug': p.slug,
      'brand_id': p.brand.id,
      'category_id': p.category.id,
      'description': p.description,
      'specs': [for (final s in p.specs) s.toJson()],
      'gst_rate': p.gstRate,
      'is_active': true,
      'is_featured': p.isFeatured,
    });
  }
}

// Splitting a supplier file into AI-sized chunks ---------------------------------

/// Pages per AI call for a PDF.
const pdfChunkPages = 20;

/// Rows per AI call for a spreadsheet or CSV (the header line goes with every chunk).
const sheetChunkRows = 150;

/// The PDF's page count, counted from its page objects. shortcut: 0 when pages sit in compressed object streams
/// (then the whole PDF goes in one call); upgrade to a PDF parser if suppliers send those.
int pdfPageCount(Uint8List bytes) => RegExp(r'/Type\s*/Page(?![a-zA-Z])').allMatches(latin1.decode(bytes, allowInvalid: true)).length;

/// Text lines → chunks of [rows] data lines, each starting with the header line.
List<String> textChunks(String text, {int rows = sheetChunkRows}) {
  final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
  if (lines.length <= rows + 1) return lines.isEmpty ? const [] : [lines.join('\n')];
  final header = lines.first;
  return [for (var i = 1; i < lines.length; i += rows) [header, ...lines.sublist(i, (i + rows).clamp(0, lines.length))].join('\n')];
}

/// Every sheet of an .xlsx as tab separated text, one line per row.
String sheetsText(Uint8List xlsx) {
  final out = StringBuffer();
  for (final t in Excel.decodeBytes(xlsx).tables.values) {
    for (final row in t.rows) {
      final cells = [for (final c in row) c?.value?.toString() ?? ''];
      if (cells.any((c) => c.isNotEmpty)) out.writeln(cells.join('\t'));
    }
  }
  return out.toString();
}
