import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart' show Placemark;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/account/data/address_form.dart';
import 'package:shyam_mobiles/features/account/data/profile.dart';

const _ok = '[{"Message":"Number of pincode(s) found:3","Status":"Success","PostOffice":['
    '{"Name":"Koramangala","District":"Bangalore","State":"Karnataka"},'
    '{"Name":"Koramangala VI Bk","District":"Bangalore","State":"Karnataka"},'
    '{"Name":"Koramangala","District":"Bangalore","State":"Karnataka"},'
    '{"Name":" ","District":"Bangalore","State":"Karnataka"}]}]';

void main() {
  group('validators match the addresses table checks', () {
    test('name 2..80', () {
      expect(validateName('A'), isNotNull);
      expect(validateName(' Al '), isNull);
      expect(validateName('a' * 80), isNull);
      expect(validateName('a' * 81), isNotNull);
      expect(validateName(''), 'Enter a name.');
    });
    test('line1 3..120, line2 ≤120, landmark ≤80, city 2..60', () {
      expect(validateLine1('12'), isNotNull);
      expect(validateLine1('12B'), isNull);
      expect(validateLine1('a' * 121), isNotNull);
      expect(validateLine2(''), isNull);
      expect(validateLine2('a' * 121), isNotNull);
      expect(validateLandmark(null), isNull);
      expect(validateLandmark('a' * 81), isNotNull);
      expect(validateCity('P'), isNotNull);
      expect(validateCity('Patna'), isNull);
    });
    test('district optional, ≤60', () {
      expect(validateDistrict(null), isNull);
      expect(validateDistrict(''), isNull);
      expect(validateDistrict('a' * 60), isNull);
      expect(validateDistrict('a' * 61), isNotNull);
    });
    test('pincode ^[1-9][0-9]{5}\$', () {
      expect(validatePincode('110001'), isNull);
      expect(validatePincode('011000'), isNotNull);
      expect(validatePincode('11000'), isNotNull);
      expect(validatePincode('1100011'), isNotNull);
    });
    test('phone is an Indian mobile', () {
      expect(validatePhone('98765 43210'), isNull);
      expect(validatePhone('+91 98765 43210'), isNull);
      expect(validatePhone('12345 67890'), isNotNull);
      expect(validatePhone(''), isNotNull);
    });
    test('state required', () {
      expect(validateState(null), isNotNull);
      expect(validateState('Goa'), isNull);
    });
  });

  test('state names from India Post map to the dropdown', () {
    expect(indianStates, hasLength(36));
    expect(matchState('KARNATAKA'), 'Karnataka');
    expect(matchState('Jammu & Kashmir'), 'Jammu and Kashmir');
    expect(matchState('Chattisgarh'), 'Chhattisgarh');
    expect(matchState('Daman & Diu'), 'Dadra and Nagar Haveli and Daman and Diu');
    expect(matchState('Atlantis'), isNull);
    for (final s in indianStates) {
      expect(s.length, inInclusiveRange(2, 60)); // DB check on state
    }
  });

  group('pincode response', () {
    test('success → district, state and the post offices as areas', () {
      final p = parsePincodeResponse(_ok)!;
      expect(p.district, 'Bangalore');
      expect(p.state, 'Karnataka');
      expect(p.areas, ['Koramangala', 'Koramangala VI Bk'], reason: 'deduped, blanks dropped');
    });
    test('no records, bad shape or junk → null', () {
      expect(parsePincodeResponse('[{"Message":"No records found","Status":"Error","PostOffice":null}]'), isNull);
      expect(parsePincodeResponse('[]'), isNull);
      expect(parsePincodeResponse('<html>'), isNull);
    });
    test('lookup: null when not found, throws when India Post is unreachable', () async {
      final ok = MockClient((r) async {
        expect(r.url.toString(), 'https://api.postalpincode.in/pincode/560034');
        return http.Response(_ok, 200);
      });
      expect((await lookupPincode('560034', client: ok))?.district, 'Bangalore');
      final none = MockClient((_) async => http.Response('[{"Status":"Error","PostOffice":null}]', 200));
      expect(await lookupPincode('999999', client: none), isNull);
      expect(lookupPincode('560034', client: MockClient((_) async => http.Response('', 503))), throwsA(isA<http.ClientException>()));
      expect(lookupPincode('560034', client: MockClient((_) async => throw http.ClientException('offline'))), throwsA(isA<http.ClientException>()));
    });
  });

  group('placemark → form fields', () {
    test('plus code dropped, house and street joined, state matched', () {
      final g = addressFromPlacemark(const Placemark(
        name: '7JFJ+2Q',
        subThoroughfare: '14',
        thoroughfare: 'Station Road',
        subLocality: 'Gandhi Nagar',
        locality: 'Gaya',
        subAdministrativeArea: 'Gaya',
        administrativeArea: 'BIHAR',
        postalCode: '823001',
        isoCountryCode: 'IN',
      ));
      expect(g, (
        line1: '14, Station Road',
        area: 'Gandhi Nagar',
        city: 'Gaya',
        district: 'Gaya',
        state: 'Bihar',
        pincode: '823001',
      ));
    });
    test('a name that already holds the street, or repeats the area, is not doubled', () {
      expect(
        addressFromPlacemark(const Placemark(name: '12, MG Road', subThoroughfare: '12', thoroughfare: 'MG Road')).line1,
        '12, MG Road',
      );
      final g = addressFromPlacemark(
          const Placemark(name: 'Koramangala', thoroughfare: 'Unnamed Road', subLocality: 'Koramangala', postalCode: '5600'));
      expect(g.line1, isNull);
      expect(g.area, 'Koramangala');
      expect(g.pincode, isNull, reason: 'not a valid Indian pincode');
    });
    test('empty placemark → nothing to fill', () {
      expect(addressFromPlacemark(const Placemark(name: ' ', administrativeArea: 'Atlantis')),
          (line1: null, area: null, city: null, district: null, state: null, pincode: null));
    });
  });

  group('address model', () {
    const a = Address(
      name: 'Asha',
      phone: '+919876543210',
      line1: '14 Station Road',
      city: 'Bodh Gaya',
      district: 'Gaya',
      state: 'Bihar',
      pincode: '824231',
      label: AddressLabel.work,
    );
    test('label and district round-trip through JSON', () {
      expect(a.toJson()['label'], 'work');
      expect(a.toJson()['district'], 'Gaya');
      final back = Address.fromJson({...a.toJson(), 'id': 'a1'});
      expect(back.label, AddressLabel.work);
      expect(back.district, 'Gaya');
      expect(AddressLabel.values.map((l) => l.displayName), ['Home', 'Work', 'Other']);
      expect(AddressLabel.parse('office'), AddressLabel.home);
    });
    test('oneLine shows the district only when it differs from the city', () {
      expect(a.oneLine, '14 Station Road, Bodh Gaya, Gaya, Bihar 824231');
      expect(Address.fromJson({...a.toJson(), 'city': 'GAYA'}).oneLine, '14 Station Road, GAYA, Bihar 824231');
    });
    test('order snapshots from before district and label still parse', () {
      final o = Order.fromJson({
        'id': 'o1', 'number': 'SM100001', 'user_id': 'u1', 'status': 'confirmed', 'payment_method': 'cod',
        'payment_status': 'pending', 'subtotal_paise': 100, 'delivery_fee_paise': 0, 'total_paise': 100,
        'address': {'name': 'A', 'phone': '+919876543210', 'line1': 'x', 'city': 'Gaya', 'state': 'Bihar', 'pincode': '823001'},
        'created_at': '2026-10-29T10:00:00Z',
      });
      expect(o.address.district, isNull);
      expect(o.address.label, AddressLabel.home);
      expect(o.address.oneLine, 'x, Gaya, Bihar 823001');
    });
  });

  test('account header helpers', () {
    expect(initials('Asha Kumari Rao'), 'AR');
    expect(initials('ravi'), 'R');
    expect(initials('   '), isNull);
    expect(initials(null), isNull);
    expect(accountPhone('919876543210', null), '+91 98765 43210');
    expect(accountPhone('', '+919876543210'), '+91 98765 43210');
    expect(accountPhone(null, null), isNull);
  });
}
