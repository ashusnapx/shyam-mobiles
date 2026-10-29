import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
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
  late final _hours = TextEditingController(text: _s.storeHours);
  late final _repairNote = TextEditingController(text: _s.repairNote);
  late final _returns = TextEditingController(text: _s.returnsPolicy);
  late bool _cod = _s.codEnabled;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_fee, _freeMin, _codMax, _phone, _address, _hours, _repairNote, _returns]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
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
  Widget build(BuildContext context) => Scaffold(
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
                controller: _hours,
                decoration: const InputDecoration(labelText: 'Opening hours', hintText: '10 am – 9 pm, closed Tuesday'),
                maxLength: 60,
              ),
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
