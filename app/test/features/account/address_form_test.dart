import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shyam_mobiles/features/account/data/address_form.dart';
import 'package:shyam_mobiles/features/account/data/profile.dart';

const _ok = '[{"Message":"Number of pincode(s) found:3","Status":"Success",'
    '"PostOffice":[{"Name":"Koramangala","District":"Bangalore","State":"Karnataka"}]}]';

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
    test('success → district and state', () {
      final p = parsePincodeResponse(_ok)!;
      expect(p.city, 'Bangalore');
      expect(p.state, 'Karnataka');
    });
    test('no records, bad shape or junk → null', () {
      expect(parsePincodeResponse('[{"Message":"No records found","Status":"Error","PostOffice":null}]'), isNull);
      expect(parsePincodeResponse('[]'), isNull);
      expect(parsePincodeResponse('<html>'), isNull);
    });
    test('lookup ignores HTTP and network failures', () async {
      final ok = MockClient((r) async {
        expect(r.url.toString(), 'https://api.postalpincode.in/pincode/560034');
        return http.Response(_ok, 200);
      });
      expect((await lookupPincode('560034', client: ok))?.city, 'Bangalore');
      expect(await lookupPincode('560034', client: MockClient((_) async => http.Response('', 503))), isNull);
      expect(await lookupPincode('560034', client: MockClient((_) async => throw http.ClientException('offline'))), isNull);
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
