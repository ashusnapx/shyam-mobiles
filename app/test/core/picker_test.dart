import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/core/widgets/picker.dart';

final _brands = ['Samsung', 'Apple', 'OnePlus', 'Xiaomi', 'vivo', 'OPPO', 'realme', 'LAVA', 'Nokia', 'Motorola'];

Future<GlobalKey<FormState>> _pump(
  WidgetTester tester, {
  String? initial,
  Future<String?> Function(String)? onCreate,
  ValueChanged<String>? onChanged,
  List<String>? options,
}) async {
  tester.view.physicalSize = const Size(1080, 2400); // 360x800 dp
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final form = GlobalKey<FormState>();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(colorScheme: lightScheme, fontFamily: 'Roboto'),
    builder: (context, child) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
    home: Scaffold(
      body: Form(
        key: form,
        child: PickerField<String>(
          label: 'Brand',
          options: options ?? _brands,
          labelOf: (b) => b,
          initialValue: initial,
          onChanged: onChanged ?? (_) {},
          validator: (v) => v == null ? 'Pick a brand' : null,
          onCreate: onCreate,
          createLabel: 'Add brand',
        ),
      ),
    ),
  ));
  return form;
}

void main() {
  testWidgets('search narrows the list and picking sets the field', (tester) async {
    String? changed;
    await _pump(tester, onChanged: (v) => changed = v);
    await tester.tap(find.byType(PickerField<String>));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'no');
    await tester.pump();
    expect(find.text('Nokia'), findsOneWidget);
    expect(find.text('Samsung'), findsNothing);
    await tester.tap(find.text('Nokia'));
    await tester.pumpAndSettle();
    expect(changed, 'Nokia');
    expect(find.text('Nokia'), findsOneWidget); // shown in the field
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers "Add brand" only when nothing matches exactly, and returns the new brand', (tester) async {
    final created = <String>[];
    String? changed;
    await _pump(tester, onChanged: (v) => changed = v, onCreate: (name) async {
      created.add(name);
      return name;
    });
    await tester.tap(find.byType(PickerField<String>));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nokia');
    await tester.pump();
    expect(find.textContaining('Add brand'), findsNothing); // exact match exists (any case)

    await tester.enterText(find.byType(TextField), 'Itel');
    await tester.pump();
    expect(find.text('Add brand “Itel”'), findsOneWidget);
    await tester.tap(find.text('Add brand “Itel”'));
    await tester.pumpAndSettle();
    expect(created, ['Itel']);
    expect(changed, 'Itel');
  });

  testWidgets('validator shows until a value is picked', (tester) async {
    final form = await _pump(tester);
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Pick a brand'), findsOneWidget);
  });

  testWidgets('a long list fits a small screen with large text', (tester) async {
    await _pump(tester, options: [for (var i = 0; i < 40; i++) 'State number $i with a long name']);
    await tester.tap(find.byType(PickerField<String>));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // no overflow
    await tester.scrollUntilVisible(find.text('State number 39 with a long name'), 300,
        scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)));
    expect(find.text('State number 39 with a long name'), findsOneWidget);
  });
}
