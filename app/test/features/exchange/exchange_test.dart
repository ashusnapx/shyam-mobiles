// Exchange your old phone (docs/GROWTH.md §2c) at 360x800 dp with large text: the sheet never shows a price, sends
// the request or a WhatsApp text; the customer sees the shop's estimate as a range; staff send one.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/features/admin/screens/admin_exchanges_screen.dart';
import 'package:shyam_mobiles/features/exchange/data/exchange_repository.dart';
import 'package:shyam_mobiles/features/exchange/screens/exchanges_screen.dart';
import 'package:shyam_mobiles/features/exchange/widgets/exchange_widgets.dart';

import '../../fakes/fake_exchange_repository.dart';
import '../repairs/layout_harness.dart';

void main() {
  late FakeExchangeRepository repo;
  setUp(() => repo = FakeExchangeRepository());
  List<Override> fakes() => [exchangeRepositoryProvider.overrideWithValue(repo)];
  final asked = ExchangeRequest(id: 'e1', brand: 'Samsung', model: 'Galaxy A12', age: ExchangeAge.y2to3,
      condition: ExchangeCondition.good, createdAt: DateTime(2026, 11, 18));

  test('the WhatsApp text says what was picked and asks; it names no price', () {
    final m = exchangeMessage(brand: 'Samsung', model: 'Galaxy A12', age: ExchangeAge.y2to3, condition: ExchangeCondition.fair,
        forPhone: 'Samsung Galaxy S25');
    expect(m, contains('for the Samsung Galaxy S25'));
    expect(m, contains('Phone: Samsung Galaxy A12'));
    expect(m, contains('Age: 2–3 years'));
    expect(m, contains('Condition: Fair'));
    expect(m, isNot(contains('₹')));
    expect(estimateRange(400000, 550000), '₹4,000–₹5,500');
    expect(estimateRange(400000, 400000), '₹4,000');
  });

  testWidgets('the sheet asks for every answer, then sends the request', (tester) async {
    await pumpScreen(tester, const Scaffold(body: ExchangeCard(forProductId: 'galaxy-s25', forPhone: 'Samsung Galaxy S25')),
        overrides: fakes());
    await tester.tap(find.text('Exchange your old phone'));
    await tester.pumpAndSettle();
    expect(find.textContaining('₹'), findsNothing);
    await tester.ensureVisible(find.text('Send to the shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to the shop'));
    await tester.pumpAndSettle();
    expect(find.text('Add the brand, the model, its age, its condition.'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(TextField, 'Brand'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Brand'), 'Samsung');
    await tester.enterText(find.widgetWithText(TextField, 'Model'), 'Galaxy A12');
    await tester.ensureVisible(find.text('2–3 years'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2–3 years'));
    await tester.ensureVisible(find.text('Good'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.ensureVisible(find.text('Send to the shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to the shop'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['request Samsung Galaxy A12 2_3 good 0 galaxy-s25']);
    expect(find.text('Sent. The shop will reply with an estimate.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('before the cut-over only WhatsApp is offered', (tester) async {
    repo.enabled = false;
    await pumpScreen(tester, const Scaffold(body: ExchangeCard()), overrides: fakes());
    await tester.tap(find.text('Exchange your old phone'));
    await tester.pumpAndSettle();
    expect(find.text('Send to the shop'), findsNothing);
    expect(find.text('Send on WhatsApp'), findsOneWidget);
  });

  testWidgets('the customer sees a waiting request, then the estimate as a range', (tester) async {
    repo.list = [
      asked,
      ExchangeRequest(id: 'e2', brand: 'Vivo', model: 'Y21', age: ExchangeAge.over3, condition: ExchangeCondition.fair,
          lowPaise: 300000, highPaise: 350000, note: 'Bring the box', createdAt: DateTime(2026, 11, 17)),
    ];
    await pumpScreen(tester, const ExchangesScreen(), overrides: fakes());
    await tester.pumpAndSettle();
    expect(find.text('Waiting for the shop'), findsOneWidget);
    expect(find.text('About ₹3,000–₹3,500'), findsOneWidget);
    expect(find.text('An estimate: the final value is set when the shop checks the phone.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff send an estimate range; the second amount can’t be below the first', (tester) async {
    repo.list = [asked];
    await pumpScreen(tester, const AdminExchangesScreen(), overrides: fakes());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Give estimate'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'From'), '5000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Up to'), '4000');
    await tester.tap(find.text('Send estimate'));
    await tester.pumpAndSettle();
    expect(find.text('Keep it at or above the first amount.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Up to'), '6000');
    await tester.tap(find.text('Send estimate'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['estimate e1 500000 600000 ""']);
  });
}
