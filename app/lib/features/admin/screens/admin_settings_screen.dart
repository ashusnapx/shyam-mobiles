import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../catalog/widgets/store_links.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../data/admin.dart';
import '../data/photos.dart';
import '../data/rules.dart';
import '../widgets/admin_widgets.dart';

class AdminSettingsScreen extends ConsumerWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(storeSettingsProvider);
    return AdminGate(
      child: value.hasValue
          ? _Form(settings: value.value!)
          : Scaffold(
              appBar: AppBar(title: const Text('Store settings')),
              body: value.hasError
                  ? ErrorView(error: value.error!, onRetry: () => ref.invalidate(storeSettingsProvider))
                  : const Center(child: CircularProgressIndicator()),
            ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.settings});

  final StoreSettings settings;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _form = GlobalKey<FormState>();
  late final StoreSettings _s = widget.settings;
  late final _fee = TextEditingController(text: rupeesText(_s.deliveryFeePaise));
  late final _freeMin = TextEditingController(text: rupeesText(_s.freeDeliveryMinPaise));
  late final _codMax = TextEditingController(text: rupeesText(_s.codMaxPaise));
  late final _phone = TextEditingController(text: localPhone(_s.storePhone));
  late final _address = TextEditingController(text: _s.storeAddress);
  late final _pin = TextEditingController(text: _s.storeLat == null ? '' : '${_s.storeLat}, ${_s.storeLng}');
  late String? _mapsUrl = _s.storeMapsUrl;
  late final _hours = TextEditingController(text: _s.storeHours);
  late final _repairNote = TextEditingController(text: _s.repairNote);
  late final _returns = TextEditingController(text: _s.returnsPolicy);
  late bool _cod = _s.codEnabled;
  late bool _referral = _s.referralEnabled;
  late final _friend = TextEditingController(text: rupeesText(_s.referralFriendPaise));
  late final _reward = TextEditingController(text: rupeesText(_s.referralRewardPaise));
  late final _referralMin = TextEditingController(text: rupeesText(_s.referralMinOrderPaise));
  late final _referralCap = TextEditingController(text: '${_s.referralMonthlyCap}');
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_fee, _freeMin, _codMax, _phone, _address, _pin, _hours, _repairNote, _returns, _friend, _reward, _referralMin, _referralCap]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final pinText = tidy(_pin.text).replaceAll(' ', ''); // a link never has spaces; a wrapped paste may
    final pin = parseMapPin(pinText.isEmpty ? '' : tidy(_pin.text)); // null when empty: clears the pin
    // a pasted place link becomes the listing customers open; plain "lat, lng" keeps the old one
    if (isMapsPlaceLink(pinText)) _mapsUrl = pinText;
    setState(() => _busy = true);
    try {
      await saveSettings(
        ref,
        StoreSettings(
          deliveryFeePaise: parseRupees(_fee.text)!,
          freeDeliveryMinPaise: parseRupees(_freeMin.text)!,
          codEnabled: _cod,
          codMaxPaise: parseRupees(_codMax.text)!,
          storePhone: normalizeIndianPhone(_phone.text)!,
          storeAddress: tidy(_address.text, multiline: true),
          storeLat: pin?.lat,
          storeLng: pin?.lng,
          storeMapsUrl: _mapsUrl,
          storeHours: tidy(_hours.text),
          repairNote: tidy(_repairNote.text, multiline: true),
          returnsPolicy: tidy(_returns.text, multiline: true),
          referralEnabled: _referral,
          referralFriendPaise: parseRupees(_friend.text)!,
          referralRewardPaise: parseRupees(_reward.text)!,
          referralMinOrderPaise: parseRupees(_referralMin.text)!,
          referralMonthlyCap: int.parse(_referralCap.text),
        ),
      );
      if (mounted) showMessage(context, 'Settings saved');
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _feeError(String? v) => rupeesError(v, maxPaise: maxFeePaise);
  String? _limitError(String? v) => rupeesError(v, maxPaise: maxAmountPaise);
  // the friend's and the referrer's coupons are flat offers, which are at least ₹1
  String? _couponError(String? v) => rupeesError(v, minPaise: 100, maxPaise: maxFeePaise);

  Widget _gap() => const SizedBox(height: Space.md);

  @override
  Widget build(BuildContext context) {
    final pin = parseMapPin(_pin.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Store settings')),
      bottomNavigationBar: StickyBar(
        child: FilledButton(onPressed: _busy ? null : _save, child: const Text('Save settings')),
      ),
      body: Form(
        key: _form,
        // not a ListView: a lazy list drops fields scrolled far away, and Form.validate() would skip them
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ListSection('Delivery'),
              TextFormField(
                controller: _fee,
                decoration: const InputDecoration(labelText: 'Delivery fee', prefixText: '₹ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [RupeesFormatter(maxDigits: 5)],
                textInputAction: TextInputAction.next,
                validator: _feeError,
              ),
              _gap(),
              TextFormField(
                controller: _freeMin,
                decoration: const InputDecoration(
                  labelText: 'Free delivery from',
                  prefixText: '₹ ',
                  helperText: 'Orders at or above this pay no delivery fee. 0 makes delivery always free.',
                  helperMaxLines: 3,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [RupeesFormatter(maxDigits: 7)],
                textInputAction: TextInputAction.next,
                validator: _limitError,
              ),
              const ListSection('Cash on delivery'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Offer cash on delivery'),
                value: _cod,
                onChanged: (v) => setState(() => _cod = v),
              ),
              TextFormField(
                controller: _codMax,
                enabled: _cod,
                decoration: const InputDecoration(
                  labelText: 'COD limit',
                  prefixText: '₹ ',
                  helperText: 'Orders above this must pay online.',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [RupeesFormatter(maxDigits: 7)],
                textInputAction: TextInputAction.next,
                validator: _limitError,
              ),
              const ListSection('Refer & earn'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Run Refer & earn'),
                subtitle: const Text('Customers share a code. The friend gets money off their first order, and the '
                    'customer gets a coupon once it’s delivered.'),
                value: _referral,
                onChanged: (v) => setState(() => _referral = v),
              ),
              TextFormField(
                controller: _friend,
                enabled: _referral,
                decoration: const InputDecoration(labelText: 'Friend gets', prefixText: '₹ ', helperText: 'Off their first order'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [RupeesFormatter(maxDigits: 5)],
                textInputAction: TextInputAction.next,
                validator: _couponError,
              ),
              _gap(),
              TextFormField(
                controller: _reward,
                enabled: _referral,
                decoration: const InputDecoration(labelText: 'Customer gets', prefixText: '₹ ', helperText: 'A coupon when the friend’s order is delivered'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [RupeesFormatter(maxDigits: 5)],
                textInputAction: TextInputAction.next,
                validator: _couponError,
              ),
              _gap(),
              TextFormField(
                controller: _referralMin,
                enabled: _referral,
                decoration: const InputDecoration(labelText: 'Minimum order', prefixText: '₹ ', helperText: 'For both coupons'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [RupeesFormatter(maxDigits: 7)],
                textInputAction: TextInputAction.next,
                validator: _limitError,
              ),
              _gap(),
              TextFormField(
                controller: _referralCap,
                enabled: _referral,
                decoration: const InputDecoration(labelText: 'Rewards per customer a month', helperText: 'Stops one person farming codes'),
                keyboardType: TextInputType.number,
                inputFormatters: const [DigitsFormatter(3)],
                textInputAction: TextInputAction.next,
                validator: (v) => int.tryParse(v ?? '') == null ? 'Enter a number, 0 or more.' : null,
              ),
              const ListSection('Store'),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Store phone (also WhatsApp)', prefixText: '+91 ', hintText: '98765 43210'),
                keyboardType: TextInputType.phone,
                inputFormatters: const [IndianMobileFormatter()],
                textInputAction: TextInputAction.next,
                validator: validateMobile,
              ),
              _gap(),
              TextFormField(
                controller: _address,
                decoration: InputDecoration(
                  labelText: 'Address',
                  alignLabelWithHint: true,
                  counter: LengthCounter(_address, MaxLen.storeAddress),
                ),
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: textInput(MaxLen.storeAddress, multiline: true),
                validator: (v) => checkText(v, max: MaxLen.storeAddress, multiline: true),
              ),
              _gap(),
              TextFormField(
                controller: _pin,
                decoration: InputDecoration(
                  labelText: 'Shop location',
                  hintText: 'Google Maps link, or 24.0670, 82.6307',
                  helperText: pin == null
                      ? 'In Google Maps, open the shop and copy the link from the address bar. Directions go to this exact spot.'
                      : 'Pin: ${pin.lat}, ${pin.lng}',
                  helperMaxLines: 3,
                  errorMaxLines: 3,
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                // generous: full place links run long and their pin sits near the end, so a cut would lose it
                inputFormatters: textInput(2000),
                minLines: 1,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                validator: (v) => (v ?? '').trim().isEmpty || parseMapPin(v!) != null
                    ? null
                    : 'No pin in India found. Paste “lat, lng” or the full link from the browser, not a maps.app.goo.gl short link.',
              ),
              if (pin != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () =>
                        openExternal(context, mapPinUri(pin.lat, pin.lng), 'Couldn’t open Google Maps.'),
                    icon: const Icon(PhosphorIconsRegular.mapPin),
                    label: const Text('Open in Google Maps'),
                  ),
                ),
              _gap(),
              TextFormField(
                controller: _hours,
                decoration: const InputDecoration(labelText: 'Opening hours', hintText: '10 am – 9 pm, closed Tuesday'),
                inputFormatters: textInput(MaxLen.storeHours),
                textInputAction: TextInputAction.done,
                validator: (v) => checkText(v, max: MaxLen.storeHours),
              ),
              const _ShopPhotos(),
              const ListSection('Customer notes'),
              TextFormField(
                controller: _repairNote,
                decoration: InputDecoration(
                  labelText: 'Repair booking note',
                  helperText: 'Shown on the repair booking form.',
                  alignLabelWithHint: true,
                  counter: LengthCounter(_repairNote, MaxLen.storeAddress),
                ),
                minLines: 2,
                maxLines: 4,
                inputFormatters: textInput(MaxLen.storeAddress, multiline: true),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => tidy(v).isEmpty ? 'Add a short note' : checkText(v, max: MaxLen.storeAddress, multiline: true),
              ),
              _gap(),
              TextFormField(
                controller: _returns,
                decoration: InputDecoration(
                  labelText: 'Returns and warranty policy',
                  helperText: 'Shown on product pages and in Account.',
                  alignLabelWithHint: true,
                  counter: LengthCounter(_returns, MaxLen.returnsPolicy),
                ),
                minLines: 4,
                maxLines: 10,
                inputFormatters: textInput(MaxLen.returnsPolicy, multiline: true),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) =>
                    tidy(v).isEmpty ? 'Add your returns policy' : checkText(v, max: MaxLen.returnsPolicy, multiline: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saved straight away (not with "Save settings"): they're files, not form fields.
class _ShopPhotos extends ConsumerStatefulWidget {
  const _ShopPhotos();

  static const max = 8; // store_settings check

  @override
  ConsumerState<_ShopPhotos> createState() => _ShopPhotosState();
}

class _ShopPhotosState extends ConsumerState<_ShopPhotos> {
  bool _busy = false;

  List<String> get _photos => ref.read(storeSettingsProvider).value?.storePhotos ?? const [];

  Future<void> _run(Future<void> Function() write, [String? done]) async {
    setState(() => _busy = true);
    try {
      await write();
      if (mounted && done != null) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final file = await pickPhoto(context);
    if (file == null) return;
    await _run(() async {
      final saved = await addStorePhoto(ref, _photos, await readPhoto(file));
      if (mounted) {
        showMessage(context, 'Photo added · ${formatBytes(saved.before)} → ${formatBytes(saved.after)}. Customers see it now.');
      }
    });
  }

  void _move(int i, int to) {
    final list = [..._photos];
    list.insert(to, list.removeAt(i));
    _run(() => saveStorePhotos(ref, list), 'Order saved');
  }

  Future<void> _remove(String path) async {
    final ok = await confirmChoice(
      context,
      title: 'Remove this photo?',
      message: 'It’s taken off the home screen and deleted.',
      action: 'Remove',
      keep: 'Keep photo',
      destructive: true,
    );
    if (ok) await _run(() => removeStorePhoto(ref, _photos, path), 'Photo removed');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final photos = ref.watch(storeSettingsProvider).value?.storePhotos ?? const <String>[];
    final full = photos.length >= _ShopPhotos.max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSection(
          'Shop photos',
          trailing: TextButton.icon(
            onPressed: _busy || full ? null : _add,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(PhosphorIconsRegular.plus),
            label: const Text('Add photo'),
          ),
        ),
        Text(
          full
              ? 'That’s the most (${_ShopPhotos.max}). Remove one to add another.'
              : '${photos.length} of ${_ShopPhotos.max}. Shown on the home screen in this order. Changes save straight away.',
          style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
        if (photos.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: Space.sm),
            child: Row(
              spacing: Space.sm,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, path) in photos.indexed)
                  SizedBox(
                    key: ValueKey(path),
                    width: 152,
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.md),
                          child: ProductImage(path, aspectRatio: 4 / 3, radius: 0, padding: 0, fit: BoxFit.cover),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              tooltip: 'Move photo ${i + 1} left',
                              onPressed: _busy || i == 0 ? null : () => _move(i, i - 1),
                              icon: const Icon(PhosphorIconsRegular.arrowLeft),
                            ),
                            IconButton(
                              tooltip: 'Move photo ${i + 1} right',
                              onPressed: _busy || i == photos.length - 1 ? null : () => _move(i, i + 1),
                              icon: const Icon(PhosphorIconsRegular.arrowRight),
                            ),
                            IconButton(
                              tooltip: 'Remove photo ${i + 1}',
                              onPressed: _busy ? null : () => _remove(path),
                              icon: const Icon(PhosphorIconsRegular.trash),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
