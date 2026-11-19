import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// 12999900 → "₹1,29,999", 4950 → "₹49.50", -4950 → "-₹49.50". Shows paise only when there are some.
/// Integer maths only: rupees and paise are formatted separately, never through a double.
String formatInr(int paise) {
  if (paise < 0) return '-${formatInr(-paise)}';
  final rupees = _inr.format(paise ~/ 100);
  return paise % 100 == 0 ? rupees : '$rupees.${(paise % 100).toString().padLeft(2, '0')}';
}

/// Whole-percent discount off MRP, rounded down so we never overstate it.
int discountPercent(int pricePaise, int mrpPaise) =>
    mrpPaise <= pricePaise ? 0 : ((mrpPaise - pricePaise) * 100) ~/ mrpPaise;

String formatDate(DateTime d) => DateFormat('d MMM y').format(d.toLocal());
String formatDateTime(DateTime d) => DateFormat('d MMM y, h:mm a').format(d.toLocal());

/// "98765 43210" / "+91 98765 43210" / "098765-43210" → "+919876543210", or null if not an Indian mobile.
String? normalizeIndianPhone(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  final local = digits.length == 12 && digits.startsWith('91')
      ? digits.substring(2)
      : digits.length == 11 && digits.startsWith('0')
          ? digits.substring(1)
          : digits;
  return RegExp(r'^[6-9]\d{9}$').hasMatch(local) ? '+91$local' : null;
}

/// "+919876543210" → "+91 98765 43210"
String displayPhone(String e164) =>
    e164.length == 13 ? '${e164.substring(0, 3)} ${e164.substring(3, 8)} ${e164.substring(8)}' : e164;

/// The only links the app hands to other apps: the dialler, https (WhatsApp, Maps, policy pages) and UPI.
/// Store settings and admin-typed links are data, so anything else (intent:, file:, javascript:) is refused.
bool isAllowedExternalUri(Uri uri) =>
    uri.scheme == 'tel' || uri.scheme == 'upi' || (uri.scheme == 'https' && uri.host.isNotEmpty);

/// The shop's pages, kept as bare usernames (store_settings.instagram_handle / facebook_handle, settings/business
/// instagramHandle / facebookHandle). The patterns match the database's checks.
enum SocialSite {
  instagram(['instagram.com'], r'^[A-Za-z0-9._]{1,30}$'),
  facebook(['facebook.com', 'fb.com'], r'^[A-Za-z0-9.]{5,50}$');

  const SocialSite(this.hosts, this._pattern);

  final List<String> hosts;
  final String _pattern;

  /// "@shop", "shop" or a pasted link ("instagram.com/shop/", "https://m.facebook.com/shop?ref=x") → "shop". A link
  /// to another site comes back whole, so [valid] refuses it.
  String bare(String input) {
    final s = input.trim();
    if (s.startsWith('@')) return s.substring(1);
    if (!s.contains('/')) return s;
    final uri = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    final host = uri?.host.toLowerCase() ?? '';
    if (!hosts.any((h) => host == h || host.endsWith('.$h'))) return s;
    return uri!.pathSegments.firstWhere((p) => p.isNotEmpty, orElse: () => s);
  }

  bool valid(String handle) => RegExp(_pattern).hasMatch(handle);

  /// `https://instagram.com/<handle>`, `https://facebook.com/<handle>`: the app opens it when installed, else the browser.
  Uri url(String handle) => Uri.https(hosts.first, '/$handle');
}

/// Google Maps directions to [address] (opens the Maps app, or the browser). Maps universal link: no API key.
Uri directionsUri(String address) =>
    Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': address});

/// Google Maps centred on a pin, with the place card when Maps knows one there.
Uri mapPinUri(double lat, double lng) =>
    Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$lat,$lng'});
