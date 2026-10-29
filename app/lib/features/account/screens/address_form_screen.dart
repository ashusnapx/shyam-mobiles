import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/address_form.dart';
import '../data/addresses.dart';
import '../data/profile.dart';

/// Add (/account/addresses/new) or edit (/account/addresses/:id). Pops with the saved [Address].
class AddressFormScreen extends ConsumerWidget {
  const AddressFormScreen({super.key, this.addressId});

  final String? addressId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(addressId == null ? 'New address' : 'Edit address')),
      body: AsyncBody(
        value: addresses,
        onRetry: () => ref.invalidate(addressesProvider),
        loading: const Center(child: CircularProgressIndicator()),
        data: (list) {
          final existing = list.where((a) => a.id == addressId).firstOrNull;
          if (addressId != null && existing == null) {
            return EmptyState(
              icon: PhosphorIconsRegular.mapPin,
              title: 'Address not found',
              message: 'It may have been deleted.',
              action: OutlinedButton(onPressed: () => context.pop(), child: const Text('Go back')),
            );
          }
          return _AddressForm(existing: existing, forceDefault: list.isEmpty || (existing?.isDefault ?? false));
        },
      ),
    );
  }
}

class _AddressForm extends ConsumerStatefulWidget {
  const _AddressForm({required this.existing, required this.forceDefault});

  final Address? existing;
  final bool forceDefault;

  @override
  ConsumerState<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends ConsumerState<_AddressForm> {
  final _form = GlobalKey<FormState>();
  late final Address? _a = widget.existing;
  late final _name = TextEditingController(text: _a?.name ?? ref.read(profileProvider).value?.fullName);
  late final _phone = TextEditingController(text: _localPhone(_a?.phone ?? ref.read(currentUserProvider)?.phone));
  late final _pincode = TextEditingController(text: _a?.pincode);
  late final _city = TextEditingController(text: _a?.city);
  late final _line1 = TextEditingController(text: _a?.line1);
  late final _line2 = TextEditingController(text: _a?.line2);
  late final _landmark = TextEditingController(text: _a?.landmark);
  late String? _state = _a?.state;
  late bool _isDefault = widget.forceDefault || (_a?.isDefault ?? false);
  String? _autoCity; // last city we filled in, so a new pincode may replace it but never the user's own typing
  bool _lookingUp = false;
  bool _saving = false;

  /// "+919876543210" or "919876543210" → "98765 43210".
  static String? _localPhone(String? raw) {
    final p = normalizeIndianPhone(raw ?? '');
    return p == null ? null : '${p.substring(3, 8)} ${p.substring(8)}';
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _pincode, _city, _line1, _line2, _landmark]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _onPincode(String pin) async {
    if (validatePincode(pin) != null) return;
    setState(() => _lookingUp = true);
    final place = await lookupPincode(pin);
    if (!mounted) return;
    setState(() {
      _lookingUp = false;
      if (place == null || _pincode.text != pin) return;
      if (_city.text.trim().isEmpty || _city.text == _autoCity) _city.text = _autoCity = place.city;
      _state = place.state ?? _state;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    setState(() => _saving = true);
    try {
      final saved = await ref.read(addressesProvider.notifier).save(Address(
            id: _a?.id,
            name: _name.text.trim(),
            phone: normalizeIndianPhone(_phone.text)!,
            line1: _line1.text.trim(),
            line2: opt(_line2),
            landmark: opt(_landmark),
            city: _city.text.trim(),
            state: _state!,
            pincode: _pincode.text.trim(),
            isDefault: _isDefault,
          ));
      if (mounted) context.pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: Space.lg);
    final states = [...indianStates, if (_state != null && !indianStates.contains(_state)) _state!];
    return Column(
      children: [
        Expanded(
          child: Form(
            key: _form,
            child: AutofillGroup(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    textInputAction: TextInputAction.next,
                    validator: validateName,
                  ),
                  gap,
                  TextFormField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 '),
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumberNational],
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d ]')), LengthLimitingTextInputFormatter(14)],
                    textInputAction: TextInputAction.next,
                    validator: validatePhone,
                  ),
                  gap,
                  TextFormField(
                    controller: _pincode,
                    decoration: InputDecoration(
                      labelText: 'Pincode',
                      suffixIcon: _lookingUp
                          ? const Padding(
                              padding: EdgeInsets.all(Space.md),
                              child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : null,
                    ),
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.postalCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    textInputAction: TextInputAction.next,
                    onChanged: _onPincode,
                    validator: validatePincode,
                  ),
                  gap,
                  TextFormField(
                    controller: _city,
                    decoration: const InputDecoration(labelText: 'City or district'),
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.addressCity],
                    textInputAction: TextInputAction.next,
                    validator: validateCity,
                  ),
                  gap,
                  DropdownButtonFormField<String>(
                    initialValue: _state,
                    isExpanded: true,
                    icon: const Icon(PhosphorIconsRegular.caretDown, size: 18),
                    decoration: const InputDecoration(labelText: 'State'),
                    items: [for (final s in states) DropdownMenuItem(value: s, child: Text(s))],
                    onChanged: (v) => setState(() => _state = v),
                    validator: validateState,
                  ),
                  gap,
                  TextFormField(
                    controller: _line1,
                    decoration: const InputDecoration(labelText: 'House, building, street'),
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.streetAddressLine1],
                    textInputAction: TextInputAction.next,
                    validator: validateLine1,
                  ),
                  gap,
                  TextFormField(
                    controller: _line2,
                    decoration: const InputDecoration(labelText: 'Area or colony (optional)'),
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.streetAddressLine2],
                    textInputAction: TextInputAction.next,
                    validator: validateLine2,
                  ),
                  gap,
                  TextFormField(
                    controller: _landmark,
                    decoration: const InputDecoration(labelText: 'Landmark (optional)'),
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    validator: validateLandmark,
                  ),
                  const SizedBox(height: Space.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use as default address'),
                    subtitle: widget.forceDefault
                        ? Text(widget.existing == null
                            ? 'Your first address is the default.'
                            : 'To change this, set another address as default.')
                        : null,
                    value: _isDefault,
                    onChanged: widget.forceDefault ? null : (v) => setState(() => _isDefault = v),
                  ),
                ],
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.all(Space.lg),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Save address'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
