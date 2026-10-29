import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/input.dart';

TextEditingValue _v(String text, [int? caret]) =>
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret ?? text.length));

/// Types [chars] one at a time at the caret, the way a keyboard sends them.
TextEditingValue _type(TextInputFormatter f, String chars, {TextEditingValue? from}) {
  var value = from ?? TextEditingValue.empty;
  for (final ch in chars.split('')) {
    final at = value.selection.end < 0 ? value.text.length : value.selection.end;
    value = f.formatEditUpdate(value, _v(value.text.substring(0, at) + ch + value.text.substring(at), at + 1));
  }
  return value;
}

/// Pastes [text] at [at] (default: the end) of [into].
TextEditingValue _paste(TextInputFormatter f, String text, {String into = '', int? at}) {
  final i = at ?? into.length;
  return f.formatEditUpdate(_v(into, i), _v(into.substring(0, i) + text + into.substring(i), i + text.length));
}

void main() {
  group('tidy and checkText', () {
    for (final (input, single, multi) in [
      ('  Asha   Verma  ', 'Asha Verma', 'Asha Verma'),
      ('Asha\u200B Verma\u200E', 'Asha Verma', 'Asha Verma'),
      ('\uFEFFFlat 12\t\tB', 'Flat 12 B', 'Flat 12 B'),
      ('line one\r\n\n\n\nline two  ', 'line one line two', 'line one\n\nline two'),
      ('राम\u202E कुमार', 'राम कुमार', 'राम कुमार'),
      ('क्\u200Dष', 'क्\u200Dष', 'क्\u200Dष'), // ZWJ kept: Hindi conjuncts need it
      ('\x00\x07ab\x1B', 'ab', 'ab'),
    ]) {
      test('tidy ${input.codeUnits.take(6).toList()}…', () {
        expect(tidy(input), single);
        expect(tidy(input, multiline: true), multi);
      });
    }

    test('names need a letter in any script; lengths count code points like char_length', () {
      String? name(String v) => checkText(v, min: 2, max: 80, what: 'a name', mustHave: hasLetter);
      expect(name('Asha'), isNull);
      expect(name('राम कुमार'), isNull);
      expect(name('محمد'), isNull);
      expect(name('O’Brien-Smith'), isNull);
      expect(name(''), 'Enter a name.');
      expect(name('   \u200B '), 'Enter a name.');
      expect(name('😀😀'), isNotNull);
      expect(name('12345'), isNotNull);
      expect(name('...'), isNotNull);
      expect(name('A'), 'Too short.');
      expect(name('a' * 80), isNull);
      expect(name('a' * 81), isNotNull);
      // क्ष is 3 code points: 27 of them are 81 for Postgres even though Flutter sees 27 characters
      expect(name('क्ष' * 26), isNull);
      expect(name('क्ष' * 27), isNotNull);
      expect(checkText('13', max: 60, mustHave: hasLetterOrDigit), isNull);
      expect(checkText('📱', max: 60, mustHave: hasLetterOrDigit), isNotNull);
      expect(checkText('', max: 60), isNull, reason: 'optional when min is 0');
    });
  });

  group('IndianMobileFormatter', () {
    const f = IndianMobileFormatter();
    for (final (pasted, shown) in [
      ('9876543210', '98765 43210'),
      ('+91 98765 43210', '98765 43210'),
      ('+91 98765-43210 (home)', '98765 43210'),
      ('098765-43210', '98765 43210'),
      ('919876543210', '98765 43210'),
      ('0091 98765 43210', '98765 43210'),
      ('Call me: 98765 43210', '98765 43210'),
      ('९८७६५ ४३२१०', '98765 43210'), // Devanagari digits
      ('98765', '98765'),
      ('98765 43210 / 98765 43211', ''), // two numbers: nothing to guess, nothing pasted
      ('12345678901', ''),
    ]) {
      test('paste "$pasted"', () {
        final v = _paste(f, pasted);
        expect(v.text, shown);
        expect(v.selection.end, shown.length);
      });
    }

    test('typing: grouped as it goes, no 11th digit', () {
      final v = _type(f, '9876543210');
      expect(v.text, '98765 43210');
      expect(v.selection.end, 11);
      expect(_type(f, '1', from: v).text, '98765 43210');
      expect(_type(f, '7', from: _v('98765 43210', 3)).text, '98765 43210', reason: 'full: typing in the middle too');
      expect(_type(f, 'abc+-').text, '');
    });

    test('typing the country or trunk prefix by hand still ends with the right 10 digits', () {
      expect(_type(f, '+919876543210').text, '98765 43210');
      expect(_type(f, '09876543210').text, '98765 43210');
      expect(_type(f, '9198765432').text, '91987 65432', reason: 'a real number starting 91 is kept as is');
    });

    test('backspace over the space deletes the digit before it; caret stays put in the middle', () {
      // "98765 |43210" → backspace removes the space; the formatter removes the 5 instead
      final v = f.formatEditUpdate(_v('98765 43210', 6), _v('9876543210', 5));
      expect(v.text, '98764 3210');
      expect(v.selection.end, 4);
      // the same number pasted over itself without the space is not a backspace
      expect(f.formatEditUpdate(_v('98765 43210'), _v('9876543210')).text, '98765 43210');
      final mid = _type(f, '1', from: _v('98765 4321', 2));
      expect(mid.text, '98176 54321');
      expect(mid.selection.end, 3);
    });

    test('field text for a stored number and the validator', () {
      expect(localPhone('+919876543210'), '98765 43210');
      expect(localPhone('919876543210'), '98765 43210');
      expect(localPhone(null), '');
      expect(localPhone('garbage'), '');
      expect(validateMobile('98765 43210'), isNull);
      expect(validateMobile(''), 'Enter a 10-digit mobile number.');
      expect(validateMobile('98765 4321'), 'Enter a 10-digit mobile number.');
      expect(validateMobile('91987 654321'), 'Enter a 10-digit mobile number.');
      expect(validateMobile('12345 67890'), 'Mobile numbers start with 6, 7, 8 or 9.');
      expect(validateMobile('51234 67890'), 'Mobile numbers start with 6, 7, 8 or 9.');
    });
  });

  group('DigitsFormatter', () {
    test('pincode: 6 digits, a 7th is ignored', () {
      const f = DigitsFormatter(6);
      expect(_type(f, '1100245').text, '110024');
      expect(_paste(f, '110 024').text, '110024');
      expect(_paste(f, 'Delhi - 110024, India').text, '110024');
      expect(_paste(f, '११००२४').text, '110024');
      expect(_type(f, 'a1-b2').text, '12');
    });

    test('OTP from an SMS', () {
      const f = DigitsFormatter(6);
      expect(_paste(f, '123456 is your Shyam Mobiles code. Ref 99').text, '123456');
      expect(_paste(f, '123-456-789').text, '123456');
    });

    test('IMEI: a pasted box label keeps the 15-digit run', () {
      const f = DigitsFormatter(15);
      expect(_paste(f, '35-209900-176148-1').text, '352099001761481');
      expect(_paste(f, 'IMEI1: 352099001761481 IMEI2: 352099001761499').text, '352099001761481');
      expect(_paste(f, '352099001761481', into: '35').text, '352099001761481', reason: 'a full paste replaces');
      expect(_type(f, '9', from: _v('352099001761481', 4)).text, '352099001761481');
    });
  });

  group('RupeesFormatter', () {
    const f = RupeesFormatter(maxDigits: 7);
    for (final (pasted, shown) in [
      ('74999', '74999'),
      ('₹74,999.00', '74999.00'),
      ('Rs. 1,29,999', '129999'),
      ('49.5', '49.5'),
      ('-500', '500'),
      ('12345678', ''), // too many digits: refused, not cut
      ('1.2.3', ''),
      ('49.999', ''),
    ]) {
      test('paste "$pasted"', () => expect(_paste(f, pasted).text, shown));
    }

    test('typing: no third decimal, no second point, no eighth digit', () {
      expect(_type(f, '49.505').text, '49.50');
      expect(_type(f, '4.9.').text, '4.9');
      expect(_type(f, '123456789').text, '1234567');
    });
  });

  group('HexColorFormatter', () {
    const f = HexColorFormatter();
    test('adds the #, uppercases, stops at 6', () {
      expect(_type(f, '1f2b4d').text, '#1F2B4D');
      expect(_type(f, '#1f2b4d9').text, '#1F2B4D');
      expect(_paste(f, '#1f2b4dff').text, '#1F2B4D');
      expect(_paste(f, 'zz12').text, '#12');
      expect(_type(f, '#').text, '');
    });
  });

  group('text limits', () {
    test('caps at code points, never splits an emoji or loses existing text', () {
      const f = CodePointLimit(10);
      expect(_paste(f, 'a' * 10000).text, 'a' * 10);
      expect(_paste(f, '😀😀😀😀😀😀', into: 'abcdef').text, 'abcdef😀😀😀😀');
      // pasting in the middle cuts the paste, not the end of the text
      final mid = _paste(f, 'XXXXXXXX', into: 'Hello world', at: 5);
      expect(mid.text, 'Hello world');
      final room = _paste(f, 'XXXXXXXX', into: 'Hello', at: 2);
      expect(room.text, 'HeXXXXXllo');
      expect(room.selection.end, 7);
      expect(_paste(f, 'क्षक्षक्षक्ष').text, 'क्षक्षक्ष', reason: 'whole clusters only: 9 code points');
    });

    test('clean formatter drops invisibles as they are typed or pasted, keeps Hindi', () {
      final single = textInput(80);
      TextEditingValue run(List<TextInputFormatter> fs, String s) =>
          fs.fold(_v(s), (v, f) => f.formatEditUpdate(TextEditingValue.empty, v));
      expect(run(single, 'Asha\u200B\u202E Verma').text, 'Asha Verma');
      expect(run(single, 'a\tb').text, 'a b');
      expect(run(single, 'राम').text, 'राम');
      expect(run(textInput(500, multiline: true), 'line one\r\nline two').text, 'line one\nline two');
    });
  });

  test('email: trimmed, lowercased, sensible shape', () {
    expect(normalizeEmail('  Asha.Verma@Gmail.COM '), 'asha.verma@gmail.com');
    for (final ok in ['a@b.co', 'asha.verma+shop@gmail.com', 'x@mail.example.in']) {
      expect(validateEmail(ok), isNull, reason: ok);
    }
    for (final bad in ['', 'asha', 'asha@', '@gmail.com', 'asha@gmail', 'asha@gmail,com', 'asha@@gmail.com',
        'asha..v@gmail.com', '.asha@gmail.com', 'asha.@gmail.com', 'asha@gmail..com',
        'asha@gmail.c', '${'a' * 65}@gmail.com', 'a@${'b' * 250}.com']) {
      expect(validateEmail(bad), isNotNull, reason: bad);
    }
  });
}
