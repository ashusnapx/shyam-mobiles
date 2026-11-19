import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/input.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../exchange/data/exchange_repository.dart';
import '../../exchange/data/exchanges.dart';
import '../../exchange/widgets/exchange_widgets.dart';
import '../data/rules.dart' show maxAmountPaise, parseRupees, rupeesError, rupeesText;
import '../widgets/admin_widgets.dart';

/// Staff: customers' old phones, newest first. Reply with a range; the customer is told it's an estimate and the
/// final value is set when the shop checks the phone (docs/GROWTH.md §2c).
class AdminExchangesScreen extends ConsumerWidget {
  const AdminExchangesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AdminGate(
        child: Scaffold(
          appBar: AppBar(title: const Text('Exchange requests')),
          body: AsyncBody<List<ExchangeRequest>>(
            value: ref.watch(adminExchangesProvider),
            onRetry: () => ref.invalidate(adminExchangesProvider),
            loading: const Center(child: CircularProgressIndicator()),
            data: (all) => all.isEmpty
                ? const EmptyState(icon: PhosphorIconsRegular.arrowsLeftRight, title: 'No exchange requests yet')
                : RefreshIndicator(
                    onRefresh: () => ref.refresh(adminExchangesProvider.future),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
                      children: [
                        for (final r in all)
                          ExchangeRequestCard(
                            r,
                            trailing: Wrap(
                              spacing: Space.sm,
                              children: [
                                for (final (i, p) in r.photos.indexed) _PhotoButton(p, i + 1),
                                FilledButton.tonal(
                                  onPressed: () => _estimate(context, ref, r),
                                  child: Text(r.estimated ? 'Change estimate' : 'Give estimate'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      );

  Future<void> _estimate(BuildContext context, WidgetRef ref, ExchangeRequest r) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EstimateSheet(request: r),
    );
    if (sent == true) {
      ref.invalidate(adminExchangesProvider);
      if (context.mounted) showMessage(context, 'Estimate sent to the customer');
    }
  }
}

class _PhotoButton extends ConsumerWidget {
  const _PhotoButton(this.path, this.n);

  final String path;
  final int n;

  @override
  Widget build(BuildContext context, WidgetRef ref) => OutlinedButton.icon(
        onPressed: () async {
          try {
            final bytes = await ref.read(exchangeRepositoryProvider).photo(path);
            if (!context.mounted || bytes == null) return;
            await showDialog<void>(context: context, builder: (_) => Dialog(child: Image.memory(bytes, fit: BoxFit.contain)));
          } catch (e) {
            if (context.mounted) showMessage(context, friendlyError(e));
          }
        },
        icon: const Icon(PhosphorIconsRegular.image, size: 18),
        label: Text('Photo $n'),
      );
}

class _EstimateSheet extends ConsumerStatefulWidget {
  const _EstimateSheet({required this.request});

  final ExchangeRequest request;

  @override
  ConsumerState<_EstimateSheet> createState() => _EstimateSheetState();
}

class _EstimateSheetState extends ConsumerState<_EstimateSheet> {
  final _form = GlobalKey<FormState>();
  late final _low = TextEditingController(text: widget.request.lowPaise == null ? '' : rupeesText(widget.request.lowPaise!));
  late final _high = TextEditingController(text: widget.request.highPaise == null ? '' : rupeesText(widget.request.highPaise!));
  late final _note = TextEditingController(text: widget.request.note);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _low.dispose();
    _high.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(exchangeRepositoryProvider).estimate(widget.request.id,
          lowPaise: parseRupees(_low.text)!, highPaise: parseRupees(_high.text)!, note: tidy(_note.text, multiline: true));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final r = widget.request;
    InputDecoration money(String label) => InputDecoration(labelText: label, prefixText: '₹ ');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg + MediaQuery.paddingOf(context).bottom),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              Semantics(header: true, child: Text('Estimate: ${r.brand} ${r.model}', style: t.titleLarge)),
              Text('${r.age.label} · ${r.condition.label}. Give a range; the customer sees it as an estimate.',
                  style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              TextFormField(
                controller: _low,
                decoration: money('From'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [RupeesFormatter(maxDigits: 7)],
                validator: (v) => rupeesError(v, maxPaise: maxAmountPaise),
              ),
              TextFormField(
                controller: _high,
                decoration: money('Up to'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [RupeesFormatter(maxDigits: 7)],
                validator: (v) => rupeesError(v, maxPaise: maxAmountPaise) ??
                    ((parseRupees(v!) ?? 0) < (parseRupees(_low.text) ?? 0) ? 'Keep it at or above the first amount.' : null),
              ),
              TextFormField(
                controller: _note,
                decoration: InputDecoration(labelText: 'Note for the customer (optional)', counter: LengthCounter(_note, 300)),
                maxLines: 3,
                inputFormatters: textInput(300, multiline: true),
              ),
              if (_error != null) Text(_error!, style: t.bodySmall?.copyWith(color: c.error)),
              FilledButton(
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send estimate'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
