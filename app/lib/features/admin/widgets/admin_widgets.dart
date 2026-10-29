import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';

/// Copy for admin write errors; falls back to the shared mapping.
String adminError(Object e) => switch (e) {
      PostgrestException(code: '23505', :final message) when message.contains('slug') =>
        'Another product already uses this slug. Change it and save again.',
      PostgrestException(code: '23505', :final message) when message.contains('sku') =>
        'Another variant already uses this SKU.',
      PostgrestException(code: '23505') => 'That’s already in use. Pick a different value.',
      PostgrestException(code: '23514') => 'One of the values isn’t allowed. Check the form and try again.',
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
    final tracking = _tracking.text.trim();
    Navigator.pop(context, (courier: _courier.text.trim(), tracking: tracking.isEmpty ? null : tracking));
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
            maxLength: 60,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the courier' : null,
          ),
          const SizedBox(height: Space.sm),
          TextFormField(
            controller: _tracking,
            decoration: const InputDecoration(labelText: 'Tracking number (optional)'),
            maxLength: 60,
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
