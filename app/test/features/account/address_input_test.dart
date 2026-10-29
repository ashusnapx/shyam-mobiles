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
import 'package:shyam_mobiles/features/account/screens/profile_screen.dart';

import '../repairs/layout_harness.dart';

/// Holds every save open, so a double tap and the saved values can be checked without a server.
class _Addresses extends AddressesNotifier {
  final saved = <Address>[];

  @override
  Future<List<Address>> build() async => const [];

  @override
  Future<Address> save(Address address) {
    saved.add(address);
    return Completer<Address>().future;
  }
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<String> _text(WidgetTester tester, String label) async {
  await scrollTo(tester, _field(label));
  return tester.widget<TextFormField>(_field(label)).controller!.text;
}

Future<void> _type(WidgetTester tester, String label, String text) async {
  await scrollTo(tester, _field(label));
  await tester.enterText(_field(label), text);
}

Future<_Addresses> _pump(WidgetTester tester) async {
  final addresses = _Addresses();
  await pumpScreen(tester, const AddressFormScreen(), overrides: [
    currentUserProvider.overrideWithValue(null),
    profileProvider.overrideWithValue(const AsyncData(Profile(id: 'user-1'))),
    addressesProvider.overrideWith(() => addresses),
    pincodeLookupProvider.overrideWithValue((_) async => (district: 'Gaya', state: 'Bihar', areas: const <String>[])),
  ]);
  return addresses;
}

void main() {
  testWidgets('phone and pincode take exactly their digits, however they are typed or pasted', (tester) async {
    await _pump(tester);
    for (final (typed, shown) in [
      ('+91 98765-43210 (home)', '98765 43210'),
      ('919876543210', '98765 43210'),
      ('98765 432109', '98765 43210'), // an 11th digit
    ]) {
      await _type(tester, 'Mobile number', typed);
      expect(await _text(tester, 'Mobile number'), shown, reason: typed);
    }
    await _type(tester, 'Pincode', '8230011'); // 7 digits
    expect(await _text(tester, 'Pincode'), '823001');
    await _type(tester, 'Pincode', 'PIN: ८२३ ००१');
    expect(await _text(tester, 'Pincode'), '823001');
  });

  testWidgets('every text field stops at its DB length, counted like Postgres', (tester) async {
    await _pump(tester);
    for (final (label, max) in [
      ('Full name', 80),
      ('House no., flat, building', 120),
      ('Area, street, locality (optional)', 120),
      ('Landmark (optional)', 80),
      ('City, town or village', 60),
      ('District (optional)', 60),
    ]) {
      await _type(tester, label, 'क्ष' * 10000); // a 30,000-code-point Hindi essay
      expect((await _text(tester, label)).runes.length, lessThanOrEqualTo(max), reason: label);
      await _type(tester, label, 'a' * 10000);
      expect(await _text(tester, label), 'a' * max, reason: label);
    }
  });

  testWidgets('junk is refused with a clear message; Hindi is fine; saved values are tidy; one save per tap burst',
      (tester) async {
    final addresses = await _pump(tester);
    await _type(tester, 'Full name', '😀😀');
    await _type(tester, 'Mobile number', '98765 43210');
    await _type(tester, 'Pincode', '823001');
    await tester.pump(const Duration(milliseconds: 400)); // pincode lookup fills district and state
    await tester.pump();
    await _type(tester, 'House no., flat, building', '   ');
    await _type(tester, 'City, town or village', '12345');
    await tester.tap(find.text('Save address'));
    await tester.pump();
    expect(addresses.saved, isEmpty);
    expect(find.text('Enter house and street.'), findsOneWidget);
    // name (scrolled far off screen) and city: a lazy ListView would have dropped the name field and skipped it
    expect(find.text('Use letters, not only symbols or emoji.'), findsNWidgets(2));

    await _type(tester, 'Full name', '  राम   कुमार\u200B ');
    await _type(tester, 'House no., flat, building', 'मकान 14,\u202E गांधी नगर ');
    await _type(tester, 'City, town or village', 'Bodh Gaya');
    await tester.tap(find.text('Save address'));
    await tester.tap(find.text('Save address'));
    await tester.tap(find.text('Save address'));
    await tester.pump();
    expect(addresses.saved, hasLength(1), reason: 'triple tap saves once');
    final a = addresses.saved.single;
    expect(a.name, 'राम कुमार');
    expect(a.line1, 'मकान 14, गांधी नगर');
    expect(a.phone, '+919876543210');
    expect(a.pincode, '823001');
    expect(a.state, 'Bihar');
    expect(a.district, 'Gaya');
    expect(a.landmark, isNull);
  });

  testWidgets('profile name: capped at 80, emoji-only refused before the server sees it', (tester) async {
    await pumpScreen(tester, const ProfileScreen(), overrides: [
      currentUserProvider.overrideWithValue(null),
      profileProvider.overrideWithValue(const AsyncData(Profile(id: 'user-1', fullName: 'Asha'))),
    ]);
    await tester.enterText(_field('Full name'), 'n' * 10000);
    expect(tester.widget<TextFormField>(_field('Full name')).controller!.text, 'n' * 80);
    await tester.enterText(_field('Full name'), '🙂🙂🙂');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Use letters, not only symbols or emoji.'), findsOneWidget);
  });

  test('validators match the addresses checks (letters for names and places)', () {
    expect(validateName('😀😀'), isNotNull);
    expect(validateName('12345'), isNotNull);
    expect(validateName('...'), isNotNull);
    expect(validateName('राम'), isNull);
    expect(validateCity('Gaya'), isNull);
    expect(validateCity('123'), isNotNull);
    expect(validateDistrict('🙂'), isNotNull);
    expect(validateDistrict(''), isNull);
    expect(validateLine1('Flat 12B'), isNull);
    expect(validateLine1('   '), 'Enter house and street.');
    expect(validatePhone('98765 4321'), isNotNull);
  });
}
