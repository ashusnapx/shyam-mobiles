import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _inrPaise = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// 12999900 → "₹1,29,999". Shows paise only when there are some.
String formatInr(int paise) => paise % 100 == 0 ? _inr.format(paise ~/ 100) : _inrPaise.format(paise / 100);

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
