// The name asked at sign-up and in Profile, how it's shown, and the first name the Home greeting uses.
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/features/account/data/profile.dart';

void main() {
  test('2 to 60 characters of letters (any script) and spaces; dots, apostrophes and hyphens allowed', () {
    for (final ok in ['Ravi Kumar', 'Asha', 'रवि कुमार', 'R.K. Sharma', "D'Souza", 'Mary-Ann', '  ravi   kumar  ']) {
      expect(validatePersonName(ok), isNull, reason: ok);
    }
    expect(validatePersonName(''), 'Enter your name.');
    expect(validatePersonName('   '), 'Enter your name.');
    expect(validatePersonName('R'), 'Enter at least 2 letters.');
    expect(validatePersonName('R.'), 'Enter at least 2 letters.');
    expect(validatePersonName('Ravi 2'), 'Use letters only, like Ravi Kumar.');
    expect(validatePersonName('Ravi 🙂'), 'Use letters only, like Ravi Kumar.');
    expect(validatePersonName('Demo Admin (staff)'), 'Use letters only, like Ravi Kumar.');
    expect(validatePersonName('A' * 60), isNull);
    expect(validatePersonName('A' * 61), 'Keep it to 60 characters.');
  });

  test('display: tidied and capitalised, mixed case kept', () {
    expect(displayName('  ravi   kumar '), 'Ravi Kumar');
    expect(displayName('RAVI KUMAR'), 'Ravi Kumar');
    expect(displayName('ravi McDonald'), 'Ravi McDonald');
    expect(displayName('रवि कुमार'), 'रवि कुमार');
  });

  test('first name for the greeting', () {
    expect(firstName('ravi kumar'), 'Ravi');
    expect(firstName('Demo Admin (staff)'), 'Demo');
    expect(firstName('(staff) Asha'), 'Asha');
    expect(firstName('रवि कुमार'), 'रवि');
    expect(firstName(''), isNull);
    expect(firstName(null), isNull);
    expect(firstName('🙂'), isNull);
  });
}
