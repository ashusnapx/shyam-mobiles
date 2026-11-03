import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/errors.dart';
import '../../../core/input.dart';
import '../../../core/router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../account/data/profile.dart';

/// Where a fresh sign-in goes: a phone sign-in first stops at /welcome, which asks a new customer's name (Google gives
/// it); everyone else goes straight back to [from].
String afterSignInPath(String? from, {required bool byPhone}) {
  final back = safeReturnPath(from);
  if (!byPhone) return back ?? '/';
  return back == null ? '/welcome' : Uri(path: '/welcome', queryParameters: {'from': back}).toString();
}

/// "What should we call you?": once, after a first phone sign-up, never skipped. A customer who already has a name
/// passes straight through to [from].
class NameScreen extends ConsumerStatefulWidget {
  const NameScreen({super.key, this.from});

  final String? from;

  @override
  ConsumerState<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends ConsumerState<NameScreen> {
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // named already, or just saved: on to `from` (after this frame: no navigating while building)
    ref.listenManual(profileProvider, fireImmediately: true, (_, p) {
      if (tidy(p.value?.fullName).isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(safeReturnPath(widget.from) ?? '/');
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await saveFullName(ref, displayName(_name.text)); // the listener then leaves
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), action: SnackBarAction(label: 'Try again', onPressed: _save));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider);
    const waiting = Center(child: BrandMark(size: 52));
    final body = switch (profile) {
      _ when tidy(profile.value?.fullName).isNotEmpty => waiting,
      AsyncValue(hasValue: true) => Form(
          key: _form,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                Space.gutter, Space.sm, Space.gutter, Space.xl + MediaQuery.paddingOf(context).bottom),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text('What should we call you?', style: t.displaySmall)),
                  const SizedBox(height: Space.sm),
                  Text('We’ll put it on your orders and repair bookings.',
                      style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                ],
              ).enter(context),
              const SizedBox(height: Space.xl),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    inputFormatters: textInput(MaxLen.name),
                    decoration: const InputDecoration(labelText: 'Your name', hintText: 'Ravi Kumar'),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    validator: validatePersonName,
                  ),
                  const SizedBox(height: Space.lg),
                  FilledButton(
                    onPressed: _save,
                    child: _saving ? const ButtonSpinner() : const Text('Continue'),
                  ),
                ],
              ).enter(context, index: 1),
            ],
          ),
        ),
      AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(profileProvider)),
      _ => waiting,
    };
    // never skipped: Back does nothing here (the account exists; only the name is missing)
    return PopScope(
      canPop: false,
      child: Scaffold(appBar: AppBar(automaticallyImplyLeading: false), body: body),
    );
  }
}
