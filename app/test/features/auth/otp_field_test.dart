import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/features/auth/widgets/otp_field.dart';

void main() {
  Future<List<String>> pumpOtp(WidgetTester tester, TextEditingController controller) async {
    final completed = <String>[];
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: OtpField(controller: controller, focusNode: focus, onCompleted: completed.add)),
    ));
    return completed;
  }

  testWidgets('keeps digits only, caps at 6 and completes once', (tester) async {
    final controller = TextEditingController();
    final completed = await pumpOtp(tester, controller);

    await tester.enterText(find.byType(TextField), '12a 34');
    await tester.pump();
    expect(controller.text, '1234');
    expect(completed, isEmpty);
    expect(find.text('3'), findsOneWidget); // drawn in its box

    await tester.enterText(find.byType(TextField), '123 4567'); // pasted with a space and a digit too many
    expect(controller.text, '123456');
    expect(completed, ['123456']);
  });

  testWidgets('one field with SMS autofill hint and a spoken label', (tester) async {
    await pumpOtp(tester, TextEditingController());
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofillHints, [AutofillHints.oneTimeCode]);
    expect(find.bySemanticsLabel('6-digit code'), findsOneWidget);
  });
}
