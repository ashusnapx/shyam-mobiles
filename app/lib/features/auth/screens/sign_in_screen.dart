import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/env.dart';
import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/router.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../account/widgets/policies.dart';
import '../data/google.dart';
import '../widgets/auth_hero.dart';
import '../widgets/dev_login.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.from});

  final String? from;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)..addListener(() => setState(() => _error = null));
  final _phone = TextEditingController();
  final _email = TextEditingController();
  String? _error;
  bool _sending = false;
  bool _googleBusy = false;

  late final _termsTap = TapGestureRecognizer()..onTap = () => openPolicy(context, 'terms.html');
  late final _privacyTap = TapGestureRecognizer()..onTap = () => openPolicy(context, 'privacy.html');

  bool get _usePhone => _tabs.index == 0;

  @override
  void initState() {
    super.initState();
    // go_router checks redirects against the route this screen was pushed over, not /sign-in, so leave
    // explicitly once a session exists. OTP (from the code screen above), Google and dev sign-in all land here.
    ref.listenManual(currentUserIdProvider, (_, uid) {
      if (uid != null && mounted) context.go(safeReturnPath(widget.from) ?? '/');
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_sending) return;
    final phone = normalizeIndianPhone(_phone.text);
    final email = normalizeEmail(_email.text);
    if ((_usePhone ? validateMobile(_phone.text) : validateEmail(email)) case final error?) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      final auth = ref.read(supabaseProvider).auth;
      _usePhone ? await auth.signInWithOtp(phone: phone) : await auth.signInWithOtp(email: email, shouldCreateUser: true);
      if (!mounted) return;
      // The code screen pops with 'phone' or 'email' when the user wants to switch method.
      unawaited(context.push<String>(Uri(path: '/sign-in/verify', queryParameters: {
        if (_usePhone) 'phone': phone else 'email': email,
        if (widget.from != null) 'from': widget.from,
      }).toString()).then((method) {
        if (mounted && method != null) _tabs.animateTo(method == 'email' ? 1 : 0);
      }));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _google() async {
    if (_googleBusy || _sending) return;
    setState(() => _googleBusy = true);
    try {
      await signInWithGoogle(ref.read(supabaseProvider).auth); // the router redirects on success
    } catch (e) {
      if (!mounted) return;
      showMessage(context, e is GoogleSignInException ? 'Google sign-in didn’t work. Use your phone or email instead.' : friendlyError(e));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final busy = _sending || _googleBusy;
    final label = t.labelMedium;
    final link = TextStyle(color: c.onSurface, fontWeight: FontWeight.w600, decoration: TextDecoration.underline);

    final field = _usePhone
        ? TextField(
            key: const ValueKey('phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendCode(),
            // 10 digits after the fixed +91; a pasted "+91 98765-43210" or "098765 43210" becomes them
            inputFormatters: const [IndianMobileFormatter()],
            style: t.bodyLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            decoration: InputDecoration(
              hintText: '98765 43210',
              errorText: _error,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: Space.lg, right: Space.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('+91', style: t.titleSmall),
                    const SizedBox(width: Space.md),
                    SizedBox(width: 1, height: 22, child: ColoredBox(color: c.outline)),
                  ],
                ),
              ),
            ),
          )
        : TextField(
            key: const ValueKey('email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: emailInput,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendCode(),
            decoration: InputDecoration(hintText: 'you@example.com', errorText: _error),
          );

    // Typing: the hero folds into a compact bar so the form stays fully in view and nothing is cut off.
    final compact = MediaQuery.viewInsetsOf(context).bottom > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarIconBrightness: Brightness.light, statusBarBrightness: Brightness.dark),
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // hero spans the screen on any width
          children: [
            // while the keyboard slides up, the folding hero can be taller than the room above it for a few frames:
            // clip it there instead of overflowing
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ClipRect(
                child: OverflowBox(
                  fit: OverflowBoxFit.deferToChild,
                  maxHeight: double.infinity,
                  alignment: Alignment.topCenter,
                  child: AuthHero(
                    compact: compact,
                    leading: heroButton(
                      tooltip: 'Close',
                      icon: PhosphorIconsRegular.x,
                      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -26),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 22, 20, Space.lg + MediaQuery.paddingOf(context).bottom),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!compact) const _Benefits(),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.surfaceContainer,
                              borderRadius: BorderRadius.circular(Radii.md + 2),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(Space.xs),
                              child: TabBar(
                                controller: _tabs,
                                indicatorSize: TabBarIndicatorSize.tab,
                                dividerHeight: 0,
                                splashBorderRadius: BorderRadius.circular(Radii.sm + 2),
                                // the chosen tab in peacock; the button below stays ink
                                indicator: BoxDecoration(
                                  color: BrandColors.peacockMist,
                                  borderRadius: BorderRadius.circular(Radii.sm + 2),
                                  border: Border.all(color: BrandColors.peacock.withValues(alpha: 0.35)),
                                ),
                                labelColor: BrandColors.peacockInk,
                                unselectedLabelColor: c.onSurfaceVariant,
                                labelStyle: t.titleSmall,
                                tabs: const [Tab(height: 44, text: 'Phone'), Tab(height: 44, text: 'Email')],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          ExcludeSemantics(child: Text(_usePhone ? 'Mobile number' : 'Email', style: label)),
                          const SizedBox(height: Space.sm),
                          Semantics(label: _usePhone ? 'Mobile number' : 'Email', child: _peacockFocus(context, field)),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: busy ? null : _sendCode,
                            child: _sending ? const _Spinner() : const Text('Send code'),
                          ),
                          if (googleSignInAvailable) ...[
                            const SizedBox(height: 18),
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
                            const SizedBox(height: 18),
                            OutlinedButton.icon(
                              onPressed: busy ? null : _google,
                              icon: _googleBusy ? const _Spinner() : Image.asset('assets/brand/google_g.png', width: 18, height: 18, semanticLabel: 'Google'),
                              label: const Text('Continue with Google'),
                            ),
                          ],
                          const SizedBox(height: Space.lg),
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
                          if (Env.devLogin) const DevLoginButtons(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5));
}

/// The focused field's outline in peacock, matching the chosen tab.
Widget _peacockFocus(BuildContext context, Widget field) {
  final theme = Theme.of(context);
  final input = theme.inputDecorationTheme;
  return Theme(
    data: theme.copyWith(
      inputDecorationTheme: input.copyWith(
        focusedBorder: input.focusedBorder?.copyWith(borderSide: const BorderSide(color: BrandColors.peacock, width: 2)),
      ),
      textSelectionTheme: theme.textSelectionTheme.copyWith(cursorColor: BrandColors.peacock),
    ),
    child: field,
  );
}

/// What signing up gets you, from the shop's settings: the friend's-code welcome, free delivery, repairs. Each hides
/// when its value isn't there; all of them while the settings load.
class _Benefits extends ConsumerWidget {
  const _Benefits();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(storeSettingsProvider).value;
    if (s == null) return const SizedBox.shrink();
    final chips = [
      if (s.referralEnabled && s.referralFriendPaise > 0)
        (PhosphorIconsFill.gift, '${formatInr(s.referralFriendPaise)} off your first order with a friend’s code',
            BrandColors.mint, BrandColors.mintInk),
      if (s.deliveryFeePaise == 0 || s.freeDeliveryMinPaise == 0)
        (PhosphorIconsFill.truck, 'Free delivery on every order', BrandColors.cream, BrandColors.creamInk)
      else
        (PhosphorIconsFill.truck, 'Free delivery from ${formatInr(s.freeDeliveryMinPaise)}', BrandColors.cream,
            BrandColors.creamInk),
      (PhosphorIconsFill.wrench, 'Phone repairs at our shop', tileTints[3].$1, tileTints[3].$2),
    ];
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final (i, (icon, text, bg, fg)) in chips.indexed)
            DecoratedBox(
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.sm)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: fg),
                    const SizedBox(width: 6),
                    Flexible(child: Text(text, style: t.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700))),
                  ],
                ),
              ),
            ).enter(context, index: i),
        ],
      ),
    );
  }
}
