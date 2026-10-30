import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../admin/widgets/admin_widgets.dart';
import '../../repairs/widgets/repair_widgets.dart';
import '../data/payments.dart';

/// Staff: Razorpay payment links for wholesale and phone orders (a typed amount) and for app orders, newest first.
/// A new link opens WhatsApp to the customer with the link in the message.
class AdminPaymentLinksScreen extends ConsumerWidget {
  const AdminPaymentLinksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.watch(paymentLinksProvider);
    return AdminGate(
      child: Scaffold(
        appBar: AppBar(title: const Text('Payment links')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (_) => const _NewLinkSheet(),
          ),
          icon: const Icon(PhosphorIconsRegular.plus),
          label: const Text('New link'),
        ),
        body: AsyncBody<List<PaymentLink>>(
          value: links,
          onRetry: () => ref.invalidate(paymentLinksProvider),
          loading: const Center(child: CircularProgressIndicator()),
          data: (list) => RefreshIndicator(
            onRefresh: () => ref.refresh(paymentLinksProvider.future),
            child: list.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      EmptyState(
                        icon: PhosphorIconsRegular.link,
                        title: 'No payment links yet',
                        message: 'Make one for a wholesale or phone order and send it on WhatsApp.',
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(bottom: 96 + MediaQuery.paddingOf(context).bottom),
                    children: [for (final l in list) _LinkTile(link: l)],
                  ),
          ),
        ),
      ),
    );
  }
}

class _LinkTile extends ConsumerWidget {
  const _LinkTile({required this.link});

  final PaymentLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = link;
    return ListTile(
      title: Text('${formatInr(l.amountPaise)} · ${l.customerName ?? displayPhone(l.customerPhone)}'),
      subtitle: Text('${l.description}\n${l.statusLabel}'),
      isThreeLine: true,
      trailing: Tag(
        l.status == 'paid' ? 'Paid' : (l.isOpen ? 'Open' : l.statusLabel),
        tone: l.status == 'paid' ? TagTone.ok : (l.isOpen ? TagTone.deal : TagTone.info),
      ),
      onTap: l.orderId != null
          ? () => context.push('/admin/orders/${l.orderId}')
          : l.isOpen
              ? () => openUri(context, whatsAppUri(l.customerPhone, text: paymentLinkText(l)))
              : null,
    );
  }
}

class _NewLinkSheet extends ConsumerStatefulWidget {
  const _NewLinkSheet();

  @override
  ConsumerState<_NewLinkSheet> createState() => _NewLinkSheetState();
}

class _NewLinkSheetState extends ConsumerState<_NewLinkSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _what = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_amount, _phone, _name, _what]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await createPaymentLink(
        ref,
        amountPaise: int.parse(_amount.text) * 100,
        phone: normalizeIndianPhone(_phone.text),
        name: tidy(_name.text).isEmpty ? null : tidy(_name.text),
        description: tidy(_what.text),
      );
      if (!mounted) return;
      Navigator.pop(context);
      await openUri(context, whatsAppUri(link.customerPhone, text: paymentLinkText(link)));
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetForm(
        formKey: _form,
        title: 'New payment link',
        children: [
          TextFormField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
            validator: (v) {
              final n = int.tryParse(v ?? '') ?? 0;
              return n < 1 || n > 5000000 ? '₹1 to ₹50,00,000' : null;
            },
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Customer’s mobile number', prefixText: '+91 '),
            keyboardType: TextInputType.phone,
            inputFormatters: const [DigitsFormatter(10)],
            validator: (v) => normalizeIndianPhone(v ?? '') == null ? 'A 10-digit mobile number' : null,
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name (optional)'),
            textCapitalization: TextCapitalization.words,
            inputFormatters: textInput(60),
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _what,
            decoration: const InputDecoration(labelText: 'What it’s for', hintText: 'e.g. 10 × Redmi 13C, wholesale'),
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: textInput(200),
            validator: (v) => tidy(v ?? '').isEmpty ? 'Say what it’s for: the customer sees it' : null,
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Valid 3 days. Razorpay’s fee applies when it’s paid, as for any online payment.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: Space.md),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const WhatsAppIcon(),
            label: const Text('Make link and send on WhatsApp'),
          ),
        ],
      );
}
