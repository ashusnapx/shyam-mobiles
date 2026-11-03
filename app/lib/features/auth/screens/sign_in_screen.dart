import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/env.dart';
import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../account/widgets/policies.dart';
import '../data/auth_errors.dart';
import '../data/auth_repository.dart';
import '../data/google.dart';
import '../widgets/dev_login.dart';
import 'name_screen.dart';

/// One calm screen: Continue with Google, or a mobile number and a code by SMS. Nothing promotional here.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.from});

  final String? from;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  String? _error;
  bool _sending = false;
  bool _googleBusy = false;
  bool _byPhone = false; // a code was asked for: a first phone sign-up names itself before going back

  late final _termsTap = TapGestureRecognizer()..onTap = () => openPolicy(context, 'terms');
  late final _privacyTap = TapGestureRecognizer()..onTap = () => openPolicy(context, 'privacy');

  @override
  void initState() {
    super.initState();
    // go_router checks redirects against the route this screen was pushed over, not /sign-in, so leave
    // explicitly once a session exists. Phone (from the code screen above), Google and dev sign-in all land here.
    ref.listenManual(currentUserIdProvider, (_, uid) {
      if (uid != null && mounted) context.go(afterSignInPath(widget.from, byPhone: _byPhone));
    });
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_sending || _googleBusy) return;
    if (validateMobile(_phone.text) case final error?) {
      setState(() => _error = error);
      return;
    }
    final phone = normalizeIndianPhone(_phone.text)!;
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      final request = await ref.read(authRepositoryProvider).requestPhoneCode(phone);
      _byPhone = true;
      if (!mounted || request.autoVerified) return; // the phone read the SMS itself: signed in, the listener leaves
      unawaited(context.push(
        Uri(path: '/sign-in/verify', queryParameters: {'phone': phone, 'from': ?widget.from}).toString(),
        extra: request,
      ));
    } catch (e) {
      if (!mounted) return;
      final message = authError(e).message;
      showMessage(context, message,
          action: message == tooManyTries ? null : SnackBarAction(label: 'Try again', onPressed: _sendCode));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _google() async {
    if (_sending || _googleBusy) return;
    setState(() => _googleBusy = true);
    _byPhone = false;
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle(); // backed out: nothing to say; in: the listener leaves
    } catch (e) {
      if (!mounted) return;
      showMessage(context,
          e is GoogleSignInException ? 'Couldn’t sign in with Google. Try again, or use your mobile number.' : authError(e).message);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final quiet = t.bodyMedium?.copyWith(color: c.onSurfaceVariant);
    final link = TextStyle(color: c.onSurface, fontWeight: FontWeight.w600, decoration: TextDecoration.underline);
    final digits = t.titleMedium?.copyWith(fontSize: 18, fontFeatures: const [FontFeature.tabularFigures()]);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  Space.gutter, Space.sm, Space.gutter, Space.lg + MediaQuery.paddingOf(context).bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BrandMark(size: 52, ripple: true),
                      const SizedBox(height: Space.gutter),
                      Semantics(header: true, child: Text('Welcome to Shyam Mobiles', style: t.displaySmall)),
                      const SizedBox(height: Space.sm),
                      Text('Phones, accessories and repairs in Waidhan', style: quiet),
                    ],
                  ).enter(context),
                  const SizedBox(height: Space.xxl),
                  if (googleSignInAvailable) ...[
                    _GoogleButton(busy: _googleBusy, onPressed: _sending ? null : _google).enter(context, index: 1),
                    const SizedBox(height: Space.gutter),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.md),
                          child: Text('or', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: Space.gutter),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ExcludeSemantics(child: Text('Mobile number', style: t.titleSmall)),
                      const SizedBox(height: Space.sm),
                      Semantics(
                        label: 'Mobile number',
                        child: TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumberNational],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _sendCode(),
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                          // 10 digits after the fixed +91; a pasted "+91 98765-43210" or "098765 43210" becomes them
                          inputFormatters: const [IndianMobileFormatter()],
                          style: digits,
                          decoration: InputDecoration(
                            hintText: '98765 43210',
                            hintStyle: digits?.copyWith(color: c.onSurfaceVariant, fontWeight: FontWeight.w400),
                            errorText: _error,
                            prefixIcon: Padding(
                              padding: const EdgeInsets.only(left: Space.lg, right: Space.md),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('+91', style: digits),
                                  const SizedBox(width: Space.md),
                                  SizedBox(width: 1, height: 24, child: ColoredBox(color: c.outline)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      FilledButton(
                        onPressed: _googleBusy ? null : _sendCode,
                        child: _sending ? const ButtonSpinner() : const Text('Get code'),
                      ),
                    ],
                  ).enter(context, index: 2),
                  const Spacer(),
                  const SizedBox(height: Space.xl),
                  if (Env.devLogin) const DevLoginButtons(),
                  // Play requires the privacy policy to be reachable inside the app, so these are real links.
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'By continuing you agree to the '),
                      TextSpan(text: 'Terms', style: link, recognizer: _termsTap),
                      const TextSpan(text: ' and '),
                      TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacyTap),
                      const TextSpan(text: '.'),
                    ]),
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Google's light "Continue with Google" button (developers.google.com/identity/branding-guidelines): white, a
/// #747775 hairline, #1F1F1F Roboto Medium and the full-colour G, never recoloured.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          disabledBackgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          side: const BorderSide(color: Color(0xFF747775)),
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const ButtonSpinner()
            else
              Image.asset('assets/brand/google_g.png', width: 20, height: 20, excludeFromSemantics: true),
            const SizedBox(width: 10),
            const Flexible(child: Text('Continue with Google')),
          ],
        ),
      );
}
