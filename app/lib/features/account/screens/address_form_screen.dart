import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' show Geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/picker.dart';
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

const _labelIcons = {
  AddressLabel.home: PhosphorIconsRegular.house,
  AddressLabel.work: PhosphorIconsRegular.briefcase,
  AddressLabel.other: PhosphorIconsRegular.mapPin,
};

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
  late final _phone = TextEditingController(text: localPhone(_a?.phone ?? ref.read(currentUserProvider)?.phone));
  late final _pincode = TextEditingController(text: _a?.pincode);
  late final _line1 = TextEditingController(text: _a?.line1);
  late final _line2 = TextEditingController(text: _a?.line2);
  late final _landmark = TextEditingController(text: _a?.landmark);
  late final _city = TextEditingController(text: _a?.city);
  late final _district = TextEditingController(text: _a?.district);
  late String? _state = _a?.state;
  late AddressLabel _label = _a?.label ?? AddressLabel.home;
  late bool _isDefault = widget.forceDefault || (_a?.isDefault ?? false);

  /// Last value we filled in per field (controller, or 'state'), so a later lookup may replace our own guess
  /// but never what the user typed.
  final _auto = <Object, String>{};

  Timer? _pinDebounce;
  int _pinSeq = 0; // bumped on every pincode edit; a lookup that finishes under an older number is dropped
  bool _lookingUp = false;
  PincodePlace? _place;
  String? _pinNote;
  bool _allAreas = false;

  bool _locating = false;
  String? _locNote;
  (String, Future<bool> Function())? _locFix; // button label and the settings screen it opens

  bool _saving = false;

  @override
  void dispose() {
    _pinDebounce?.cancel();
    for (final c in [_name, _phone, _pincode, _line1, _line2, _landmark, _city, _district]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Puts [value] in [c] if the field is empty or still holds our earlier guess. Returns whether it did.
  bool _fill(TextEditingController c, String? value) {
    if (value == null || value.isEmpty) return false;
    if (c.text.trim().isNotEmpty && c.text != _auto[c]) return false;
    c.text = _auto[c] = value;
    return true;
  }

  bool _fillState(String? value) {
    if (value == null || (_state != null && _state != _auto['state'])) return false;
    _state = _auto['state'] = value;
    return true;
  }

  void _onPincode(String pin) {
    _pinDebounce?.cancel();
    final seq = ++_pinSeq;
    setState(() {
      _lookingUp = false;
      _place = null;
      _pinNote = null;
      _allAreas = false;
    });
    if (validatePincode(pin) != null) return;
    _pinDebounce = Timer(const Duration(milliseconds: 350), () => _lookUp(pin, seq));
  }

  Future<void> _lookUp(String pin, int seq) async {
    setState(() => _lookingUp = true);
    PincodePlace? place;
    String? note;
    try {
      place = await ref.read(pincodeLookupProvider)(pin);
      if (place == null) note = 'No post office has this pincode. Check it, or fill in the rest yourself.';
    } catch (_) {
      note = "Couldn't check the pincode just now. You can fill in the rest yourself.";
    }
    if (!mounted || seq != _pinSeq) return;
    setState(() {
      _lookingUp = false;
      _place = place;
      _pinNote = note;
      if (place == null) return;
      _fill(_district, place.district);
      _fill(_city, place.district); // India Post has no city; the district is the best first guess
      if (place.state case final s?) _state = _auto['state'] = s; // a pincode belongs to exactly one state
    });
  }

  Future<void> _useLocation() async {
    setState(() {
      _locating = true;
      _locNote = null;
      _locFix = null;
    });
    String? note;
    (String, Future<bool> Function())? fix;
    AddressGuess? guess;
    var precise = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        note = 'Location is turned off on this phone.';
        fix = ('Turn on location', Geolocator.openLocationSettings);
      } else {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.deniedForever) {
          note = 'Location access is off for Shyam Mobiles. Allow it in Settings, or type your address below.';
          fix = ('Open settings', Geolocator.openAppSettings);
        } else if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
          note = 'No problem. Type your address below.';
        } else {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 10)),
          );
          precise = await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.precise;
          // English names so the state matches our list. The timeout guards a geocoder that never answers.
          final marks = await Geocoding(locale: const Locale('en', 'IN'))
              .placemarkFromCoordinates(pos.latitude, pos.longitude)
              .timeout(const Duration(seconds: 10));
          final mark = marks.firstOrNull;
          if (mark == null) {
            note = "Couldn't find an address here. Type it below.";
          } else if (mark.isoCountryCode != null && mark.isoCountryCode != 'IN') {
            note = 'We deliver within India only. Type an Indian address below.';
          } else {
            guess = addressFromPlacemark(mark);
          }
        }
      }
    } on TimeoutException {
      note = "Couldn't get your location in time. Try again, or type your address below.";
    } catch (_) {
      note = "Couldn't get your location. Try again, or type your address below.";
    }
    if (!mounted) return;
    if (guess != null) note = _applyGuess(guess, precise: precise);
    setState(() {
      _locating = false;
      _locNote = note;
      _locFix = fix;
    });
  }

  /// Fills only empty fields (or our own earlier guesses) and says which ones it filled.
  String _applyGuess(AddressGuess g, {required bool precise}) {
    final pinBefore = _pincode.text;
    final filled = [
      // An approximate fix is off by a kilometre or more: the house and area would be someone else's.
      if (precise && _fill(_line1, g.line1)) 'house and street',
      if (precise && _fill(_line2, g.area)) 'area',
      if (_fill(_city, g.city)) 'city',
      if (_fill(_district, g.district)) 'district',
      if (_fillState(g.state)) 'state',
      if (_fill(_pincode, g.pincode)) 'pincode',
    ];
    if (_pincode.text != pinBefore) _onPincode(_pincode.text);
    if (filled.isEmpty) return 'Your location matches what you have typed. Nothing was changed.';
    final list = filled.length == 1
        ? filled.first
        : '${filled.sublist(0, filled.length - 1).join(', ')} and ${filled.last}';
    return 'Filled $list from your location. Please check before saving.'
        '${precise ? '' : ' Your location is approximate, so add your house and area yourself.'}';
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    String? opt(TextEditingController c) => tidy(c.text).isEmpty ? null : tidy(c.text);
    setState(() => _saving = true);
    try {
      final saved = await ref.read(addressesProvider.notifier).save(Address(
            id: _a?.id,
            name: tidy(_name.text),
            phone: normalizeIndianPhone(_phone.text)!,
            line1: tidy(_line1.text),
            line2: opt(_line2),
            landmark: opt(_landmark),
            city: tidy(_city.text),
            district: opt(_district),
            state: _state!,
            pincode: _pincode.text.trim(),
            label: _label,
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
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    const gap = SizedBox(height: Space.lg);
    final states = [...indianStates, if (_state != null && !indianStates.contains(_state)) _state!];
    final place = _place;
    final areas = place?.areas ?? const <String>[];
    final shownAreas = _allAreas || areas.length <= 8 ? areas : areas.take(6).toList();
    return Column(
      children: [
        Expanded(
          child: Form(
            key: _form,
            child: AutofillGroup(
              // not a ListView: a lazy list drops fields scrolled far away, and Form.validate() would skip them
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _locating ? null : _useLocation,
                        icon: _locating
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(PhosphorIconsRegular.crosshair),
                        label: Text(_locating ? 'Finding your location…' : 'Use my current location'),
                      ),
                    ),
                    if (_locNote != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.sm),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(_locNote!, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        ),
                      ),
                    if (_locFix case (final label, final open))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(onPressed: open, child: Text(label)),
                      ),
                    gap,
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      inputFormatters: textInput(MaxLen.name),
                      textInputAction: TextInputAction.next,
                      validator: validateName,
                    ),
                    gap,
                    TextFormField(
                      controller: _phone,
                      decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 ', hintText: '98765 43210'),
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumberNational],
                      inputFormatters: const [IndianMobileFormatter()],
                      textInputAction: TextInputAction.next,
                      validator: validatePhone,
                    ),
                    gap,
                    TextFormField(
                      controller: _pincode,
                      decoration: InputDecoration(
                        labelText: 'Pincode',
                        helperText: _lookingUp
                            ? 'Checking pincode…'
                            : place != null
                                ? [place.district, ?place.state].join(' · ')
                                : _pinNote,
                        helperMaxLines: 3,
                        suffixIcon: _lookingUp
                            ? const Padding(
                                padding: EdgeInsets.all(Space.md),
                                child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : place != null
                                ? const Icon(PhosphorIconsRegular.checkCircle, semanticLabel: 'Pincode found')
                                : null,
                      ),
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.postalCode],
                      inputFormatters: const [DigitsFormatter(6)],
                      textInputAction: TextInputAction.next,
                      onChanged: _onPincode,
                      validator: validatePincode,
                    ),
                    if (areas.isNotEmpty) ...[
                      const SizedBox(height: Space.md),
                      Text('Tap your area', style: t.labelLarge),
                      const SizedBox(height: Space.xs),
                      ListenableBuilder(
                        listenable: _line2,
                        builder: (context, _) => Wrap(
                          spacing: Space.sm,
                          children: [
                            for (final a in shownAreas)
                              ChoiceChip(
                                label: Text(a),
                                selected: _line2.text.trim() == a,
                                onSelected: (_) => _line2.text = a,
                              ),
                            if (shownAreas.length < areas.length)
                              ActionChip(
                                label: Text('${areas.length - shownAreas.length} more'),
                                onPressed: () => setState(() => _allAreas = true),
                              ),
                          ],
                        ),
                      ),
                    ],
                    gap,
                    TextFormField(
                      controller: _line1,
                      decoration: const InputDecoration(labelText: 'House no., flat, building'),
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.streetAddressLine1],
                      inputFormatters: textInput(MaxLen.addressLine),
                      textInputAction: TextInputAction.next,
                      validator: validateLine1,
                    ),
                    gap,
                    TextFormField(
                      controller: _line2,
                      decoration: const InputDecoration(labelText: 'Area, street, locality (optional)'),
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.streetAddressLine2],
                      inputFormatters: textInput(MaxLen.addressLine),
                      textInputAction: TextInputAction.next,
                      validator: validateLine2,
                    ),
                    gap,
                    TextFormField(
                      controller: _landmark,
                      decoration: const InputDecoration(labelText: 'Landmark (optional)', hintText: 'Near Shiv Mandir'),
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: textInput(MaxLen.landmark),
                      textInputAction: TextInputAction.next,
                      validator: validateLandmark,
                    ),
                    gap,
                    TextFormField(
                      controller: _city,
                      decoration: const InputDecoration(labelText: 'City, town or village'),
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.addressCity],
                      inputFormatters: textInput(MaxLen.place),
                      textInputAction: TextInputAction.next,
                      validator: validateCity,
                    ),
                    gap,
                    TextFormField(
                      controller: _district,
                      decoration: const InputDecoration(labelText: 'District (optional)'),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: textInput(MaxLen.place),
                      textInputAction: TextInputAction.done,
                      validator: validateDistrict,
                    ),
                    gap,
                    PickerField<String>(
                      // keyed by the value so a pincode or location autofill shows up in the field
                      key: ValueKey('state-$_state'),
                      label: 'State',
                      options: states,
                      labelOf: (s) => s,
                      initialValue: _state,
                      onChanged: (v) => setState(() => _state = v),
                      validator: validateState,
                      searchHint: 'Search states',
                    ),
                    gap,
                    Semantics(header: true, child: Text('Save address as', style: t.labelLarge)),
                    const SizedBox(height: Space.xs),
                    Wrap(
                      spacing: Space.sm,
                      children: [
                        for (final l in AddressLabel.values)
                          ChoiceChip(
                            showCheckmark: false,
                            avatar: Icon(_labelIcons[l], size: 18, color: l == _label ? c.onPrimary : c.onSurface),
                            label: Text(l.displayName),
                            selected: l == _label,
                            onSelected: (_) => setState(() => _label = l),
                          ),
                      ],
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
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.outlineVariant)),
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
