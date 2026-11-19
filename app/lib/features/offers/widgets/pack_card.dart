import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../cart/data/cart.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/variant_options.dart';
import '../../catalog/screens/product_screen.dart' show leadLine;
import '../data/packs.dart';

/// "Complete your pack": the phone and one fitting item per type the pack asks for, each swappable, the pack price
/// and what the pack saves. Nothing is added until "Add pack to cart" (no pre-ticked or auto-added items).
/// [phoneVariant]: the phone's variant (the product page's pick, or the cart line); added unless it's in [inCart].
/// [inCart]: product ids already in the cart; they count toward the pack and aren't added again.
class CompletePackCard extends ConsumerStatefulWidget {
  const CompletePackCard({super.key, required this.pack, this.phoneVariant, this.inCart = const {}});

  final Pack pack;
  final Variant? phoneVariant;
  final Set<String> inCart;

  @override
  ConsumerState<CompletePackCard> createState() => _CompletePackCardState();
}

class _CompletePackCardState extends ConsumerState<CompletePackCard> {
  late List<PackItem> _items = [...widget.pack.items];
  bool _busy = false;

  @override
  void didUpdateWidget(CompletePackCard old) {
    super.didUpdateWidget(old);
    if (old.pack != widget.pack) _items = [...widget.pack.items];
  }

  Future<void> _swap(int i) async {
    final choices = widget.pack.choices[_items[i].type]!;
    final picked = await showModalBottomSheet<PackItem>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in choices)
              ListTile(
                title: Text(c.card.name),
                subtitle: Text(c.forModel == null ? 'In stock' : leadLine(c.card.leadDays ?? 2)),
                trailing: Text(formatInr(c.card.minPricePaise)),
                selected: c.card.id == _items[i].card.id,
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _items[i] = picked);
  }

  Future<void> _add() async {
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    try {
      final cart = ref.read(cartProvider.notifier);
      final repo = ref.read(catalogRepositoryProvider);
      if (widget.phoneVariant case final v? when !widget.inCart.contains(widget.pack.phone.id)) await cart.add(v);
      for (final item in _items) {
        if (widget.inCart.contains(item.card.id)) continue;
        final variants = (await repo.product(item.card.slug))?.activeVariants ?? const <Variant>[];
        final v = item.forModel != null ? variants.where((v) => v.madeToOrder).firstOrNull : initialVariant(variants);
        if (v == null || !v.inStock) throw const FormatException('Something in this pack just sold out. Pick another.');
        await cart.add(v, forModel: item.forModel);
      }
      unawaited(HapticFeedback.mediumImpact());
      if (mounted) {
        showMessage(
          context,
          'Pack added to cart',
          action: SnackBarAction(label: 'View cart', onPressed: () => router.push('/bag')),
        );
      }
    } catch (e) {
      if (mounted) showMessage(context, e is FormatException ? e.message : friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final pack = widget.pack;
    final phonePaise = widget.phoneVariant?.pricePaise ?? initialVariant(pack.phone.activeVariants)?.pricePaise ?? 0;
    final accessories = _items.fold(0, (sum, i) => sum + i.card.minPricePaise);
    final saving = pack.offer.savingPaise(phonePaise, accessories);
    final muted = t.bodySmall?.copyWith(color: c.onSurfaceVariant);
    Widget row({required String title, required String subtitle, required int paise, VoidCallback? onChange}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(subtitle, style: muted),
                  ],
                ),
              ),
              Text(formatInr(paise), style: t.titleSmall),
              if (onChange != null)
                TextButton(onPressed: onChange, child: const Text('Change'))
              else
                const SizedBox(width: Space.sm),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.md),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              spacing: Space.sm,
              children: [
                const Icon(PhosphorIconsRegular.package, color: BrandColors.peacockInk),
                Expanded(
                  child: Text('Complete your pack', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            Text(
              '${pack.offer.title}: ${pack.offer.percent}% off ${pack.offer.whole ? 'the whole pack' : 'the accessories'} '
              'when you buy them together.',
              style: muted,
            ),
            const Divider(),
            row(
              title: pack.phone.name,
              subtitle: widget.inCart.contains(pack.phone.id) ? 'In your cart' : 'This phone',
              paise: phonePaise,
            ),
            for (final (i, item) in _items.indexed)
              row(
                title: item.card.name,
                subtitle: [
                  item.type.label,
                  if (widget.inCart.contains(item.card.id)) 'In your cart',
                  if (item.forModel != null)
                    'For ${item.forModel} · ${leadLine(item.card.leadDays ?? 2).toLowerCase()}',
                ].join(' · '),
                paise: item.card.minPricePaise,
                onChange: pack.choices[item.type]!.length > 1 ? () => _swap(i) : null,
              ),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('Pack price', style: t.titleSmall)),
                Text(
                  formatInr(phonePaise + accessories - saving),
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            if (saving > 0)
              Align(
                alignment: Alignment.centerRight,
                child: Tag('Save ${pack.offer.percent}% (${formatInr(saving)})', tone: TagTone.deal),
              ),
            const SizedBox(height: Space.sm),
            FilledButton.icon(
              onPressed: _busy ? null : _add,
              icon: const Icon(PhosphorIconsRegular.shoppingBagOpen),
              label: const Text('Add pack to cart'),
            ),
            Text(
              'The final price is worked out at checkout. One offer per order: you always get the bigger saving.',
              style: muted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
