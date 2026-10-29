import 'package:intl/intl.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';

/// Mirrors the transition table in `admin_update_order` (supabase/migrations/20261028000200_rpcs.sql).
/// Keep the two in sync; test/features/admin/rules_test.dart pins it.
const orderTransitions = <OrderStatus, List<OrderStatus>>{
  OrderStatus.pendingPayment: [OrderStatus.cancelled],
  OrderStatus.confirmed: [OrderStatus.packed, OrderStatus.cancelled],
  OrderStatus.packed: [OrderStatus.shipped, OrderStatus.cancelled],
  OrderStatus.shipped: [OrderStatus.delivered],
  OrderStatus.delivered: [OrderStatus.refunded],
};

List<OrderStatus> nextOrderStatuses(OrderStatus s) => orderTransitions[s] ?? const [];

/// Repair forward step (SPEC state machine). Any open booking can also be cancelled.
const repairNextStep = <RepairStatus, RepairStatus>{
  RepairStatus.requested: RepairStatus.confirmed,
  RepairStatus.confirmed: RepairStatus.inProgress,
  RepairStatus.inProgress: RepairStatus.ready,
  RepairStatus.ready: RepairStatus.completed,
};

/// DB columns are int4.
const _maxPaise = 2147483647;

/// "74,999" / "₹ 74999.5" → 7499950 paise. Null unless it's a plain amount with at most 2 decimals that fits the DB.
int? parseRupees(String input) {
  final m = RegExp(r'^(\d{1,8})(?:\.(\d{1,2}))?$').firstMatch(input.replaceAll(RegExp(r'[₹,\s]'), ''));
  if (m == null) return null;
  final paise = int.parse(m[1]!) * 100 + int.parse((m[2] ?? '').padRight(2, '0'));
  return paise <= _maxPaise ? paise : null;
}

/// Business caps on money fields (well inside int4 paise): prices, MRPs, COD and free-delivery limits, quotes.
const maxAmountPaise = 100000000; // ₹10,00,000
const maxFeePaise = 1000000; // ₹10,000: the delivery fee

/// Null when [v] is an amount of [minPaise]..[maxPaise]; blank is fine only when [optional].
String? rupeesError(String? v, {required int maxPaise, int minPaise = 0, bool optional = false}) {
  if ((v ?? '').trim().isEmpty) return optional ? null : 'Enter an amount.';
  final paise = parseRupees(v!);
  if (paise == null) return 'Enter an amount like 499 or 74999.50.';
  if (paise < minPaise) return minPaise <= 1 ? 'Enter an amount above ₹0.' : 'Enter at least ${formatInr(minPaise)}.';
  if (paise > maxPaise) return 'Keep it at or under ${formatInr(maxPaise)}.';
  return null;
}

/// 7499950 → "74999.50", 7499900 → "74999". For prefilling rupee fields.
String rupeesText(int paise) =>
    paise % 100 == 0 ? '${paise ~/ 100}' : '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

/// Tile money: "₹49,999", "₹4.82L", "₹1.2Cr". Rounded down, paise dropped.
String shortInr(int paise) {
  final rupees = paise ~/ 100;
  String short(int unit, String suffix) {
    final hundredths = rupees * 100 ~/ unit;
    final frac = (hundredths % 100).toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '');
    return '₹${hundredths ~/ 100}${frac.isEmpty || frac == '0' ? '' : '.$frac'}$suffix';
  }

  if (rupees >= 10000000) return short(10000000, 'Cr');
  if (rupees >= 100000) return short(100000, 'L');
  return formatInr(rupees * 100);
}

final _imei = RegExp(r'^\d{15}$');

/// IMEIs end in a Luhn check digit, so most single-digit typos are caught before they reach an invoice.
bool imeiChecksumOk(String imei) {
  var sum = 0;
  for (var i = 0; i < imei.length; i++) {
    var d = imei.codeUnitAt(imei.length - 1 - i) - 48;
    if (i.isOdd) d = d * 2 > 9 ? d * 2 - 9 : d * 2;
    sum += d;
  }
  return sum % 10 == 0;
}

String? imeiFieldError(String v) => !_imei.hasMatch(v)
    ? 'Enter all 15 digits'
    : imeiChecksumOk(v)
        ? null
        : 'One digit looks wrong. Check it against the box label.';

/// Mirrors `admin_set_imeis`: exactly [qty] values, 15 digits each, no repeats.
String? imeisError(List<String> imeis, int qty) {
  if (imeis.length != qty) return 'Enter $qty IMEI${qty == 1 ? '' : 's'}';
  if (imeis.any((i) => !_imei.hasMatch(i))) return 'Each IMEI is 15 digits';
  if (imeis.any((i) => !imeiChecksumOk(i))) return 'One IMEI has a digit wrong. Check it against the box label.';
  if (imeis.toSet().length != imeis.length) return 'An IMEI is repeated. Each unit has its own.';
  return null;
}

/// Same rule as the DB check on products/brands/categories.
final slugPattern = RegExp(r'^[a-z0-9-]{1,160}$');

/// Same rule as the DB check on variants.sku: ASCII, starts with a letter or digit, ≤60.
final skuPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]{0,59}$');

/// A new brand's display name: spaces tidied and the first letter capitalised ("itel" → "Itel").
String brandDisplayName(String typed) {
  final s = typed.trim().replaceAll(RegExp(r'\s+'), ' ');
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// "Samsung Galaxy S25+ (12 GB)" → "samsung-galaxy-s25-plus-12-gb".
String slugify(String name) => name
    .toLowerCase()
    .replaceAll('+', ' plus ')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

final hexColorPattern = RegExp(r'^#[0-9a-fA-F]{6}$');

/// "8 GB · 256 GB · Black", the default variant name.
String variantName(List<String> parts) => parts.map((p) => p.trim()).where((p) => p.isNotEmpty).join(' · ');

/// Plain-words WhatsApp update for the customer about an order.
String orderUpdateText(Order o) {
  final where = switch (o.status) {
    OrderStatus.pendingPayment => 'waiting for payment',
    OrderStatus.confirmed => 'confirmed and being prepared',
    OrderStatus.packed => 'packed and will ship soon',
    OrderStatus.shipped => o.courier == null
        ? 'on its way'
        : 'on its way with ${o.courier}${o.trackingNumber == null ? '' : ' (tracking ${o.trackingNumber})'}',
    OrderStatus.delivered => 'delivered. Thank you for shopping with us',
    OrderStatus.cancelled => o.needsRefund ? 'cancelled. Your refund of ${formatInr(o.totalPaise)} is on its way' : 'cancelled',
    OrderStatus.refunded => 'refunded',
  };
  return 'Hi ${o.address.name}, your Shyam Mobiles order ${o.number} is $where.';
}

/// Plain-words WhatsApp update for the customer about a repair.
String repairUpdateText(RepairBooking b) {
  final when = '${DateFormat('EEE d MMM').format(b.preferredDate)}, ${b.slot.label.toLowerCase()} (${b.slot.hours})';
  final where = switch (b.status) {
    RepairStatus.requested => 'booked for $when. We’ll confirm your slot soon',
    RepairStatus.confirmed => 'confirmed for $when',
    RepairStatus.inProgress => 'being repaired now',
    RepairStatus.ready => 'ready for pickup',
    RepairStatus.completed => 'completed. Thank you',
    RepairStatus.cancelled => 'cancelled',
  };
  final quote = b.quotePaise == null || !b.status.isOpen
      ? ''
      : ' Quote: ${formatInr(b.quotePaise!)}. Work starts only after you approve it.';
  return 'Hi, your Shyam Mobiles repair ${b.number} (${b.deviceBrand} ${b.deviceModel}) is $where.$quote';
}

const _num = r'(-?\d{1,3}(?:\.\d+)?)';

// First match wins: a place's own pin (!3d…!4d…), then query/q/ll params, then the @ viewport centre, then plain text.
final _pinPatterns = [
  RegExp('!3d$_num!4d$_num'),
  RegExp('[?&](?:query|q|ll)=$_num,\\s*$_num'),
  RegExp('@$_num,$_num'),
  RegExp('^\\s*$_num\\s*,\\s*$_num\\s*\$'),
];

/// A Google Maps link (full, not maps.app.goo.gl) or "lat, lng" → the pin, or null unless it's inside India.
({double lat, double lng})? parseMapPin(String input) {
  var s = input.trim();
  try {
    s = Uri.decodeFull(s); // query=24.06%2C82.62
  } catch (_) {}
  for (final p in _pinPatterns) {
    final m = p.firstMatch(s);
    if (m == null) continue;
    final lat = double.parse(m[1]!), lng = double.parse(m[2]!);
    return lat >= 6 && lat <= 38 && lng >= 68 && lng <= 98 ? (lat: lat, lng: lng) : null;
  }
  return null;
}

/// A shareable Google Maps place link: worth keeping as the shop's listing (`store_maps_url`).
bool isMapsPlaceLink(String input) {
  final s = input.trim();
  return s.length <= 500 && s.startsWith('https://') && s.contains('/maps/place/') && parseMapPin(s) != null;
}
