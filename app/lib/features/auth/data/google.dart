import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// Android only needs the web client id (Credential Manager mints an ID token for it).
bool get googleSignInAvailable => Env.googleWebClientId.isNotEmpty && (!_isIos || Env.googleIosClientId.isNotEmpty);

Future<void>? _init;

// GoogleSignIn.initialize must run exactly once per app run, before any other call.
Future<void> _ensureInit() => _init ??= GoogleSignIn.instance.initialize(
      serverClientId: Env.googleWebClientId,
      clientId: _isIos ? Env.googleIosClientId : null, // untested: v1 ships on Android only
    );

/// Native Google sheet, then a Supabase session from its ID token. Returns false if the user backed out.
Future<bool> signInWithGoogle(GoTrueClient auth) async {
  await _ensureInit();
  final GoogleSignInAccount account;
  try {
    account = await GoogleSignIn.instance.authenticate();
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return false;
    rethrow;
  }
  final idToken = account.authentication.idToken;
  if (idToken == null) {
    throw const GoogleSignInException(code: GoogleSignInExceptionCode.unknownError, description: 'No ID token');
  }
  await auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
  return true;
}

/// So the next Google sign-in shows the account picker again. Never throws.
Future<void> signOutOfGoogle() async {
  if (!googleSignInAvailable) return;
  try {
    await _ensureInit();
    await GoogleSignIn.instance.signOut();
  } catch (_) {}
}
