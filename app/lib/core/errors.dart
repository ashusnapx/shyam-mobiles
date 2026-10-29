import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

const _codes = {
  'CART_EMPTY': 'Your cart is empty.',
  'ADDRESS_NOT_FOUND': 'Pick a delivery address.',
  'OUT_OF_STOCK': 'Some items just went out of stock. Check your cart and try again.',
  'COD_UNAVAILABLE': 'Cash on delivery isn’t available for this order. Pay online instead.',
  'INVALID_TRANSITION': 'This can’t be changed any more.',
  'NOT_FOUND': 'We couldn’t find that. It may have been removed.',
  'FORBIDDEN': 'You don’t have access to this.',
  'ORDER_NOT_PAYABLE': 'This order can’t be paid any more.',
  'ORDER_EXPIRED': 'The payment window closed, so the order was cancelled and nothing was charged. Add the items to your cart again to reorder.',
  'BAD_SIGNATURE': 'We couldn’t confirm that payment. If money was taken, it will be refunded automatically.',
  'ACTIVE_ORDERS': 'You have orders or repairs in progress. You can delete your account once they’re finished.',
  'GATEWAY_ERROR': 'The payment service didn’t respond. Try again in a moment.',
  'ADDRESS_LIMIT': 'You can save up to 10 addresses. Delete one to add another.',
  'INVALID_IMEIS': 'Each IMEI must be 15 digits, one per unit, with no repeats.',
  'PAYMENT_MISMATCH': 'That payment doesn’t match this order. If money was taken, it will be refunded.',
  'INTERNAL': fallbackError,
};

const fallbackError = 'Something went wrong. Try again.';

/// User-facing copy for any error thrown by Supabase, Edge Functions or the network.
String friendlyError(Object e) {
  switch (e) {
    case PostgrestException(:final message, :final code):
      return _codes[message] ?? (code == '42501' ? _codes['FORBIDDEN']! : fallbackError);
    case FunctionException(:final details):
      final code = details is Map ? details['error'] : null;
      return _codes[code] ?? (details is Map && details['message'] is String ? details['message'] : fallbackError);
    case AuthException(:final message, :final statusCode):
      if (statusCode == '429' || message.contains('rate limit')) return 'Too many attempts. Wait a minute and try again.';
      if (message.contains('expired') || message.contains('invalid')) return 'That code is wrong or has expired. Request a new one.';
      return message;
    case SocketException() || HttpException():
      return 'You’re offline. Check your connection and try again.';
  }
  return fallbackError;
}
