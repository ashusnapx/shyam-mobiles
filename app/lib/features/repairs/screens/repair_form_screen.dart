import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/booking_days.dart';
import '../data/repairs.dart';
import '../widgets/repair_widgets.dart';

const _brands = ['Apple', 'Samsung', 'OnePlus', 'Xiaomi', 'vivo', 'Other'];

class RepairFormScreen extends ConsumerStatefulWidget {
  const RepairFormScreen({super.key});

  @override
  ConsumerState<RepairFormScreen> createState() => _RepairFormScreenState();
}

class _RepairFormScreenState extends ConsumerState<RepairFormScreen> {
  final _form = GlobalKey<FormState>();
  final _otherBrand = TextEditingController();
  final _model = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  final _now = DateTime.now();
  late final _days = bookingDays(_now);
  late DateTime _day = _days.first;
  String? _brand;
  RepairIssue? _issue;
  RepairSlot? _slot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(myPhoneProvider.future).then((p) {
      if (mounted && p != null && _phone.text.isEmpty) _phone.text = localPhone(p);
    }, onError: (_) {}); // prefill is a nicety; the field stays editable
  }

  @override
  void dispose() {
    for (final c in [_otherBrand, _model, _description, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _slotOpen(RepairSlot s) => !slotOver(s, _day, _now);

  Future<void> _submit() async {
    if (_busy) return; // a double tap would book twice
    final missing = [
      if (_brand == null) 'your phone’s brand',
      if (_issue == null) 'what’s wrong',
      if (_slot == null) 'a time slot',
    ];
    final fieldsOk = _form.currentState!.validate();
    if (missing.isNotEmpty) return showMessage(context, 'Pick ${missing.join(', ')}.');
    if (!fieldsOk) return;
    setState(() => _busy = true);
    try {
      final id = await bookRepair(
        ref.read(supabaseProvider),
        deviceBrand: _brand == 'Other' ? tidy(_otherBrand.text) : _brand!,
        deviceModel: tidy(_model.text),
        issue: _issue!,
        description: tidy(_description.text, multiline: true),
        preferredDate: isoDate(_day),
        slot: _slot!,
        contactPhone: normalizeIndianPhone(_phone.text)!,
      );
      ref.invalidate(myRepairsProvider);
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      showMessage(context, 'Booked. We’ll call you to confirm.');
      context.pushReplacement('/repairs/$id');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final settings = ref.watch(storeSettingsProvider).value;
    final note = settings?.repairNote;
    final storePhone = settings?.storePhone;
    final when = bookingDayLabel(_day, _now);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: () => context.canPop() ? context.pop() : context.go('/repairs'),
        ),
        title: const Text('Book a repair'),
      ),
      bottomNavigationBar: StickyBar(
        child: FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(_slot == null ? 'Book for $when' : 'Book for $when, ${_slot!.label.toLowerCase()}'),
        ),
      ),
      body: Form(
        key: _form,
        // not a ListView: a lazy list drops fields scrolled far away, and Form.validate() would skip them
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Pad(FieldLabel('Your phone')),
              ChipBar(
                options: {for (final b in _brands) b: b},
                selected: _brand,
                onSelected: (b) => setState(() => _brand = b),
              ),
              if (_brand == 'Other')
                _Pad(Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: TextFormField(
                    controller: _otherBrand,
                    decoration: const InputDecoration(labelText: 'Brand'),
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: textInput(MaxLen.deviceBrand),
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        checkText(v, min: 1, max: MaxLen.deviceBrand, what: 'the brand', mustHave: hasLetterOrDigit),
                  ),
                )),
              _Pad(Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: TextFormField(
                  controller: _model,
                  decoration: const InputDecoration(labelText: 'Model', hintText: 'e.g. Galaxy S23'),
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: textInput(MaxLen.deviceModel),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      checkText(v, min: 1, max: MaxLen.deviceModel, what: 'the model', mustHave: hasLetterOrDigit),
                ),
              )),
              const _Pad(FieldLabel('What’s wrong?')),
              _Pad(_IssueGrid(selected: _issue, onSelected: (i) => setState(() => _issue = i))),
              _Pad(Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: TextFormField(
                  controller: _description,
                  decoration: InputDecoration(
                    labelText: 'Anything else? (optional)',
                    counter: LengthCounter(_description, MaxLen.note),
                  ),
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: textInput(MaxLen.note, multiline: true),
                ),
              )),
              const _Pad(FieldLabel('When can you come in?')),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: Row(
                  children: [
                    for (final d in _days)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.sm),
                        child: _DayChip(
                          day: d,
                          today: isIstToday(d, _now),
                          selected: d == _day,
                          onTap: () => setState(() {
                            _day = d;
                            if (_slot != null && !_slotOpen(_slot!)) _slot = null;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              _Pad(Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: Row(
                  children: [
                    for (final s in RepairSlot.values) ...[
                      if (s != RepairSlot.values.first) const SizedBox(width: Space.sm),
                      Expanded(
                        child: _SlotChip(
                          slot: s,
                          selected: s == _slot,
                          onTap: _slotOpen(s) ? () => setState(() => _slot = s) : null,
                        ),
                      ),
                    ],
                  ],
                ),
              )),
              _Pad(Padding(
                padding: const EdgeInsets.only(top: Space.xl),
                child: TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone for updates',
                    prefixIcon: Icon(PhosphorIconsRegular.phone),
                    prefixText: '+91 ',
                    hintText: '98765 43210',
                  ),
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: const [IndianMobileFormatter()],
                  textInputAction: TextInputAction.done,
                  validator: validateMobile,
                ),
              )),
              if (note != null && note.isNotEmpty)
                _Pad(Padding(padding: const EdgeInsets.only(top: Space.lg), child: NoteBox(note))),
              _Pad(Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: Text(
                  'Booking is free. You can cancel until the repair starts.',
                  style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              )),
              if (storePhone != null)
                _Pad(Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => openUri(context, whatsAppUri(storePhone, text: 'Hi, I have a question about a repair')),
                    icon: const WhatsAppIcon(),
                    label: const Text('WhatsApp'),
                  ),
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: Space.lg), child: child);
}

/// 4-column issue grid (mockup `.issues`). Tiles grow with text scale instead of clipping.
class _IssueGrid extends StatelessWidget {
  const _IssueGrid({required this.selected, required this.onSelected});

  final RepairIssue? selected;
  final ValueChanged<RepairIssue> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - Space.sm * 3) / 4;
        return Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final issue in RepairIssue.values)
              Builder(builder: (context) {
                final on = issue == selected;
                final fg = on ? c.onPrimaryContainer : c.onSurface;
                return SizedBox(
                  width: width,
                  child: Semantics(
                    selected: on,
                    button: true,
                    child: Material(
                      color: on ? c.primaryContainer : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: on ? BorderSide.none : BorderSide(color: c.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onSelected(issue),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 76),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.sm),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(issueIcons[issue], size: 24, color: on ? fg : c.onSurfaceVariant),
                                const SizedBox(height: 6),
                                Text(
                                  issue.label,
                                  textAlign: TextAlign.center,
                                  style: t.labelSmall?.copyWith(color: fg, height: 1.15),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.today, required this.selected, required this.onTap});

  final DateTime day;
  final bool today;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final fg = selected ? c.onPrimary : c.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      label: '${today ? 'Today, ' : ''}${DateFormat('EEEE d MMMM').format(day)}',
      excludeSemantics: true,
      child: Material(
        color: selected ? c.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: selected ? BorderSide.none : BorderSide(color: c.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56, minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    today ? 'Today' : DateFormat('EEE').format(day),
                    style: t.labelSmall?.copyWith(color: selected ? fg : c.onSurfaceVariant),
                  ),
                  Text('${day.day}', style: t.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.slot, required this.selected, required this.onTap});

  final RepairSlot slot;
  final bool selected;
  final VoidCallback? onTap; // null when the slot is over today

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final fg = selected ? c.onPrimaryContainer : c.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      enabled: onTap != null,
      label: '${slot.label}, ${slot.hours}${onTap == null ? ', not available today' : ''}',
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Material(
          color: selected ? c.primaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
            side: selected ? BorderSide.none : BorderSide(color: c.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(slot.label, style: t.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                    Text(
                      slot.hours,
                      textAlign: TextAlign.center,
                      style: t.labelSmall?.copyWith(
                        color: selected ? fg : c.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
