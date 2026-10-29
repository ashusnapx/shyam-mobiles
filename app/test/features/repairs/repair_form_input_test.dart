import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/features/repairs/data/repairs.dart';
import 'package:shyam_mobiles/features/repairs/screens/repair_form_screen.dart';

import 'layout_harness.dart';

Finder _field(String label) => find.widgetWithText(TextFormField, label);

String _text(WidgetTester tester, String label) => tester.widget<TextFormField>(_field(label)).controller!.text;

Future<void> _type(WidgetTester tester, String label, String text) async {
  await scrollTo(tester, _field(label));
  await tester.enterText(_field(label), text);
  await tester.pump();
}

void main() {
  testWidgets('repair booking: phone, device and notes take only what the DB keeps', (tester) async {
    await pumpScreen(tester, const RepairFormScreen(),
        overrides: [myPhoneProvider.overrideWithValue(const AsyncData('+919876543210'))]);
    expect(_text(tester, 'Phone for updates'), '98765 43210', reason: 'prefilled as the 10 digits after +91');
    await _type(tester, 'Phone for updates', '+91 98765 43210 (home)');
    expect(_text(tester, 'Phone for updates'), '98765 43210');
    await _type(tester, 'Phone for updates', '98765 432101');
    expect(_text(tester, 'Phone for updates'), '98765 43210', reason: 'no 11th digit');

    await tester.ensureVisible(find.text('Other').first); // the brand chip (the issue grid has an Other too)
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').first);
    await tester.pump();
    await _type(tester, 'Brand', 'B' * 200);
    expect(_text(tester, 'Brand'), 'B' * 40);
    await _type(tester, 'Brand', '📱📱');
    await _type(tester, 'Model', '   ');
    await _type(tester, 'Anything else? (optional)', 'ख' * 10000);
    expect(_text(tester, 'Anything else? (optional)').runes.length, 500);
    expect(find.text('500/500'), findsOneWidget);

    await tester.tap(find.textContaining('Book for'));
    await tester.pump();
    expect(find.text('Use letters, not only symbols or emoji.'), findsOneWidget);
    expect(find.text('Enter the model.'), findsOneWidget);
    expect(find.text('Pick what’s wrong, a time slot.'), findsOneWidget);
  });
}
