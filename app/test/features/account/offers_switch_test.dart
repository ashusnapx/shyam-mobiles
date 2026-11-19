// "Offers & reminders" (docs/GROWTH.md §2d): on by default, off in one tap, hidden where no such pushes exist.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/features/account/data/profile_repository.dart';
import 'package:shyam_mobiles/features/account/widgets/offers_switch.dart';

import '../../fakes/fake_profile_repository.dart';
import '../repairs/layout_harness.dart';

void main() {
  testWidgets('on by default; one tap turns it off', (tester) async {
    final repo = FakeProfileRepository();
    await pumpScreen(tester, const Scaffold(body: OffersSwitch()), overrides: [profileRepositoryProvider.overrideWithValue(repo)]);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    expect(find.textContaining('At most one every 3 days'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(repo.calls, ['offers false']);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden on a build that sends none, and when signed out', (tester) async {
    final repo = FakeProfileRepository()..offers = null;
    await pumpScreen(tester, const Scaffold(body: OffersSwitch()), overrides: [profileRepositoryProvider.overrideWithValue(repo)]);
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    await pumpScreen(tester, const Scaffold(body: OffersSwitch()),
        overrides: [profileRepositoryProvider.overrideWithValue(FakeProfileRepository())], userId: null);
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
  });
}
