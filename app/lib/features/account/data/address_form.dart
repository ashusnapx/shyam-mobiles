import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' show Placemark;
import 'package:http/http.dart' as http;

import '../../../core/input.dart';

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

// Validators return null when valid, else short copy. Limits and the letter rule mirror the `addresses` table checks.

String? validateName(String? v) => checkText(v, min: 2, max: MaxLen.name, what: 'a name', mustHave: hasLetter);
String? validateLine1(String? v) => checkText(v, min: 3, max: MaxLen.addressLine, what: 'house and street');
String? validateLine2(String? v) => checkText(v, max: MaxLen.addressLine);
String? validateLandmark(String? v) => checkText(v, max: MaxLen.landmark);
String? validateCity(String? v) => checkText(v, min: 2, max: MaxLen.place, what: 'a city', mustHave: hasLetter);
String? validateDistrict(String? v) => checkText(v, max: MaxLen.place, mustHave: hasLetter);
String? validateState(String? v) => v == null || v.isEmpty ? 'Pick a state.' : null;
String? validatePhone(String? v) => validateMobile(v);
String? validatePincode(String? v) =>
    RegExp(r'^[1-9][0-9]{5}$').hasMatch((v ?? '').trim()) ? null : 'Enter a 6-digit pincode.';

/// `areas` are the pincode's post-office names, offered as one-tap areas.
typedef PincodePlace = ({String district, String? state, List<String> areas});

/// Reads the India Post response: `[{"Status":"Success","PostOffice":[{"Name":..,"District":..,"State":..}]}]`.
/// Null when the pincode has no post offices or the body is junk.
PincodePlace? parsePincodeResponse(String body) {
  try {
    final first = (jsonDecode(body) as List).first as Map;
    if (first['Status'] != 'Success') return null;
    final offices = (first['PostOffice'] as List).cast<Map>();
    final district = (offices.first['District'] as String).trim();
    if (district.isEmpty) return null;
    return (
      district: district,
      state: matchState(offices.first['State'] as String? ?? ''),
      areas: {
        for (final o in offices)
          if ((o['Name'] as String? ?? '').trim() case final n when n.isNotEmpty && n.length <= 120) n,
      }.toList(),
    );
  } catch (_) {
    return null;
  }
}

/// Null when India Post has no such pincode; throws when it can't be reached (offline, HTTP error, 5 s timeout).
Future<PincodePlace?> lookupPincode(String pincode, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final url = Uri.https('api.postalpincode.in', '/pincode/$pincode');
    final res = await c.get(url).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}', url);
    return parsePincodeResponse(res.body);
  } finally {
    if (client == null) c.close();
  }
}

/// The form's pincode lookup; tests override it to stay offline.
final pincodeLookupProvider = Provider<Future<PincodePlace?> Function(String)>((_) => lookupPincode);

typedef AddressGuess = ({String? line1, String? area, String? city, String? district, String? state, String? pincode});

// Android often puts a plus code ("7JFJ+2Q") in the feature name instead of a house or building.
final _plusCode = RegExp(r'^[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3}\b', caseSensitive: false);

/// Maps a reverse-geocoded placemark onto the form's fields; parts that are missing or unusable come back null.
AddressGuess addressFromPlacemark(Placemark p) {
  String? clean(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
  final area = clean(p.subLocality), city = clean(p.locality), pincode = clean(p.postalCode);
  final street = <String>[];
  for (final part in [clean(p.name), clean(p.subThoroughfare), clean(p.thoroughfare)]) {
    if (part == null || _plusCode.hasMatch(part) || part.toLowerCase() == 'unnamed road') continue;
    final key = part.toLowerCase();
    // The feature name often repeats the area, city or pincode, or already holds the house number and street.
    if ([area, city, pincode].any((o) => o?.toLowerCase() == key)) continue;
    if (street.any((s) => s.toLowerCase().contains(key))) continue;
    street.add(part);
  }
  return (
    line1: street.isEmpty ? null : street.join(', '),
    area: area,
    city: city,
    district: clean(p.subAdministrativeArea),
    state: matchState(p.administrativeArea ?? ''),
    pincode: validatePincode(pincode) == null ? pincode : null,
  );
}
