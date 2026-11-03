// The returns sheet never opens blank: a store whose settings carry no policy shows the default one.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/theme/tokens.dart';
import 'package:shyam_mobiles/core/widgets/blocks.dart';

StoreSettings _settings(String policy) => StoreSettings(
      deliveryFeePaise: 4900,
      freeDeliveryMinPaise: 99900,
      codEnabled: true,
      codMaxPaise: 2500000,
      storePhone: '+919999999999',
      storeAddress: '',
      repairNote: '',
      returnsPolicy: policy,
    );

void main() {
  for (final (policy, shown) in [('', defaultReturnsPolicy), ('Seven days, unopened.', 'Seven days, unopened.')]) {
    testWidgets('policy "$policy": the sheet shows "$shown"', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: lightScheme, fontFamily: 'Roboto'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReturnsSheet(context, _settings(policy)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Returns & warranty'), findsOneWidget);
      expect(find.text(shown), findsOneWidget);
    });
  }
}
