import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../repairs/data/repairs.dart';
import '../../repairs/screens/repair_detail_screen.dart' show RepairStatusHero;
import '../../repairs/widgets/repair_widgets.dart';
import '../data/admin.dart';
import '../data/rules.dart';
import '../widgets/admin_widgets.dart';

class AdminRepairScreen extends ConsumerWidget {
  const AdminRepairScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = repairProvider(bookingId);
    final value = ref.watch(provider);
    return AdminGate(
      child: Scaffold(
        appBar: AppBar(title: Text(value.value == null ? 'Repair' : 'Repair ${value.value!.number}')),
        body: AsyncBody<RepairBooking>(
          value: value,
          onRetry: () => ref.invalidate(provider),
          loading: const Center(child: CircularProgressIndicator()),
          data: (b) => _Body(booking: b),
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.booking});

  final RepairBooking booking;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final _form = GlobalKey<FormState>();
  late final _quote = TextEditingController(
    text: widget.booking.quotePaise == null ? '' : rupeesText(widget.booking.quotePaise!),
  );
  late final _note = TextEditingController(text: widget.booking.adminNote ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _quote.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _write(String done, Map<String, dynamic> changes) async {
    try {
      await updateRepair(ref, widget.booking.id, changes);
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, adminError(e));
    }
  }

  /// One action at a time, the confirm dialog included, so a double tap can't open two or write twice.
  Future<void> _once(Future<void> Function() flow) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await flow();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(RepairStatus to) async {
    if (to == RepairStatus.cancelled &&
        !await confirmAction(
          context,
          title: 'Cancel ${widget.booking.number}?',
          message: 'The customer sees the booking as cancelled.',
          action: 'Cancel booking',
          cancel: 'Keep booking',
          destructive: true,
        )) {
      return;
    }
    await _write('Marked ${to.label.toLowerCase()}', {'status': to.value});
  }

  Future<void> _saveQuote() async {
    if (!_form.currentState!.validate()) return;
    final note = tidy(_note.text, multiline: true);
    await _write('Saved', {
      'quote_paise': _quote.text.trim().isEmpty ? null : parseRupees(_quote.text),
      'admin_note': note.isEmpty ? null : note,
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final b = widget.booking;
    final next = repairNextStep[b.status];
    return ListView(
      padding: EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.xl + MediaQuery.paddingOf(context).bottom),
      children: [
        RepairStatusHero(booking: b),
        if (b.status.isOpen) ...[
          const SizedBox(height: Space.md),
          Row(
            children: [
              if (next != null)
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _once(() => _setStatus(next)),
                    child: Text('Mark ${next.label.toLowerCase()}'),
                  ),
                ),
              const SizedBox(width: Space.sm),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: c.error),
                onPressed: _busy ? null : () => _once(() => _setStatus(RepairStatus.cancelled)),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
        const ListSection('Customer'),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(PhosphorIconsRegular.phone),
                title: Text(displayPhone(b.contactPhone)),
                subtitle: const Text('Tap to call'),
                onTap: () => openUri(context, telUri(b.contactPhone)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.sm),
                child: TextButton.icon(
                  onPressed: () => openUri(context, whatsAppUri(b.contactPhone, text: repairUpdateText(b))),
                  icon: const WhatsAppIcon(),
                  label: const Text('Send update on WhatsApp'),
                ),
              ),
            ],
          ),
        ),
        const ListSection('Device'),
        Card(
          child: Column(
            children: [
              InfoRow('Phone', '${b.deviceBrand} ${b.deviceModel}'),
              InfoRow('Issue', b.issue.label),
              if (b.description.isNotEmpty) InfoRow('Customer notes', b.description),
              InfoRow('Slot', '${repairWhen(b)} (${b.slot.hours})'),
              InfoRow('Booked', formatDateTime(b.createdAt)),
            ],
          ),
        ),
        const ListSection('Quote and note'),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _quote,
                decoration: const InputDecoration(labelText: 'Quote', prefixText: '₹ ', hintText: 'Blank until inspected'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [RupeesFormatter(maxDigits: 7)],
                textInputAction: TextInputAction.next,
                validator: (v) => rupeesError(v, maxPaise: maxAmountPaise, optional: true),
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _note,
                decoration: InputDecoration(
                  labelText: 'Note for the customer (optional)',
                  counter: LengthCounter(_note, MaxLen.note),
                ),
                minLines: 2,
                maxLines: 5,
                inputFormatters: textInput(MaxLen.note, multiline: true),
                textCapitalization: TextCapitalization.sentences,
              ),
              Text(
                'The customer sees the quote and note in the app. Work starts only after they approve the price.',
                style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
              const SizedBox(height: Space.md),
              FilledButton.tonal(
                onPressed: _busy ? null : () => _once(_saveQuote),
                child: const Text('Save quote and note'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
