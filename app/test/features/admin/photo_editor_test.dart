import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/features/admin/widgets/photo_editor.dart';

void main() {
  test('no adjustment is the identity; contrast pivots on mid-grey, brightness shifts', () {
    expect(adjustMatrix(0, 0), [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]);
    final m = adjustMatrix(0, 1); // contrast 1.4
    expect(128 * m[0] + m[4], closeTo(128, 0.001), reason: 'mid-grey stays');
    expect(adjustMatrix(1, 0)[4], 40);
  });

  testWidgets('without a cut-out the background switch is off and locked; Use this photo returns it unchanged',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000)); // a phone: the square preview leaves room below
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final photo = Uint8List.fromList(_png);
    Uint8List? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await editProductPhoto(context, upright: photo),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(sw.value, isFalse);
    expect(sw.onChanged, isNull);
    await tester.tap(find.text('Use this photo'));
    await tester.pumpAndSettle();
    expect(result, same(photo));
  });
}

// 1 × 1 transparent PNG
const _png = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
