import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/core/supabase.dart';
import 'package:shyam_mobiles/features/account/data/address_form.dart';
import 'package:shyam_mobiles/features/account/data/addresses.dart';
import 'package:shyam_mobiles/features/account/data/profile.dart';
import 'package:shyam_mobiles/features/account/screens/address_form_screen.dart';

import '../repairs/layout_harness.dart';

const _gaya = (
  district: 'Gaya',
  state: 'Bihar',
  areas: ['Gaya Kutchery', 'Gaya H.O', 'Bodh Gaya', 'Manpur', 'Gaya Cantt', 'Chandauti', 'Kendui', 'Bairagi', 'Delha'],
);

class _Addresses extends AddressesNotifier {
  _Addresses(this.list);

  final List<Address> list;

  @override
  Future<List<Address>> build() async => list;
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

/// Scrolls down to the field (the list builds lazily) and reads it.
Future<String> _text(WidgetTester tester, String label) async {
  await scrollTo(tester, _field(label));
  return tester.widget<TextFormField>(_field(label)).controller!.text;
}

Future<void> _pumpForm(
  WidgetTester tester,
  Future<PincodePlace?> Function(String) lookup, {
  List<Address> addresses = const [],
  String? id,
}) =>
    pumpScreen(tester, AddressFormScreen(addressId: id), overrides: [
      currentUserProvider.overrideWithValue(null),
      profileProvider.overrideWithValue(const AsyncData(Profile(id: 'user-1', fullName: 'Rahul Kumar'))),
      addressesProvider.overrideWith(() => _Addresses(addresses)),
      pincodeLookupProvider.overrideWithValue(lookup),
    ]);

void main() {
  testWidgets('new address: pincode fills district and state, offers areas, lays out at 360dp 1.3x', (tester) async {
    final asked = <String>[];
    await _pumpForm(tester, (pin) async {
      asked.add(pin);
      return _gaya;
    });
    expect(find.text('Use my current location'), findsOneWidget);
    expect(await _text(tester, 'Full name'), 'Rahul Kumar');

    await tester.enterText(_field('City, town or village'), 'Bodh Gaya'); // typed by the user: never replaced
    await tester.enterText(_field('Pincode'), '82300');
    await tester.enterText(_field('Pincode'), '823001');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(asked, ['823001'], reason: 'debounced; an incomplete pincode is not looked up');
    expect(find.text('Gaya · Bihar'), findsOneWidget);
    expect(find.text('3 more'), findsOneWidget, reason: '9 areas: 6 shown');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bodh Gaya'));
    await tester.tap(find.text('3 more'));
    await tester.pump();
    expect(find.text('Delha'), findsOneWidget);
    expect(await _text(tester, 'Area, street, locality (optional)'), 'Bodh Gaya');

    expect(await _text(tester, 'City, town or village'), 'Bodh Gaya');
    expect(await _text(tester, 'District (optional)'), 'Gaya');
    await scrollTo(tester, find.text('Bihar'));

    await scrollTo(tester, find.text('Work'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Work'));
    await tester.pump();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Work')).selected, isTrue);
    await scrollTo(tester, find.text('Your first address is the default.'));

    await tester.tap(find.text('Save address')); // house number missing: errors must fit too
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Enter house and street.'), -300, scrollable: find.byType(Scrollable).first);
  });

  testWidgets('pincode not found / offline keeps manual entry; stale lookups are dropped', (tester) async {
    final pending = <String, Completer<PincodePlace?>>{};
    await _pumpForm(tester, (pin) => (pending[pin] = Completer()).future);

    await tester.enterText(_field('Pincode'), '823001');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Checking pincode…'), findsOneWidget);
    await tester.enterText(_field('Pincode'), '999999');
    await tester.pump(const Duration(milliseconds: 400));
    pending['823001']!.complete(_gaya); // answers late, for the old pincode
    pending['999999']!.complete(null);
    await tester.pump();
    expect(find.text('Gaya · Bihar'), findsNothing);
    expect(find.textContaining('No post office has this pincode'), findsOneWidget);
    expect(find.text('Tap your area'), findsNothing, reason: 'no area chips');

    await tester.enterText(_field('Pincode'), '800001');
    await tester.pump(const Duration(milliseconds: 400));
    pending['800001']!.completeError(Exception('offline'));
    await tester.pump();
    expect(find.textContaining("Couldn't check the pincode"), findsOneWidget);
    expect(await _text(tester, 'District (optional)'), isEmpty);
    await tester.enterText(_field('District (optional)'), 'Patna');
    expect(await _text(tester, 'District (optional)'), 'Patna');
  });

  testWidgets('editing keeps the saved district and label', (tester) async {
    await _pumpForm(tester, (_) async => null, id: 'a1', addresses: const [
      Address(
        id: 'a1',
        name: 'Rahul Kumar',
        phone: '+919876543210',
        line1: 'House 14, Gandhi Nagar',
        city: 'Bodh Gaya',
        district: 'Gaya',
        state: 'Bihar',
        pincode: '824231',
        label: AddressLabel.other,
        isDefault: true,
      ),
    ]);
    expect(find.text('Edit address'), findsOneWidget);
    expect(await _text(tester, 'Mobile number'), '98765 43210');
    expect(await _text(tester, 'District (optional)'), 'Gaya');
    await scrollTo(tester, find.text('Other'));
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Other')).selected, isTrue);
  });
}
