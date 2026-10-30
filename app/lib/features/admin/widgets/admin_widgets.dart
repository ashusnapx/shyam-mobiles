import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';

/// Copy for admin write errors; falls back to the shared mapping.
String adminError(Object e) => switch (e) {
      PostgrestException(code: '23505', :final message) when message.contains('collections') =>
        'Another group already has this short name. Change it and save again.',
      PostgrestException(code: '23505', :final message) when message.contains('slug') =>
        'Another product already uses this slug. Change it and save again.',
      PostgrestException(code: '23505', :final message) when message.contains('sku') =>
        'Another variant already uses this SKU.',
      PostgrestException(code: '23505') => 'That’s already in use. Pick a different value.',
      PostgrestException(code: 'PGRST116') => 'Nothing was saved. Check you’re signed in with a staff account.',
      PostgrestException(message: 'INVALID_IMEIS') => 'Each IMEI must be 15 digits, one per unit, no repeats.',
      StorageException() => 'Couldn’t upload the photo. Check your connection and try again.',
      FormatException(:final message) => message,
      _ => friendlyError(e),
    };

TagTone orderTone(OrderStatus s) => switch (s) {
      OrderStatus.pendingPayment => TagTone.deal,
      OrderStatus.confirmed || OrderStatus.packed || OrderStatus.shipped => TagTone.info,
      OrderStatus.delivered => TagTone.ok,
      OrderStatus.cancelled => TagTone.bad,
      OrderStatus.refunded => TagTone.info,
    };

/// "Pixel 9a", "Pixel 9a +2 more"
String itemsSummary(Order o) => o.items.isEmpty
    ? 'No items'
    : o.items.length == 1
        ? o.items.first.productName
        : '${o.items.first.productName} +${o.items.length - 1} more';

/// "COD" or the payment status ("Paid", "Pending", ...).
String paymentShort(Order o) => o.paymentMethod == PaymentMethod.cod ? 'COD' : o.paymentStatus.label;

/// Server enforces admin rights; this shows a friendly screen instead of errors to non-staff.
class AdminGate extends ConsumerWidget {
  const AdminGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.watch(isAdminProvider);
    if (admin.value == true) return child;
    return Scaffold(
      appBar: AppBar(),
      body: admin.hasError
          ? ErrorView(error: admin.error!, onRetry: () => ref.invalidate(isAdminProvider))
          : admin.isLoading
              ? const Center(child: CircularProgressIndicator())
              : const EmptyState(
                  icon: PhosphorIconsRegular.lockSimple,
                  title: 'Staff only',
                  message: 'This part of the app is for Shyam Mobiles staff.',
                ),
    );
  }
}

/// Error line for a section inside a scrolling list (ErrorView needs the whole screen).
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.cloudX, color: c.error),
          const SizedBox(width: Space.md),
          Expanded(child: Text(friendlyError(error), style: Theme.of(context).textTheme.bodyMedium)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Staff confirmations, same rule as everywhere: the recommended choice is filled, on the right.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  String cancel = 'Not now',
  bool destructive = false,
}) =>
    confirmChoice(context, title: title, message: message, action: action, keep: cancel, destructive: destructive);

/// Asks for courier (required) and tracking number (optional). Null if dismissed.
Future<({String courier, String? tracking})?> showShipSheet(
  BuildContext context, {
  required String title,
  required String action,
  String? courier,
  String? tracking,
}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ShipSheet(title: title, action: action, courier: courier, tracking: tracking),
    );

class _ShipSheet extends StatefulWidget {
  const _ShipSheet({required this.title, required this.action, this.courier, this.tracking});

  final String title;
  final String action;
  final String? courier;
  final String? tracking;

  @override
  State<_ShipSheet> createState() => _ShipSheetState();
}

class _ShipSheetState extends State<_ShipSheet> {
  final _form = GlobalKey<FormState>();
  late final _courier = TextEditingController(text: widget.courier);
  late final _tracking = TextEditingController(text: widget.tracking);

  @override
  void dispose() {
    _courier.dispose();
    _tracking.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final tracking = tidy(_tracking.text);
    Navigator.pop(context, (courier: tidy(_courier.text), tracking: tracking.isEmpty ? null : tracking));
  }

  @override
  Widget build(BuildContext context) => SheetForm(
        formKey: _form,
        title: widget.title,
        children: [
          TextFormField(
            controller: _courier,
            autofocus: widget.courier == null,
            decoration: const InputDecoration(labelText: 'Courier', hintText: 'e.g. Delhivery, or Shop delivery'),
            textCapitalization: TextCapitalization.words,
            inputFormatters: textInput(MaxLen.courier),
            textInputAction: TextInputAction.next,
            validator: (v) => checkText(v, min: 1, max: MaxLen.courier, what: 'the courier', mustHave: hasLetterOrDigit),
          ),
          const SizedBox(height: Space.sm),
          TextFormField(
            controller: _tracking,
            decoration: const InputDecoration(labelText: 'Tracking number (optional)'),
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: textInput(MaxLen.courier),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Space.md),
          FilledButton(onPressed: _submit, child: Text(widget.action)),
        ],
      );
}

/// Bottom-sheet body: title, scrollable form, lifted above the keyboard.
class SheetForm extends StatelessWidget {
  const SheetForm({super.key, required this.formKey, required this.title, required this.children});

  final GlobalKey<FormState> formKey;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg + MediaQuery.paddingOf(context).bottom),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
                const SizedBox(height: Space.lg),
                ...children,
              ],
            ),
          ),
        ),
      );
}

/// Gallery or camera, then the original file: photos.dart resizes it, turns it upright and strips the metadata
/// (image_picker's own resize keeps GPS). Null when cancelled, or when nothing could open (with a message).
Future<XFile?> pickPhoto(BuildContext context) async {
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
  if (source == null) return null;
  try {
    return await ImagePicker().pickImage(source: source);
  } catch (_) {
    if (context.mounted) showMessage(context, 'Couldn’t open the camera or gallery.');
    return null;
  }
}

/// A date and time from the system pickers (nothing to type), shown as "30 Oct 2026, 6:00 pm". With [clearable]
/// a cross empties it, and [emptyText] says what empty means ("No end date").
class DateTimeField extends FormField<DateTime> {
  DateTimeField({
    super.key,
    required String label,
    required ValueChanged<DateTime?> onChanged,
    super.initialValue,
    super.validator,
    bool clearable = false,
    String emptyText = '',
    String? helperText,
  }) : super(
          builder: (field) {
            final value = field.value;
            Future<void> open() async {
              final now = DateTime.now();
              final start = value ?? now;
              final first = DateTime(start.isBefore(now) ? start.year : now.year - 1);
              final day = await showDatePicker(
                context: field.context,
                initialDate: start,
                firstDate: first,
                lastDate: DateTime(now.year + 3, 12, 31),
              );
              if (day == null || !field.mounted) return;
              final time = await showTimePicker(context: field.context, initialTime: TimeOfDay.fromDateTime(start));
              if (time == null || !field.mounted) return;
              final picked = DateTime(day.year, day.month, day.day, time.hour, time.minute);
              field.didChange(picked);
              onChanged(picked);
            }

            return Semantics(
              button: true,
              label: '$label, ${value == null ? emptyText : formatDateTime(value)}',
              excludeSemantics: true,
              child: InkWell(
                onTap: open,
                borderRadius: BorderRadius.circular(Radii.md),
                child: InputDecorator(
                  isEmpty: value == null && emptyText.isEmpty,
                  decoration: InputDecoration(
                    labelText: label,
                    helperText: helperText,
                    helperMaxLines: 3,
                    errorText: field.errorText,
                    errorMaxLines: 2,
                    suffixIcon: clearable && value != null
                        ? IconButton(
                            tooltip: 'Clear $label',
                            icon: const Icon(PhosphorIconsRegular.xCircle, size: 20),
                            onPressed: () {
                              field.didChange(null);
                              onChanged(null);
                            },
                          )
                        : const Icon(PhosphorIconsRegular.calendarBlank, size: 18),
                  ),
                  child: Text(value == null ? emptyText : formatDateTime(value)),
                ),
              ),
            );
          },
        );
}
