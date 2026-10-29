import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/format.dart';

/// 28 states + 8 union territories, as India Post spells them today.
const indianStates = [
  'Andaman and Nicobar Islands', 'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chandigarh', //
  'Chhattisgarh', 'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Goa', 'Gujarat', 'Haryana',
  'Himachal Pradesh', 'Jammu and Kashmir', 'Jharkhand', 'Karnataka', 'Kerala', 'Ladakh', 'Lakshadweep',
  'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Puducherry',
  'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
  'West Bengal',
];

// Old or misspelt names still returned by api.postalpincode.in.
const _stateAliases = {
  'chattisgarh': 'Chhattisgarh',
  'orissa': 'Odisha',
  'pondicherry': 'Puducherry',
  'uttaranchal': 'Uttarakhand',
  'new delhi': 'Delhi',
  'dadra and nagar haveli': 'Dadra and Nagar Haveli and Daman and Diu',
  'daman and diu': 'Dadra and Nagar Haveli and Daman and Diu',
};

/// Maps a free-text state to an entry of [indianStates], or null.
String? matchState(String raw) {
  final key = raw.toLowerCase().replaceAll('&', 'and').replaceAll(RegExp(r'\s+'), ' ').trim();
  for (final s in indianStates) {
    if (s.toLowerCase() == key) return s;
  }
  return _stateAliases[key];
}

// Validators return null when valid, else short copy. Limits mirror the `addresses` table checks.

String? _length(String? v, String what, int min, int max) {
  final n = (v ?? '').trim().length;
  if (n == 0 && min > 0) return 'Enter $what.';
  if (n < min) return 'Too short.';
  if (n > max) return 'Keep it under ${max + 1} characters.';
  return null;
}

String? validateName(String? v) => _length(v, 'a name', 2, 80);
String? validateLine1(String? v) => _length(v, 'house and street', 3, 120);
String? validateLine2(String? v) => _length(v, '', 0, 120);
String? validateLandmark(String? v) => _length(v, '', 0, 80);
String? validateCity(String? v) => _length(v, 'a city', 2, 60);
String? validateState(String? v) => v == null || v.isEmpty ? 'Pick a state.' : null;
String? validatePhone(String? v) => normalizeIndianPhone(v ?? '') == null ? 'Enter a 10-digit mobile number.' : null;
String? validatePincode(String? v) =>
    RegExp(r'^[1-9][0-9]{5}$').hasMatch((v ?? '').trim()) ? null : 'Enter a 6-digit pincode.';

typedef PincodePlace = ({String city, String? state});

/// Reads the India Post response: `[{"Status":"Success","PostOffice":[{"District":..,"State":..}]}]`.
PincodePlace? parsePincodeResponse(String body) {
  try {
    final first = (jsonDecode(body) as List).first as Map;
    if (first['Status'] != 'Success') return null;
    final office = (first['PostOffice'] as List).first as Map;
    final city = (office['District'] as String).trim();
    if (city.isEmpty) return null;
    return (city: city, state: matchState(office['State'] as String? ?? ''));
  } catch (_) {
    return null;
  }
}

/// Best effort: null on any failure or after 5 s.
Future<PincodePlace?> lookupPincode(String pincode, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(Uri.https('api.postalpincode.in', '/pincode/$pincode'))
        .timeout(const Duration(seconds: 5));
    return res.statusCode == 200 ? parsePincodeResponse(res.body) : null;
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}
