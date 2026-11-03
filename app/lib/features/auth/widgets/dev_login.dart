import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/env.dart';
import '../../../core/errors.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';

/// Dev and client-demo builds only (Env.devLogin): one tap into the test customer or staff account. The demo build
/// words it for the client ("Try the demo"), dev builds keep the dev label.
/// After sign-in the router's redirect takes over, exactly as it does after an OTP.
class DevLoginButtons extends ConsumerStatefulWidget {
  const DevLoginButtons({super.key});

  @override
  ConsumerState<DevLoginButtons> createState() => _DevLoginButtonsState();
}

class _DevLoginButtonsState extends ConsumerState<DevLoginButtons> {
  String? _busy;

  Future<void> _signIn(String who, String email, String password) async {
    setState(() => _busy = who);
    try {
      await ref.read(supabaseProvider).auth.signInWithPassword(email: email, password: password);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _button(String who, IconData icon, String label, String email, String password) => OutlinedButton.icon(
        onPressed: _busy != null || email.isEmpty ? null : () => _signIn(who, email, password),
        icon: _busy == who
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 18),
        label: Text(label),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: Tag(Env.demoBuild ? 'TRY THE DEMO' : 'DEV BUILD · TEST ACCOUNTS', tone: TagTone.deal)),
            const SizedBox(height: Space.md),
            _button('customer', PhosphorIconsRegular.user, Env.demoBuild ? 'Shop as a customer' : 'Continue as test customer', Env.devCustomerEmail,
                Env.devCustomerPassword),
            const SizedBox(height: Space.sm),
            _button('admin', PhosphorIconsRegular.storefront, Env.demoBuild ? 'Run the shop (owner)' : 'Continue as test admin', Env.devAdminEmail,
                Env.devAdminPassword),
          ],
        ),
      );
}
