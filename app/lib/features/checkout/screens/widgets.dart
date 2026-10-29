import 'package:material_ui/material_ui.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';

const tabularFigures = [FontFeature.tabularFigures()];

/// Subtotal / delivery / total rows. Pass the server's total for placed orders.
class TotalsRows extends StatelessWidget {
  const TotalsRows({
    super.key,
    required this.subtotalPaise,
    required this.deliveryFeePaise,
    required this.totalPaise,
    this.totalLabel = 'Total',
  });

  final int subtotalPaise;
  final int deliveryFeePaise;
  final int totalPaise;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    Widget row(String label, Widget value, {bool total = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: total ? t.titleMedium?.copyWith(fontWeight: FontWeight.w800) : t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                ),
              ),
              value,
            ],
          ),
        );
    Text money(int paise, {bool total = false}) => Text(
          formatInr(paise),
          style: (total ? t.titleMedium?.copyWith(fontWeight: FontWeight.w800) : t.bodyMedium)
              ?.copyWith(fontFeatures: tabularFigures),
        );
    return Column(
      children: [
        row('Subtotal', money(subtotalPaise)),
        row(
          'Delivery',
          deliveryFeePaise == 0
              ? Text('Free', style: t.bodyMedium?.copyWith(color: c.secondary, fontWeight: FontWeight.w700))
              : money(deliveryFeePaise),
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: Space.xs), child: Divider()),
        row(totalLabel, money(totalPaise, total: true), total: true),
      ],
    );
  }
}
