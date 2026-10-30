import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'format.dart';

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
  'BAD_SIGNATURE': 'We couldn’t confirm that payment. If money left your account, call or WhatsApp the store with the order number and we’ll sort it out.',
  'ACTIVE_ORDERS': 'You have orders or repairs in progress, or a refund on its way. You can delete your account once they’re finished.',
  'GATEWAY_ERROR': 'The payment service didn’t respond. Try again in a moment.',
  'ADDRESS_LIMIT': 'You can save up to 10 addresses. Delete one to add another.',
  'PENDING_LIMIT': 'You already have 2 orders waiting for payment. Pay for or cancel one in My orders, then try again.',
  'CART_LIMIT': 'That’s the most your cart can hold. Check out what you have, then add more.',
  'REPAIR_LIMIT': 'You already have 3 repairs open. We’ll be in touch about those first. Call the store if it’s urgent.',
  'QUOTE_CHANGED': 'The store just changed the price. Check the new quote, then approve it.',
  'QUOTE_NOT_APPROVED': 'The customer hasn’t approved the current quote yet.',
  'BAD_REQUEST': 'Something in that request isn’t valid. Check it and try again.',
  'ORDER_TOO_LARGE': 'That order is too large to place in the app. Call or WhatsApp the store and we’ll help.',
  'INVALID_IMEIS': 'Each IMEI must be 15 digits, one per unit, with no repeats.',
  'PAYMENT_MISMATCH': 'That payment doesn’t match this order. If money left your account, call or WhatsApp the store with the order number and we’ll sort it out.',
  'INTERNAL': fallbackError,
  'UNAUTHORIZED': 'Your session has ended. Sign in again to continue.',
  'COUPON_NOT_FOUND': 'That code isn’t valid. Check the spelling and try again.',
  'COUPON_NOT_STARTED': 'That offer hasn’t started yet. Try again when it begins.',
  'COUPON_EXPIRED': 'That code has expired. See Offers for what’s on now.',
  'COUPON_USED_UP': 'That offer has run out. See Offers for what’s on now.',
  'COUPON_LIMIT_REACHED': 'You’ve already used this code as many times as it allows.',
  'COUPON_MIN_ORDER': 'Your cart is below this code’s minimum. Add a little more to use it.',
  'COUPON_NOT_APPLICABLE': 'This code doesn’t lower this order’s total. Check what it covers in Offers.',
  'COUPON_FIRST_ORDER': 'This code is only for your first order.',
  'COUPON_ONLINE_ONLY': 'This code works only when you pay online.',
  'COUPON_RATE_LIMIT': 'Too many wrong codes. Wait 10 minutes and try again.',
  'COUPON_BETTER_OFFER': 'A sale already saves you more on this order, so we’re using it. Keep the code for another order.',
  'REFERRAL_OFF': 'Refer & earn isn’t running right now.',
  'REFERRAL_INVALID': 'That code isn’t valid. Check it with your friend.',
  'REFERRAL_SELF': 'That’s your own code. Share it with a friend instead.',
  'REFERRAL_USED': 'You’ve already used a friend’s code.',
  'REFERRAL_TOO_LATE': 'Friend codes are for new customers, before their first order.',
  'CODE_TAKEN': 'Another offer already uses this code. Pick a different one, or tap Generate.',
  'INVALID_PROMOTION': 'Something in this offer isn’t allowed. Check the amount, dates and products.',
  // Staff payments (refund-payment, payment-link). Codes not listed here (REFUND_NOT_ALLOWED, REFUND_REFUSED,
  // LINK_NOT_ALLOWED, LINK_REFUSED) carry the server's own staff copy, often Razorpay's reason.
  'REFUND_IN_PROGRESS': 'A refund for this order is already with Razorpay. Wait until it’s done, then refresh.',
  'REFUND_UNCONFIRMED': 'Razorpay didn’t confirm the refund. Tap Refund again: it retries this same refund, never a second one.',
  'LINK_IN_PROGRESS': 'That link is still being made. Try again in a moment.',
  'LINK_NOT_OPEN': 'This link is already paid, cancelled or expired. Refresh to see it.',
  'FEEDBACK_LIMIT': 'That’s all the feedback we can take from you today. Thank you! Try again tomorrow, or call the shop.',
};

// admin_save_promotion's INVALID_PROMOTION names the broken rule in `details`.
const _promotionRules = {
  'promotions_value_check': 'Check the amount: 1 to 90 percent, or at least ₹1 off.',
  'promotions_window_check': 'The end has to be after the start.',
  'promotions_banner_check': 'Only listed shop offers can have a banner, not hidden or personal codes.',
  'items needs a target': 'Pick at least one product, category, brand or group.',
  'unknown target': 'Something you picked was deleted. Pick the products again.',
};

/// Copy for a coupon refusal: `quote_order`'s `coupon_error`, or the code `place_order` raised. With
/// [minPaise] (the raise's detail, or the listed offer's minimum) the minimum-order copy names the amount.
String couponError(String code, {int? minPaise}) => code == 'COUPON_MIN_ORDER' && minPaise != null
    ? 'This code needs a cart of ${formatInr(minPaise)} or more. Add a little more to use it.'
    : _codes[code] ?? 'That code can’t be used on this order.';

const fallbackError = 'Something went wrong. Try again.';
const _offline = 'You’re offline. Check your connection and try again.';

// PostgREST codes: 22P02 = a malformed uuid in the URL (/orders/garbage), PGRST116 = `.single()` found no row,
// PGRST301/PGRST303 = the JWT is invalid or expired.
const _notFoundCodes = {'22P02', 'PGRST116'};
const _sessionCodes = {'PGRST301', 'PGRST303'};
const _authSessionCodes = {'session_not_found', 'session_expired', 'refresh_token_not_found', 'refresh_token_already_used', 'bad_jwt'};

// 23514: a check constraint refused a value. Postgres names column checks `<table>_<column>_check`, so the column
// says which field it was. Normally unreachable (core/input.dart applies the same rules first).
const _checkFields = {
  'full_name': 'name', 'name': 'name', 'phone': 'mobile number', 'contact_phone': 'mobile number',
  'line1': 'house and street', 'line2': 'area and street', 'landmark': 'landmark', 'city': 'city',
  'district': 'district', 'state': 'state', 'pincode': 'pincode', 'device_brand': 'phone brand',
  'device_model': 'phone model', 'description': 'description', 'admin_note': 'note', 'note': 'note',
  'courier': 'courier', 'tracking_number': 'tracking number', 'sku': 'SKU', 'slug': 'slug', 'stock': 'stock',
  'attributes': 'colour code', 'specs': 'specs', 'price_paise': 'price', 'store_address': 'store address',
  'store_hours': 'opening hours', 'repair_note': 'repair note', 'returns_policy': 'returns policy',
  'store_maps_url': 'Google Maps link', 'imeis': 'IMEIs',
};

String _checkError(String message) {
  if (message.contains('in_phone')) return 'Check the mobile number and try again.'; // the phone domain's check
  final constraint = RegExp(r'constraint "(\w+)"').firstMatch(message)?[1] ?? '';
  if (constraint == 'variants_check') return 'The MRP can’t be below the price.';
  final field = (_checkFields.keys.where((k) => constraint.endsWith('_${k}_check')).toList()
        ..sort((a, b) => b.length - a.length))
      .firstOrNull;
  return field == null ? 'One of the fields isn’t valid. Check it and try again.' : 'Check the ${_checkFields[field]} and try again.';
}

/// The session is gone (expired and not refreshable, revoked, or the account was deleted elsewhere): retrying
/// can't help, signing in again does. ErrorView offers that instead of "Try again".
bool isSessionError(Object e) => switch (e) {
      PostgrestException(:final code) => _sessionCodes.contains(code) || code == '401',
      // The platform's own 401 body has no code, so any 401 means the session is gone.
      FunctionException(status: 401) => true,
      AuthSessionMissingException() => true,
      AuthException(:final code) => _authSessionCodes.contains(code),
      _ => false,
    };

/// User-facing copy for any error thrown by Supabase, Edge Functions or the network. Never shows raw server text.
String friendlyError(Object e) {
  if (isSessionError(e)) return _codes['UNAUTHORIZED']!;
  switch (e) {
    case PostgrestException(:final message, :final code, :final details):
      if (message.startsWith('COUPON_')) return couponError(message, minPaise: int.tryParse('${details ?? ''}'));
      if (message == 'INVALID_PROMOTION' && _promotionRules[details] != null) return _promotionRules[details]!;
      if (_codes[message] case final copy?) return copy;
      if (code == '42501') return _codes['FORBIDDEN']!;
      if (_notFoundCodes.contains(code)) return _codes['NOT_FOUND']!;
      if (code == '23514') return _checkError(message);
      return fallbackError;
    // The request never reached the function (offline, DNS, TLS).
    case FunctionsFetchException():
      return _offline;
    case FunctionException(:final details):
      final code = details is Map ? details['error'] : null;
      return _codes[code] ?? (details is Map && details['message'] is String ? details['message'] : fallbackError);
    case AuthRetryableFetchException():
      return _offline;
    case AuthException(:final message, :final statusCode, :final code):
      if (statusCode == '429' || (code?.startsWith('over_') ?? false) || message.contains('rate limit')) {
        return 'Too many attempts. Wait a minute and try again.';
      }
      if (code == 'otp_expired' || message.contains('Token has expired')) {
        return 'That code is wrong or has expired. Request a new one.';
      }
      if (code == 'validation_failed' || code == 'email_address_invalid' || code == 'phone_invalid') {
        return 'Check the number or email and try again.';
      }
      if (code == 'sms_send_failed') return 'We couldn’t send the code. Check the number, or use email instead.';
      if (code == 'signup_disabled' || code == 'otp_disabled') return 'Sign-in with a code isn’t available right now.';
      // Our own `AuthException('Sign in to …')` guards carry their copy; server codes above cover the rest.
      return code == null && statusCode == null ? message : fallbackError;
    case TimeoutException():
      return 'That took too long. Check your connection and try again.';
    case SocketException() || HttpException() || ClientException() || HandshakeException():
      return _offline;
  }
  return fallbackError;
}
