import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../../core/errors.dart';

const tooManyTries = 'Too many tries. Wait a minute and try again.';

/// What went wrong in a sign-in step, in plain words. [badCode]: the typed code itself was refused, so the code screen
/// clears the boxes; anything else (offline, too many tries) keeps the code for another go.
({String message, bool badCode}) authError(Object e) => switch (e) {
      AuthException(:final statusCode, :final code, :final message)
          when statusCode == '429' || (code?.startsWith('over_') ?? false) || message.contains('rate limit') =>
        (message: tooManyTries, badCode: false),
      // Supabase answers otp_expired for a wrong code too, so one message covers both
      AuthException(:final code, :final message) when code == 'otp_expired' || message.contains('Token has expired') =>
        (message: 'That code is wrong or has expired. Check the SMS, or get a new code.', badCode: true),
      FirebaseAuthException(code: 'too-many-requests' || 'quota-exceeded') => (message: tooManyTries, badCode: false),
      FirebaseAuthException(code: 'invalid-verification-code') =>
        (message: 'That code is wrong. Check the SMS and type it again.', badCode: true),
      FirebaseAuthException(code: 'session-expired' || 'code-expired') =>
        (message: 'That code has expired. Get a new code below.', badCode: true),
      _ => (message: friendlyError(e), badCode: false),
    };
