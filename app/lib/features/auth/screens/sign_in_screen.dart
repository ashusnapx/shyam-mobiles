import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/env.dart';
import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/router.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/google.dart';
import '../widgets/dev_login.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

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
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_sending) return;
    final phone = normalizeIndianPhone(_phone.text);
    final email = _email.text.trim().toLowerCase();
    if (_usePhone ? phone == null : !_emailPattern.hasMatch(email)) {
      setState(() => _error = _usePhone ? 'Enter a 10-digit mobile number.' : 'Enter a valid email address.');
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
      context.push<String>(Uri(path: '/sign-in/verify', queryParameters: {
        if (_usePhone) 'phone': phone else 'email': email,
        if (widget.from != null) 'from': widget.from,
      }).toString()).then((method) {
        if (mounted && method != null) _tabs.animateTo(method == 'email' ? 1 : 0);
      });
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _google() async {
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

    final field = _usePhone
        ? TextField(
            key: const ValueKey('phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendCode(),
            // Spaces allowed so a pasted "+91 98765 43210" survives; normalizeIndianPhone strips the 91.
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d ]')), LengthLimitingTextInputFormatter(14)],
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
            _Hero(compact: compact, onClose: () => context.canPop() ? context.pop() : context.go('/')),
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
                                indicator: BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(Radii.sm + 2),
                                  boxShadow: [
                                    BoxShadow(color: c.shadow.withValues(alpha: 0.12), blurRadius: 3, offset: const Offset(0, 1)),
                                  ],
                                ),
                                labelColor: c.onSurface,
                                unselectedLabelColor: c.onSurfaceVariant,
                                labelStyle: t.titleSmall,
                                tabs: const [Tab(height: 44, text: 'Phone'), Tab(height: 44, text: 'Email')],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          ExcludeSemantics(child: Text(_usePhone ? 'Mobile number' : 'Email', style: label)),
                          const SizedBox(height: Space.sm),
                          Semantics(label: _usePhone ? 'Mobile number' : 'Email', child: field),
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
                              icon: _googleBusy ? const _Spinner() : const Icon(PhosphorIconsBold.googleLogo, size: 18),
                              label: const Text('Continue with Google'),
                            ),
                          ],
                          const SizedBox(height: Space.lg),
                          Text(
                            'By continuing you agree to the Terms and Privacy Policy.',
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

/// Black hero with a soft white glow and ripple rings (mockup screen 8). Folds to a compact bar while typing.
class _Hero extends StatelessWidget {
  const _Hero({required this.compact, required this.onClose});

  final bool compact;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const onHero = Colors.white;
    final still = MediaQuery.disableAnimationsOf(context);
    final close = Transform.translate(
      offset: const Offset(-Space.md, 0),
      child: IconButton(
        tooltip: 'Close',
        onPressed: onClose,
        style: IconButton.styleFrom(backgroundColor: onHero.withValues(alpha: 0.14), foregroundColor: onHero),
        icon: const Icon(PhosphorIconsRegular.x, size: 20),
      ),
    );
    final full = Column(
      key: const ValueKey('full'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        close,
        const SizedBox(height: Space.lg),
        const BrandMark(size: 52, onDark: true),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: Text('Welcome to\nShyam Mobiles', style: t.displayLarge?.copyWith(color: onHero)),
        ),
        const SizedBox(height: 10),
        Text(
          'Sign in or create your account with a one-time code. No password to remember.',
          style: t.bodyMedium?.copyWith(color: onHero.withValues(alpha: 0.8)),
        ),
      ],
    );
    final bar = Row(
      key: const ValueKey('compact'),
      children: [
        close,
        const BrandMark(size: 28, onDark: true),
        const SizedBox(width: Space.md),
        Flexible(
          child: Semantics(
            header: true,
            child: Text('Shyam Mobiles', style: t.displaySmall?.copyWith(fontSize: 26, color: onHero)),
          ),
        ),
      ],
    );
    final duration = still ? Duration.zero : Motion.normal;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, BrandColors.graphite],
        ),
      ),
      child: CustomPaint(
        painter: const _RipplePainter(),
        child: AnimatedPadding(
          duration: duration,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(
            Space.xl,
            MediaQuery.paddingOf(context).top + Space.xs,
            Space.xl,
            (compact ? Space.md : Space.xxl) + 26, // + the sheet's overlap
          ),
          child: AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: AnimatedSwitcher(
              duration: still ? Duration.zero : Motion.fast,
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
              child: compact ? bar : full,
            ),
          ),
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  const _RipplePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height * 1.2);
    final glow = Rect.fromCircle(center: centre, radius: size.height * 0.75);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.18), Colors.white.withValues(alpha: 0)],
        ).createShader(glow),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.07);
    for (var r = 20.0; r < size.height * 1.3; r += 20) {
      canvas.drawOval(Rect.fromCenter(center: centre, width: r * 2.6, height: r * 2), ring);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => false;
}
