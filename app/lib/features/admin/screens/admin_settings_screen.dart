import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../catalog/widgets/store_links.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../data/admin.dart';
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
  late final _phone = TextEditingController(text: displayPhone(_s.storePhone));
  late final _address = TextEditingController(text: _s.storeAddress);
  late final _pin = TextEditingController(text: _s.storeLat == null ? '' : '${_s.storeLat}, ${_s.storeLng}');
  late String? _mapsUrl = _s.storeMapsUrl;
  late final _hours = TextEditingController(text: _s.storeHours);
  late final _repairNote = TextEditingController(text: _s.repairNote);
  late final _returns = TextEditingController(text: _s.returnsPolicy);
  late bool _cod = _s.codEnabled;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_fee, _freeMin, _codMax, _phone, _address, _pin, _hours, _repairNote, _returns]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final pinText = _pin.text.trim();
    final pin = parseMapPin(pinText); // null when empty: clears the pin
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
          storeAddress: _address.text.trim(),
          storeLat: pin?.lat,
          storeLng: pin?.lng,
          storeMapsUrl: _mapsUrl,
          storeHours: _hours.text.trim(),
          repairNote: _repairNote.text.trim(),
          returnsPolicy: _returns.text.trim(),
        ),
      );
      if (mounted) showMessage(context, 'Settings saved');
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _money(String? v) => parseRupees(v ?? '') == null ? 'Enter an amount like 49 or 999' : null;

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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
          children: [
            const ListSection('Delivery'),
            TextFormField(
              controller: _fee,
              decoration: const InputDecoration(labelText: 'Delivery fee', prefixText: '₹ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: _money,
            ),
            _gap(),
            TextFormField(
              controller: _freeMin,
              decoration: const InputDecoration(
                labelText: 'Free delivery from',
                prefixText: '₹ ',
                helperText: 'Orders at or above this pay no delivery fee. 0 makes delivery always free.',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: _money,
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
              validator: _money,
            ),
            const ListSection('Store'),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Store phone (also WhatsApp)'),
              keyboardType: TextInputType.phone,
              validator: (v) => normalizeIndianPhone(v ?? '') == null ? 'Enter a 10-digit Indian mobile number' : null,
            ),
            _gap(),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address', alignLabelWithHint: true),
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
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
              maxLength: 60,
            ),
            const _ShopPhotos(),
            const ListSection('Customer notes'),
            TextFormField(
              controller: _repairNote,
              decoration: const InputDecoration(
                labelText: 'Repair booking note',
                helperText: 'Shown on the repair booking form.',
                alignLabelWithHint: true,
              ),
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Add a short note' : null,
            ),
            _gap(),
            TextFormField(
              controller: _returns,
              decoration: const InputDecoration(
                labelText: 'Returns and warranty policy',
                helperText: 'Shown on product pages and in Account.',
                alignLabelWithHint: true,
              ),
              minLines: 4,
              maxLines: 10,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Add your returns policy' : null,
            ),
          ],
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

  // shortcut: same picker sheet as the product photos (admin_product_edit_screen.dart); share it if a third use appears.
  Future<void> _add() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(PhosphorIconsRegular.image),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    } catch (_) {
      if (mounted) showMessage(context, 'Couldn’t open the camera or gallery.');
      return;
    }
    if (file == null) return;
    await _run(() async => addStorePhoto(ref, _photos, await file!.readAsBytes()), 'Photo added. Customers see it now.');
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
