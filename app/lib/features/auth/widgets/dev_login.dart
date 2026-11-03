import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/env.dart';
import '../../../core/errors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/auth_repository.dart';

/// Dev and client-demo builds only (Env.devLogin): a quiet link at the foot of sign-in that opens a sheet with one tap
/// into the test customer or staff account. The demo build words it for the client ("Try the demo"), dev builds keep
/// the dev label. After sign-in the sign-in screen leaves, exactly as it does after a code.
class DevLoginButtons extends StatelessWidget {
  const DevLoginButtons({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => const _DevLoginSheet(),
          ),
          child: const Text(Env.demoBuild ? 'Try the demo' : 'Use a test account'),
        ),
      );
}

class _DevLoginSheet extends ConsumerStatefulWidget {
  const _DevLoginSheet();

  @override
  ConsumerState<_DevLoginSheet> createState() => _DevLoginSheetState();
}

class _DevLoginSheetState extends ConsumerState<_DevLoginSheet> {
  String? _busy;

  Future<void> _signIn(String who, String email, String password) async {
    setState(() => _busy = who);
    try {
      await ref.read(authRepositoryProvider).signInForDev(email, password);
      if (mounted) Navigator.pop(context); // unless the sign-in screen's leaving took the sheet with it
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _button(String who, IconData icon, String label, String email, String password) => OutlinedButton.icon(
        onPressed: _busy != null || email.isEmpty ? null : () => _signIn(who, email, password),
        icon: _busy == who ? const ButtonSpinner() : Icon(icon, size: 18),
        label: Text(label),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: Tag(Env.demoBuild ? 'TRY THE DEMO' : 'DEV BUILD · TEST ACCOUNTS', tone: TagTone.deal)),
              const SizedBox(height: Space.lg),
              _button('customer', PhosphorIconsRegular.user, Env.demoBuild ? 'Shop as a customer' : 'Continue as test customer',
                  Env.devCustomerEmail, Env.devCustomerPassword),
              const SizedBox(height: Space.sm),
              _button('admin', PhosphorIconsRegular.storefront, Env.demoBuild ? 'Run the shop (owner)' : 'Continue as test admin',
                  Env.devAdminEmail, Env.devAdminPassword),
            ],
          ),
        ),
      );
}
