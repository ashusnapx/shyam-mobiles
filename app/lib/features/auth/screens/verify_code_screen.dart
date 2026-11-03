import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/auth_errors.dart';
import '../data/auth_repository.dart';
import '../widgets/otp_field.dart';

/// Matches `max_frequency` for SMS in supabase/config.toml (and the 60 s in docs/FIREBASE.md §4); asking sooner is
/// refused.
const resendAfterSeconds = 60;

/// The code step: the number with Change beside it, six boxes that fill from the SMS and check themselves on the
/// sixth digit, and a resend countdown.
class VerifyCodeScreen extends ConsumerStatefulWidget {
  const VerifyCodeScreen({super.key, this.phone, this.request, this.from});

  final String? phone; // E.164, from the link
  final PhoneCodeRequest? request; // the sign-in screen's request; Firebase needs its verification id
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
  ({String message, bool badCode})? _error;
  late PhoneCodeRequest? _request = widget.request ?? switch (widget.phone) { final p? => PhoneCodeRequest(phone: p), _ => null };

  AuthRepository get _auth => ref.read(authRepositoryProvider);

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
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _verify(String code) async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await _auth.verifyPhoneCode(_request!, code);
      // Signed in: the sign-in screen below leaves for `from`, or the name step first.
    } catch (e) {
      if (!mounted) return;
      final error = authError(e);
      setState(() {
        _verifying = false;
        _error = error;
      });
      if (!error.badCode) return; // offline or too many tries: the code stays for Try again
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
      _request = await _auth.requestPhoneCode(_request!.phone, resend: _request);
      if (mounted) showMessage(context, 'New code sent.');
    } catch (e) {
      if (!mounted) return;
      _timer?.cancel();
      setState(() => _secondsLeft = 0);
      showMessage(context, authError(e).message);
    }
  }

  void _back() {
    if (context.canPop()) return context.pop();
    final from = widget.from;
    context.go(from == null ? '/sign-in' : Uri(path: '/sign-in', queryParameters: {'from': from}).toString());
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final quiet = t.bodyMedium?.copyWith(color: c.onSurfaceVariant);
    const tabular = [FontFeature.tabularFigures()];
    final back = IconButton(tooltip: 'Back', icon: const Icon(PhosphorIconsRegular.arrowLeft), onPressed: _back);

    final request = _request;
    if (request == null) {
      return Scaffold(
        appBar: AppBar(leading: back),
        body: EmptyState(
          icon: PhosphorIconsRegular.signIn,
          title: 'Start again',
          message: 'Enter your mobile number to get a code.',
          action: FilledButton(onPressed: _back, child: const Text('Back to sign in')),
        ),
      );
    }

    final error = _error;
    final mm = _secondsLeft ~/ 60, ss = (_secondsLeft % 60).toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(leading: back),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            Space.gutter, Space.sm, Space.gutter, Space.xl + MediaQuery.paddingOf(context).bottom),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text('Enter the code', style: t.displaySmall)),
              const SizedBox(height: Space.sm),
              Text('We sent a 6-digit code by SMS to', style: quiet),
              Row(
                children: [
                  Flexible(child: Text(displayPhone(request.phone), style: t.titleMedium?.copyWith(fontFeatures: tabular))),
                  const SizedBox(width: Space.xs),
                  TextButton(onPressed: _back, child: const Text('Change', semanticsLabel: 'Change number')),
                ],
              ),
            ],
          ).enter(context),
          const SizedBox(height: Space.md),
          OtpField(
            controller: _code,
            focusNode: _focus,
            enabled: !_verifying,
            hasError: error?.badCode ?? false,
            onCompleted: _verify,
          ).enter(context, index: 1),
          const SizedBox(height: Space.md),
          if (_verifying)
            Row(
              spacing: Space.sm,
              children: [
                const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                Text('Checking…', style: t.bodyMedium),
              ],
            )
          else if (error != null) ...[
            Semantics(
              liveRegion: true,
              // red only for a refused code; no signal is not something the customer did wrong
              child: Text(error.message, style: t.bodyMedium?.copyWith(color: error.badCode ? c.error : c.onSurface)),
            ),
            if (!error.badCode && _code.text.length == otpLength)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => _verify(_code.text),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Text('Try again'),
                ),
              ),
          ],
          const SizedBox(height: Space.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _secondsLeft > 0
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.md),
                    child: Text('Resend code in $mm:$ss', style: quiet?.copyWith(fontFeatures: tabular)),
                  )
                : TextButton.icon(
                    onPressed: _verifying ? null : _resend,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    icon: const Icon(PhosphorIconsRegular.arrowClockwise, size: 18),
                    label: const Text('Resend code'),
                  ),
          ),
        ],
      ),
    );
  }
}
