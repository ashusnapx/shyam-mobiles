// AI catalogue builder: JSON → draft mapping on fixture answers, duplicate detection, the price prefill rule, and the
// Quick add and Import screens with a fake AI (no Firebase, no camera, no file dialog).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/admin/data/admin.dart';
import 'package:shyam_mobiles/features/admin/data/ai_catalogue.dart';
import 'package:shyam_mobiles/features/admin/data/catalog_admin_repository.dart';
import 'package:shyam_mobiles/features/admin/data/photo_store.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_import_screen.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_quick_add_screen.dart';

import '../../fakes/fake_catalog_admin_repository.dart';
import '../../fakes/fake_photo_store.dart';
import '../repairs/layout_harness.dart';

const _cats = ['Smartphones', 'Chargers'];

/// What Gemini returns for a back label (fixture).
const _labelAnswer = '''
{"products":[{"brand":"samsung","model":"Galaxy A55 5G","ram":"8 GB","storage":"256 GB","color":"Awesome Navy",
"mrpRupees":39999,"ean":"8806095 123456","category":"Smartphones","name":"Samsung Galaxy A55 5G",
"bullets":["50 MP camera","5000 mAh battery","","x","y","z"],"specs":[{"label":"Display","value":"6.6 inch"},{"label":"","value":"?"}]}]}''';

ProductDraft _draft(String model, {String brand = 'Samsung', int? mrp = 3999900, String ram = '', String storage = ''}) =>
    ProductDraft(id: model, brand: brand, model: model, name: '$brand $model', mrpPaise: mrp, ram: ram, storage: storage, categoryName: 'Smartphones', ai: {'name', 'mrp'});

class _FakeAi implements CatalogueAi {
  _FakeAi(this.label, [this.catalogue = const []]);

  final List<ProductDraft> label;
  final List<ProductDraft> catalogue;
  var labelCalls = 0;
  var catalogueCalls = 0;
  Exception? failOnce;

  @override
  Future<ProductDraft> readLabel(Uint8List image, {List<String> categories = const []}) async {
    if (failOnce case final e?) {
      failOnce = null;
      throw e;
    }
    return label[labelCalls++ % label.length];
  }

  @override
  Future<List<ProductDraft>> readCatalogue(AiInput input, {List<String> categories = const [], String fileHint = ''}) async {
    catalogueCalls++;
    return catalogue;
  }

  @override
  Future<int?> matchImage(Uint8List image, List<String> names) async => null;
}

void main() {
  group('JSON → draft', () {
    test('maps a label answer: tidy, capped, flagged, MRP in paise', () {
      final d = draftsFromText(_labelAnswer, categories: _cats).single;
      expect(d.brand, 'Samsung');
      expect(d.mrpPaise, 3999900);
      expect(d.pricePaise, isNull); // the AI never sets a selling price unless the file gives one
      expect(d.ean, '8806095123456');
      expect(d.categoryName, 'Smartphones');
      expect(d.bullets, ['50 MP camera', '5000 mAh battery', 'x']); // first 4 taken, blank dropped
      expect(d.specs.map((s) => s.label), ['Display']);
      expect(d.variantLabel, '8 GB · 256 GB · Awesome Navy');
      expect(d.ai, containsAll(['name', 'brand', 'model', 'variant', 'mrp', 'category', 'description', 'specs']));
      d.confirm('mrp');
      expect(d.ai.contains('mrp'), isFalse);
    });

    test('a selling price only when the file gives one; bad money is dropped', () {
      final d = draftFromJson({'brand': 'Itel', 'model': 'A60', 'mrpRupees': '₹7,499', 'sellingRupees': 6999}, categories: _cats)!;
      expect(d.mrpPaise, 749900);
      expect(d.pricePaise, 699900);
      final bad = draftFromJson({'brand': 'Itel', 'model': 'A60', 'mrpRupees': -5, 'sellingRupees': 'free'})!;
      expect(bad.mrpPaise, isNull);
      expect(bad.pricePaise, isNull);
      expect(draftFromJson({'brand': 'Itel', 'model': 'A60', 'category': 'Toys'}, categories: _cats)!.categoryName, '');
    });

    test('unusable answers: no brand or model → null; broken JSON throws', () {
      expect(draftFromJson({'brand': '', 'model': 'X'}), isNull);
      expect(draftFromJson('nope'), isNull);
      expect(draftsFromText('{"products":[{"model":"X"}]}'), isEmpty);
      expect(() => draftsFromText('not json'), throwsFormatException);
      expect(() => draftsFromText('{"x":1}'), throwsFormatException);
    });

    test('draft survives local storage', () {
      final d = draftsFromText(_labelAnswer, categories: _cats).single..pricePaise = 3500000;
      final back = ProductDraft.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
      expect(back.toJson(), d.toJson());
    });
  });

  group('price prefill', () {
    test('MRP minus the default discount, whole rupees; 0% is the MRP; no MRP, no price', () {
      expect(prefillPrice(3999900, 0), 3999900);
      expect(prefillPrice(3999900, 10), 3599900); // 39,999 − 10% = 35,999.10 → ₹35,999
      expect(prefillPrice(749900, 7), 697400); // 6,974.07 → ₹6,974
      expect(prefillPrice(null, 10), isNull);
      expect(prefillPrice(100000, 500), 10000); // capped at 90% off
    });
  });

  group('duplicates', () {
    AdminProductRow row(String id, String name, String brand) => AdminProductRow(
        id: id, name: name, brandName: brand, categoryName: 'Phones', isActive: true, isFeatured: false, coverPath: null,
        activeVariants: 1, stock: 1, lowStock: false);
    final rows = [row('a55', 'Samsung Galaxy A55 5G', 'Samsung'), row('a5', 'Galaxy A5', 'Samsung')];

    test('same brand + model matches, with or without the brand in the name, ignoring case and punctuation', () {
      expect(existingProductId(_draft('galaxy a55-5g'), rows), 'a55');
      expect(existingProductId(_draft('Galaxy A5'), rows), 'a5');
      expect(existingProductId(_draft('Galaxy A55'), rows), isNull); // conservative: exact model only
      expect(existingProductId(_draft('Galaxy A55 5G', brand: 'Vivo'), rows), isNull);
    });

    test('repeats inside one list', () {
      final a = _draft('A', ram: '8 GB'), b = _draft('A', ram: '8 GB')..toJson(), c = _draft('A', ram: '12 GB');
      final ds = [a, ProductDraft(id: 'other', brand: 'Samsung', model: 'A', ram: '8 GB'), c];
      expect(repeatedDrafts(ds), {'other'});
      expect(b.model, 'A');
    });

    test('an image file name picks the draft whose model it contains', () {
      final ds = [_draft('A55'), _draft('A55 Pro'), _draft('S25')];
      expect(draftForFile('galaxy-a55-pro-blue.jpg', ds)!.model, 'A55 Pro');
      expect(draftForFile('IMG_2231.jpg', ds), isNull);
    });
  });

  group('chunking', () {
    test('text chunks repeat the header', () {
      final text = ['h', for (var i = 0; i < 5; i++) 'r$i'].join('\n');
      final chunks = textChunks(text, rows: 2);
      expect(chunks, ['h\nr0\nr1', 'h\nr2\nr3', 'h\nr4']);
      expect(textChunks('h\nr', rows: 2), ['h\nr']);
      expect(textChunks('  \n'), isEmpty);
    });

    test('PDF page count from page objects', () {
      final pdf = Uint8List.fromList(latin1.encode('<</Type /Pages>> <</Type /Page /A>> <</Type/Page>> <</Type /Page>>'));
      expect(pdfPageCount(pdf), 3);
    });
  });

  group('screens', () {
    late FakeCatalogAdminRepository repo;
    late FakePhotoStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = FakeCatalogAdminRepository();
      store = FakePhotoStore();
    });

    List<Override> overrides(CatalogueAi ai, {List<PickedFile> files = const []}) => [
          catalogueAiProvider.overrideWithValue(ai),
          photoPickerProvider.overrideWithValue(() async => Uint8List.fromList([1, 2, 3])),
          filePickerProvider.overrideWithValue(() async => files),
          catalogAdminRepositoryProvider.overrideWithValue(repo),
          photoStoreProvider.overrideWithValue(store),
          adminCategoriesProvider.overrideWithValue(const AsyncData([
            Category(id: 'c1', slug: 'smartphones', name: 'Smartphones', kind: CategoryKind.phone),
          ])),
          adminBrandsProvider.overrideWithValue(const AsyncData([Brand(id: 'samsung', slug: 'samsung', name: 'Samsung')])),
          adminProductsProvider.overrideWithValue(const AsyncData([
            AdminProductRow(id: 'a55', name: 'Samsung Galaxy A55 5G', brandName: 'Samsung', categoryName: 'Smartphones', isActive: true,
                isFeatured: false, coverPath: null, activeVariants: 1, stock: 1, lowStock: false),
          ])),
        ];

    testWidgets('Quick add: label → photo → confirm → Save & next saves hidden and reopens the camera step', (tester) async {
      final ai = _FakeAi([_draft('Galaxy S25', mrp: 7499900), _draft('Galaxy A15', mrp: 1499900)]);
      await pumpScreen(tester, const AdminQuickAddScreen(), overrides: overrides(ai));
      await tester.tap(find.text('Photograph label'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Photograph product'), findsOneWidget);
      await tester.tap(find.text('Skip the photo'));
      await tester.pump();
      expect(find.textContaining(aiFlag), findsWidgets); // flagged until edited
      expect(find.widgetWithText(TextFormField, '74999'), findsNWidgets(2)); // MRP, and the price = MRP at 0% discount
      await tester.tap(find.text('Save & next'));
      await tester.pump();
      await tester.pump();
      expect(repo.calls, containsAllInOrder(['saveProduct new', 'saveVariant p0 new']));
      expect(repo.savedProducts['p0']!['is_active'], false); // never shown to customers without a tap
      expect(find.text('Photograph product'), findsOneWidget); // the next item's label was read
    });

    testWidgets('Quick add: an existing brand + model is saved as a variant, not a duplicate', (tester) async {
      final ai = _FakeAi([_draft('Galaxy A55 5G', ram: '8 GB')]);
      repo.productsById['a55'] = const Product(
        id: 'a55', slug: 'a55', name: 'Samsung Galaxy A55 5G',
        brand: Brand(id: 'samsung', slug: 'samsung', name: 'Samsung'),
        category: Category(id: 'c1', slug: 'smartphones', name: 'Smartphones', kind: CategoryKind.phone),
      );
      await pumpScreen(tester, const AdminQuickAddScreen(), overrides: overrides(ai));
      await tester.tap(find.text('Photograph label'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Skip the photo'));
      await tester.pump();
      expect(find.textContaining('saved as a new variant'), findsOneWidget);
      await tester.tap(find.text('Save & next'));
      await tester.pump();
      await tester.pump();
      expect(repo.calls.where((c) => c.startsWith('saveProduct')), isEmpty);
      expect(repo.calls, contains('saveVariant a55 new'));
    });

    testWidgets('Quick add: a quota error shows a retry message', (tester) async {
      final ai = _FakeAi([_draft('Galaxy S25')])..failOnce = const FormatException('x');
      await pumpScreen(tester, const AdminQuickAddScreen(), overrides: overrides(ai));
      await tester.tap(find.text('Photograph label'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('could not read that'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Photograph product'), findsOneWidget);
    });

    testWidgets('Import: review table warns, needs a price, saves hidden, then Show in shop', (tester) async {
      final ai = _FakeAi([], [_draft('Galaxy A55 5G'), _draft('Galaxy S25', mrp: 7499900), _draft('Galaxy S25', mrp: 7499900)]);
      final file = (name: 'list.csv', bytes: Uint8List.fromList(utf8.encode('model,mrp\nx,1')));
      await pumpScreen(tester, const AdminImportScreen(), overrides: overrides(ai, files: [file]));
      await tester.tap(find.text('Pick files'));
      await tester.pump();
      await tester.pump();
      expect(ai.catalogueCalls, 1);
      expect(find.textContaining('Exists: added as a variant'), findsOneWidget);
      expect(find.textContaining('Repeated in this list'), findsOneWidget);
      expect(find.textContaining('Enter the selling price'), findsWidgets); // the third row is below the fold
      // nothing without a price is saved
      await tester.tap(find.text('Publish selected (3)'));
      await tester.pump();
      expect(repo.calls.where((c) => c.startsWith('save')), isEmpty);
      await tester.tap(find.textContaining('Price = MRP'));
      await tester.pump();
      repo.productsById['a55'] = const Product(
        id: 'a55', slug: 'a55', name: 'Samsung Galaxy A55 5G',
        brand: Brand(id: 'samsung', slug: 'samsung', name: 'Samsung'),
        category: Category(id: 'c1', slug: 'smartphones', name: 'Smartphones', kind: CategoryKind.phone),
      );
      await tester.tap(find.text('Publish selected (3)'));
      await tester.pump();
      await tester.pump();
      expect(repo.calls.where((c) => c == 'saveProduct new'), hasLength(2)); // the two S25 rows are two products here
      expect(repo.calls, contains('saveVariant a55 new'));
      expect(repo.savedProducts.values.every((p) => p['is_active'] == false), isTrue);
      expect(find.textContaining('Show 3 saved in shop'), findsOneWidget);
      await tester.tap(find.textContaining('Show 3 saved in shop'));
      await tester.pump();
      await tester.pump();
      expect(repo.savedProducts['a55']!['is_active'], true);
    });
  });
}
