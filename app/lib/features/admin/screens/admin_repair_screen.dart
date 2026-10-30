import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../feedback/data/feedback.dart' show FeedbackKind;
import '../../repairs/data/repairs.dart';
import '../../repairs/screens/repair_detail_screen.dart' show RepairHistory, RepairStatusHero, RepairTimeline;
import '../../repairs/widgets/repair_widgets.dart';
import '../data/admin.dart';
import '../data/rules.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/feedback_card.dart';

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
          // keyed by the quote so a refresh after a write refills the quote field
          data: (b) => RefreshIndicator(
            onRefresh: () => ref.refresh(provider.future),
            child: _Body(key: ValueKey('${b.id} ${b.quotePaise}'), booking: b),
          ),
        ),
      ),
    );
  }
}

/// The next step's button label, by the status it moves to.
String _stepLabel(RepairStatus to) => switch (to) {
      RepairStatus.confirmed => 'Confirm booking',
      RepairStatus.inProgress => 'Start repair',
      RepairStatus.ready => 'Ready for pickup',
      RepairStatus.completed => 'Mark completed',
      _ => to.label,
    };

class _Body extends ConsumerStatefulWidget {
  const _Body({super.key, required this.booking});

  final RepairBooking booking;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final _form = GlobalKey<FormState>();
  late final _quote = TextEditingController(
    text: widget.booking.quotePaise == null ? '' : rupeesText(widget.booking.quotePaise!),
  );
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _quote.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _write(String done, Future<void> Function() write) async {
    try {
      await write();
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

  RepairBooking get _b => widget.booking;

  Future<void> _step(RepairStatus to) async {
    if (to == RepairStatus.completed &&
        !await confirmAction(
          context,
          title: 'Mark ${_b.number} completed?',
          message: 'Only once the customer has collected the phone.',
          action: 'Mark completed',
        )) {
      return;
    }
    if (!mounted) return;
    await _write('Marked ${to.label.toLowerCase()}', () => updateRepairStatus(ref, _b.id, to));
  }

  Future<void> _cancel() async {
    final reason = await askReason(
      context,
      title: 'Cancel ${_b.number}?',
      message: 'The customer sees the booking as cancelled, with your reason.',
      action: 'Cancel booking',
      keep: 'Keep booking',
    );
    if (reason == null || !mounted) return;
    await _write('Booking cancelled',
        () => updateRepairStatus(ref, _b.id, RepairStatus.cancelled, note: 'Cancelled by the store: $reason'));
  }

  Future<void> _sendQuote() async {
    if (!_form.currentState!.validate()) return;
    final paise = parseRupees(_quote.text)!;
    final changing = _b.quotePaise != null;
    await _write(changing ? 'New quote sent' : 'Quote sent', () => setRepairQuote(ref, _b.id, paise));
  }

  Future<void> _approvedInPerson() async {
    final quote = formatInr(_b.quotePaise!);
    final ok = await confirmAction(
      context,
      title: 'Customer agreed to $quote?',
      message: 'Only if they said yes at the counter or on the phone. Their timeline shows it as agreed with the store.',
      action: 'They agreed',
    );
    if (!ok || !mounted) return;
    await _write('Recorded as approved', () => setRepairQuote(ref, _b.id, _b.quotePaise!, approved: true));
  }

  Future<void> _sendNote() async {
    final note = tidy(_note.text, multiline: true);
    if (note.isEmpty) return showMessage(context, 'Write the note first.');
    await _write('Note sent', () async {
      await updateRepairStatus(ref, _b.id, _b.status, note: note);
      _note.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final b = widget.booking;
    final next = repairNextStep[b.status];
    final blocker = repairStepBlocker(b);
    final declineReason =
        b.quoteDeclined ? b.events.where((e) => e.quoteStatus == RepairQuoteStatus.declined).lastOrNull?.note : null;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.xl + MediaQuery.paddingOf(context).bottom),
      children: [
        RepairStatusHero(booking: b),
        if (b.awaitingApproval) ...[
          const SizedBox(height: Space.md),
          NoteBox('Waiting for the customer to approve ${formatInr(b.quotePaise!)} in the app.',
              icon: PhosphorIconsFill.hourglassMedium),
        ],
        if (b.quoteDeclined) ...[
          const SizedBox(height: Space.md),
          NoteBox(
            'The customer declined ${formatInr(b.quotePaise!)}${declineReason == null ? '' : ': “$declineReason”'}. '
            'Call them, then send a new quote or cancel.',
            tone: TagTone.bad,
            icon: PhosphorIconsFill.xCircle,
          ),
        ],
        if (b.status.isOpen) ...[
          const SizedBox(height: Space.md),
          if (next != null)
            FilledButton(
              onPressed: _busy || blocker != null ? null : () => _once(() => _step(next)),
              child: Text(_stepLabel(next)),
            ),
          if (blocker != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(blocker, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            ),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: c.error, side: BorderSide(color: c.error)),
            onPressed: _busy ? null : () => _once(_cancel),
            icon: const Icon(PhosphorIconsRegular.xCircle),
            label: const Text('Cancel booking'),
          ),
        ],
        if (canQuoteRepair(b.status)) ...[
          const ListSection('Quote'),
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _quote,
                  decoration: const InputDecoration(labelText: 'Price for the customer', prefixText: '₹ '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [RupeesFormatter(maxDigits: 7)],
                  validator: (v) => rupeesError(v, maxPaise: maxAmountPaise),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  b.quotePaise == null
                      ? 'The customer approves or declines it in the app. Work starts only after they approve.'
                      : 'A new price waits for the customer again, even mid-repair.',
                  style: t.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),
                const SizedBox(height: Space.sm),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _once(_sendQuote),
                  child: Text(b.quotePaise == null ? 'Send quote' : 'Change quote'),
                ),
                if (b.awaitingApproval || b.quoteDeclined)
                  TextButton(
                    onPressed: _busy ? null : () => _once(_approvedInPerson),
                    child: const Text('Customer agreed in person or by phone'),
                  ),
              ],
            ),
          ),
        ],
        const ListSection('Note to the customer'),
        TextField(
          controller: _note,
          decoration: InputDecoration(
            labelText: 'Shown on their timeline',
            counter: LengthCounter(_note, MaxLen.note),
          ),
          minLines: 2,
          maxLines: 5,
          inputFormatters: textInput(MaxLen.note, multiline: true),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: Space.sm),
        FilledButton.tonal(
          onPressed: _busy ? null : () => _once(_sendNote),
          child: const Text('Send note'),
        ),
        CustomerFeedbackCard(kind: FeedbackKind.repair, id: b.id),
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
              if (b.quotePaise != null && !canQuoteRepair(b.status)) InfoRow('Price', formatInr(b.quotePaise!), strong: true),
            ],
          ),
        ),
        if (b.status != RepairStatus.cancelled) ...[
          const ListSection('Progress'),
          RepairTimeline(booking: b, hint: false),
        ],
        if (b.events.isNotEmpty) ...[
          const ListSection('Timeline'),
          RepairHistory(events: b.events),
        ],
      ],
    );
  }
}
