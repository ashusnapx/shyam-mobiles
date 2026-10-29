import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/profile.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: AsyncBody(
          value: ref.watch(profileProvider),
          onRetry: () => ref.invalidate(profileProvider),
          loading: const Skeletonizer(child: _ProfileForm(profile: null)),
          data: (p) => _ProfileForm(profile: p),
        ),
      );
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});

  final Profile? profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final _name = TextEditingController(text: widget.profile?.fullName);
  final _form = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await saveFullName(ref, _name.text);
      if (!mounted) return;
      showMessage(context, 'Saved.');
      context.pop();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final phone = accountPhone(user?.phone, widget.profile?.phone);
    final email = user?.email;
    return Form(
      key: _form,
      child: ListView(
        padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl + MediaQuery.paddingOf(context).bottom),
        children: [
          TextFormField(
            controller: _name,
            enabled: widget.profile != null,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            inputFormatters: textInput(MaxLen.name),
            decoration: const InputDecoration(labelText: 'Full name'),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _save(),
            // blank clears the name; otherwise the profiles check: a letter in any script, ≤80
            validator: (v) => checkText(v, max: MaxLen.name, mustHave: hasLetter),
          ),
          const SizedBox(height: Space.lg),
          if (phone != null) _ReadOnly(label: 'Mobile number', value: phone),
          if (email != null && email.isNotEmpty) _ReadOnly(label: 'Email', value: email),
          const SizedBox(height: Space.sm),
          Text(
            'You sign in with these, so they can’t be changed here.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: _saving || widget.profile == null ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ReadOnly extends StatelessWidget {
  const _ReadOnly({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, enabled: false),
          child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
}
