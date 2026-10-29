import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';

/// The rules every text field shares: what can be typed or pasted (formatters), how a value is tidied before
/// it's saved, and the validators. Limits mirror the DB checks in supabase/migrations/20261028000000_schema.sql.
/// Postgres `char_length` counts code points, so the limits here do too.

abstract final class MaxLen {
  static const name = 80; // profiles.full_name, addresses.name, variants.name
  static const addressLine = 120; // addresses.line1/line2
  static const landmark = 80;
  static const place = 60; // addresses.city/district/state
  static const productName = 120;
  static const productDescription = 5000;
  static const note = 500; // repair description and admin_note, order_events.note
  static const returnsPolicy = 2000;
  static const storeAddress = 300; // also repair_note
  static const deviceBrand = 40;
  static const deviceModel = 60;
  static const courier = 60; // orders.courier and tracking_number
  static const storeHours = 60;
  static const mapsUrl = 500;
  static const sku = 60;
  static const slug = 160;
  static const search = 100;
  static const email = 254;
}

// Characters -------------------------------------------------------------------

// Zeros of the decimal digit blocks people paste from: Arabic-Indic, Devanagari, Bengali, Gurmukhi, Gujarati,
// Odia, Tamil, Telugu, Kannada, Malayalam, full-width.
const _digitZeros = [0x0660, 0x06F0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6, 0x0D66, 0xFF10];

int _ascii(int unit) {
  for (final z in _digitZeros) {
    if (unit >= z && unit <= z + 9) return 0x30 + unit - z;
  }
  return unit;
}

/// "९८७६५ ४३२१०" → "98765 43210". Same length (every mapped digit is one code unit), other text unchanged.
String asciiDigits(String s) => String.fromCharCodes(s.codeUnits.map(_ascii));

String _digitsOf(String s) => asciiDigits(s).replaceAll(RegExp('[^0-9]'), '');

/// Control characters (not tab or newlines), zero-width and bidi controls, soft hyphen, BOM. Invisible, so they
/// only ever arrive by paste and make "same" values differ. ZWJ/ZWNJ (U+200C/D) stay: Hindi conjuncts and emoji
/// need them.
final _invisible = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F\u00AD\u061C\u180E\u200B\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u206F\uFEFF\uFFF9-\uFFFB]');

/// What gets saved: invisible characters dropped, each run of spaces made one, trimmed. [multiline] keeps line
/// breaks, with at most one blank line in a row.
String tidy(String? s, {bool multiline = false}) {
  final t = (s ?? '').replaceAll('\r', '').replaceAll(_invisible, '');
  if (!multiline) return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t
      .split(RegExp('[\n\u2028\u2029]'))
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Contains a letter in any script (Hindi included), so "   " or "🙂🙂" isn't taken for a name.
final hasLetter = RegExp(r'\p{L}', unicode: true);

/// Contains a letter or a digit ("13" is a fine phone model).
final hasLetterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Null when the tidied [v] is [min]..[max] code points (min 0: optional) and has a match for [mustHave].
String? checkText(String? v, {required int max, int min = 0, String what = 'this', RegExp? mustHave, bool multiline = false}) {
  final s = tidy(v, multiline: multiline);
  final n = s.runes.length;
  if (n == 0) return min > 0 ? 'Enter $what.' : null;
  if (mustHave != null && !mustHave.hasMatch(s)) return 'Use letters, not only symbols or emoji.';
  if (n < min) return 'Too short.';
  if (n > max) return 'Keep it to $max characters.';
  return null;
}

// Formatters -------------------------------------------------------------------

/// The part an edit typed or pasted: [now] minus what it shares with [before] at both ends. Never splits a
/// surrogate pair, so cutting the inserted part can't leave half an emoji behind.
({int start, int end}) _edit(String before, String now) {
  var start = 0;
  while (start < before.length && start < now.length && before.codeUnitAt(start) == now.codeUnitAt(start)) {
    start++;
  }
  if (start > 0 && start < now.length && _isLow(now.codeUnitAt(start))) start--;
  var tail = 0;
  while (tail < before.length - start &&
      tail < now.length - start &&
      before.codeUnitAt(before.length - 1 - tail) == now.codeUnitAt(now.length - 1 - tail)) {
    tail++;
  }
  var end = now.length - tail;
  if (end > start && end < now.length && _isLow(now.codeUnitAt(end))) end++;
  return (start: start, end: end);
}

bool _isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

/// Rebuilds [v] with each code unit replaced by [map] (a string, '' to drop it), carrying the selection along.
TextEditingValue _rewrite(TextEditingValue v, String Function(String unit) map) {
  final s = v.text;
  final at = List<int>.filled(s.length + 1, 0);
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    at[i] = out.length;
    out.write(map(s[i]));
  }
  at[s.length] = out.length;
  final text = out.toString();
  if (text == s) return v;
  int to(int offset) => offset < 0 ? offset : at[offset.clamp(0, s.length)];
  return TextEditingValue(
    text: text,
    selection: v.selection.copyWith(baseOffset: to(v.selection.baseOffset), extentOffset: to(v.selection.extentOffset)),
  );
}

/// Drops invisible characters as they're typed or pasted; tabs become spaces, line breaks become spaces unless
/// [multiline].
class CleanTextFormatter extends TextInputFormatter {
  const CleanTextFormatter({this.multiline = false});

  final bool multiline;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) => _rewrite(
        newValue,
        (u) => switch (u) {
          '\r' => '',
          '\t' => ' ',
          '\n' || '\u2028' || '\u2029' => multiline ? '\n' : ' ',
          _ when _invisible.hasMatch(u) => '',
          _ => u,
        },
      );
}

/// Caps text at [max] code points, which is what Postgres counts. Flutter's `maxLength` counts grapheme clusters,
/// so a Hindi name (क्ष is 3 code points in 1 cluster) or emoji could pass it and still fail the DB check. Only the
/// typed or pasted part is cut, at a cluster boundary; the text already there is never lost.
class CodePointLimit extends TextInputFormatter {
  const CodePointLimit(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final now = newValue.text;
    if (now.length <= max || now.runes.length <= max) return newValue;
    final e = _edit(oldValue.text, now);
    var room = max - (now.substring(0, e.start) + now.substring(e.end)).runes.length;
    final fit = StringBuffer();
    for (final g in now.substring(e.start, e.end).characters) {
      room -= g.runes.length;
      if (room < 0) break;
      fit.write(g);
    }
    final typed = fit.toString();
    return TextEditingValue(
      text: now.substring(0, e.start) + typed + now.substring(e.end),
      selection: TextSelection.collapsed(offset: e.start + typed.length),
    );
  }
}

/// Formatters for a free-text field of at most [max] code points.
List<TextInputFormatter> textInput(int max, {bool multiline = false}) =>
    [CleanTextFormatter(multiline: multiline), CodePointLimit(max)];

/// Digits only (any script's digits become 0–9), at most [max]: pincodes, OTPs, IMEIs, stock. A digit typed into
/// a full field is ignored. A paste with too many digits keeps the first run of [max] (spaces or dashes inside
/// are fine: "Code: 123 456", "35-209900-176148-1"), else its first [max] digits.
class DigitsFormatter extends TextInputFormatter {
  const DigitsFormatter(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final v = _rewrite(newValue, (u) {
      final d = _ascii(u.codeUnitAt(0));
      return d >= 0x30 && d <= 0x39 ? String.fromCharCode(d) : '';
    });
    if (v.text.length <= max) return v;
    if (_digitsOf(oldValue.text).length >= max) return oldValue;
    final run = RegExp('(?:[0-9][ -]?){${max - 1}}[0-9]');
    final e = _edit(oldValue.text, newValue.text);
    final match = run.firstMatch(asciiDigits(newValue.text.substring(e.start, e.end))) ?? run.firstMatch(asciiDigits(newValue.text));
    final digits = match == null ? v.text.substring(0, max) : _digitsOf(match[0]!);
    return TextEditingValue(text: digits, selection: TextSelection.collapsed(offset: digits.length));
  }
}

/// ASCII codes: each character kept only if [keep] matches it, a space becomes a dash, A–Z lowercased if [lower].
TextInputFormatter _code(RegExp keep, {bool lower = false}) => TextInputFormatter.withFunction(
      (_, v) => _rewrite(v, (u) {
        final c = u == ' ' ? '-' : lower ? u.toLowerCase() : u;
        return keep.hasMatch(c) ? c : '';
      }),
    );

/// SKU field: ASCII letters, digits and . _ / - (the DB check: no Unicode look-alikes), ≤60.
final skuInput = [_code(RegExp(r'^[A-Za-z0-9._/-]$')), const CodePointLimit(MaxLen.sku)];

/// Slug field: a–z, 0–9 and dashes, ≤160. Capitals are lowercased and spaces become dashes as you type.
final slugInput = [_code(RegExp(r'^[a-z0-9-]$'), lower: true), const CodePointLimit(MaxLen.slug)];

// Indian mobile ----------------------------------------------------------------

/// "9876543210" → "98765 43210" (any shorter prefix as typed so far).
String groupMobile(String digits) => digits.length <= 5 ? digits : '${digits.substring(0, 5)} ${digits.substring(5)}';

/// The phone field's text for a stored number: "+919876543210" → "98765 43210"; '' when it isn't a mobile.
String localPhone(String? any) {
  final p = normalizeIndianPhone(any ?? '');
  return p == null ? '' : groupMobile(p.substring(3));
}

/// The 10 digits of a pasted number with its country or trunk prefix ("0091…", "+91…", "0…"), else null.
String? _localDigits(String digits) => RegExp(r'^(?:0091|091|91|0)?([6-9][0-9]{9})$').firstMatch(digits)?[1];

/// The phone field after a fixed "+91": at most 10 digits, shown "98765 43210". A pasted or autofilled
/// "+91 98765-43210", "098765 43210" or "919876543210" becomes the 10 digits; anything else that would make an
/// 11th digit is ignored. One exception: someone typing "91" before their number gets to finish it (at 12 digits
/// the 91 is dropped), so the field never keeps a wrong 10-digit "9198765432".
class IndianMobileFormatter extends TextInputFormatter {
  const IndianMobileFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final now = newValue.text;
    var digits = _digitsOf(now);
    var caret = _digitsOf(now.substring(0, newValue.selection.end.clamp(0, now.length))).length;
    // Backspace over the space deletes the digit before it instead of doing nothing.
    final at = newValue.selection.end, before = oldValue.text;
    final spaceDeleted = now.length == before.length - 1 &&
        at >= 0 &&
        at < before.length &&
        before[at] == ' ' &&
        before.substring(0, at) + before.substring(at + 1) == now;
    if (spaceDeleted && caret > 0) {
      digits = digits.substring(0, caret - 1) + digits.substring(caret);
      caret--;
    }
    if (digits.length > 10 && !(digits.length == 11 && digits.startsWith('91'))) {
      final e = _edit(oldValue.text, now);
      final local = _localDigits(digits) ?? _localDigits(_digitsOf(now.substring(e.start, e.end)));
      if (local == null) return oldValue;
      digits = local;
      caret = 10;
    }
    return TextEditingValue(
      text: groupMobile(digits),
      selection: TextSelection.collapsed(offset: caret > 5 ? caret + 1 : caret),
    );
  }
}

/// Null for a 10-digit Indian mobile (the field may hold it grouped or with a prefix).
String? validateMobile(String? v) {
  final digits = _digitsOf(v ?? '');
  if (normalizeIndianPhone(digits) != null) return null;
  if (digits.length != 10) return 'Enter a 10-digit mobile number.';
  return 'Mobile numbers start with 6, 7, 8 or 9.';
}

// Other formats ----------------------------------------------------------------

/// Rupees: digits and at most 2 decimals, no sign, at most [maxDigits] before the point. A pasted "₹74,999.00"
/// or "Rs. 1,499" keeps just the amount. A keystroke that breaks a rule is ignored.
class RupeesFormatter extends TextInputFormatter {
  const RupeesFormatter({required this.maxDigits});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digitSeen = false;
    final v = _rewrite(newValue, (u) {
      final d = _ascii(u.codeUnitAt(0));
      if (d >= 0x30 && d <= 0x39) {
        digitSeen = true;
        return String.fromCharCode(d);
      }
      return u == '.' && digitSeen ? '.' : ''; // the point of "Rs." isn't a decimal point
    });
    return RegExp('^[0-9]{0,$maxDigits}(\\.[0-9]{0,2})?\$').hasMatch(v.text) ? v : oldValue;
  }
}

/// A colour code "#RRGGBB": hex digits only, uppercase, "#" added for you, blank stays blank.
class HexColorFormatter extends TextInputFormatter {
  const HexColorFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final now = newValue.text;
    String hexOf(String s) => s.toUpperCase().replaceAll(RegExp('[^0-9A-F]'), '');
    var hex = hexOf(now);
    if (hex.length > 6) {
      if (hexOf(oldValue.text).length >= 6 && now.length == oldValue.text.length + 1) return oldValue;
      hex = hex.substring(0, 6); // "#1F2B4DFF": the alpha is dropped
    }
    final caret = hexOf(now.substring(0, newValue.selection.end.clamp(0, now.length))).length.clamp(0, hex.length);
    return hex.isEmpty
        ? TextEditingValue.empty
        : TextEditingValue(text: '#$hex', selection: TextSelection.collapsed(offset: caret + 1));
  }
}

final _email = RegExp(r'^[^@\s.]+(?:\.[^@\s.]+)*@[^@\s.]+(?:\.[^@\s.]+)*\.[^@\s.]{2,}$');

/// Trimmed and lowercased, as it's sent to sign-in.
String normalizeEmail(String s) => tidy(s).replaceAll(' ', '').toLowerCase();

/// Null for a plausible address: one @, a dot in the domain, no spaces or empty parts, ≤254 characters.
String? validateEmail(String? v) {
  final e = normalizeEmail(v ?? '');
  if (e.isEmpty) return 'Enter your email address.';
  return e.length <= MaxLen.email && e.indexOf('@') <= 64 && _email.hasMatch(e) ? null : 'Enter a valid email address.';
}

/// Formatters for an email field: no spaces, nothing invisible, ≤254.
final emailInput = [FilteringTextInputFormatter.deny(RegExp(r'\s')), ...textInput(MaxLen.email)];

/// "120/500" under a long field, counted the way [CodePointLimit] and the DB count (Flutter's own counter
/// counts grapheme clusters, so it would read low for Hindi).
class LengthCounter extends StatelessWidget {
  const LengthCounter(this.controller, this.max, {super.key});

  final TextEditingController controller;
  final int max;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final n = controller.text.runes.length;
          return Semantics(
            label: '${max - n} characters left',
            excludeSemantics: true,
            child: Text('$n/$max', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          );
        },
      );
}
