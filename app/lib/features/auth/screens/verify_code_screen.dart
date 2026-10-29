import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../widgets/otp_field.dart';

/// Matches `max_frequency` for SMS and email in supabase/config.toml; asking sooner is rejected.
const resendAfterSeconds = 60;

/// When "Use email instead" / "Use phone instead" appears (SPEC v1 additions).
const switchMethodAfterSeconds = 30;

class VerifyCodeScreen extends ConsumerStatefulWidget {
  const VerifyCodeScreen({super.key, this.phone, this.email, this.from});

  final String? phone;
  final String? email;
  final String? from;

  @override
  ConsumerState<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends ConsumerState<VerifyCodeScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _secondsLeft = resendAfterSeconds;
  bool _verifying = false;
  bool _offerSwitch = false;
  String? _error;

  GoTrueClient get _auth => ref.read(supabaseProvider).auth;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    _secondsLeft = resendAfterSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) t.cancel();
      setState(() {
        _secondsLeft--;
        if (resendAfterSeconds - _secondsLeft >= switchMethodAfterSeconds) _offerSwitch = true;
      });
    });
  }

  Future<void> _verify(String code) async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      widget.phone != null
          ? await _auth.verifyOTP(phone: widget.phone, token: code, type: OtpType.sms)
          : await _auth.verifyOTP(email: widget.email, token: code, type: OtpType.email);
      // Success: the router sees the new session and redirects to `from`.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = friendlyError(e);
      });
      _code.clear();
      // The field is re-enabled on the next frame; focus it then so the keyboard comes back.
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  Future<void> _resend() async {
    setState(() {
      _error = null;
      _startCountdown();
    });
    try {
      widget.phone != null
          ? await _auth.signInWithOtp(phone: widget.phone)
          : await _auth.signInWithOtp(email: widget.email, shouldCreateUser: true);
      if (mounted) showMessage(context, 'New code sent.');
    } catch (e) {
      if (!mounted) return;
      _timer?.cancel();
      setState(() => _secondsLeft = 0);
      showMessage(context, friendlyError(e));
    }
  }

  /// Back to sign-in; [method] ('phone' | 'email') tells it which tab to open.
  void _back([String? method]) {
    if (context.canPop()) return context.pop(method);
    context.go(Uri(path: '/sign-in', queryParameters: {if (widget.from != null) 'from': widget.from}).toString());
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final target = widget.phone != null ? displayPhone(widget.phone!) : widget.email;

    if (target == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: PhosphorIconsRegular.signIn,
          title: 'Start again',
          message: 'Enter your phone number or email to get a code.',
          action: FilledButton(onPressed: _back, child: const Text('Back to sign in')),
        ),
      );
    }

    final mm = _secondsLeft ~/ 60, ss = (_secondsLeft % 60).toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.xl + MediaQuery.paddingOf(context).bottom),
        children: [
          Semantics(header: true, child: Text('Enter the code', style: t.displaySmall)),
          const SizedBox(height: Space.sm),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'We sent a 6-digit code to '),
              TextSpan(text: target, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _back,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(widget.phone != null ? 'Change number' : 'Change email'),
            ),
          ),
          const SizedBox(height: Space.lg),
          OtpField(
            controller: _code,
            focusNode: _focus,
            enabled: !_verifying,
            hasError: _error != null,
            onCompleted: _verify,
          ),
          const SizedBox(height: Space.md),
          if (_verifying)
            Row(
              spacing: Space.sm,
              children: [
                const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                Text('Checking…', style: t.bodyMedium),
              ],
            )
          else if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.error)),
            ),
          const SizedBox(height: Space.lg),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _secondsLeft > 0
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.md),
                    child: Text(
                      'Resend code in $mm:$ss',
                      style: t.bodyMedium?.copyWith(
                        color: c.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  )
                : TextButton.icon(
                    onPressed: _verifying ? null : _resend,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    icon: const Icon(PhosphorIconsRegular.arrowClockwise, size: 18),
                    label: const Text('Resend code'),
                  ),
          ),
          if (_offerSwitch)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => _back(widget.phone != null ? 'email' : 'phone'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text('Didn’t get it? Use ${widget.phone != null ? 'email' : 'phone'} instead'),
              ),
            ),
        ],
      ),
    );
  }
}
