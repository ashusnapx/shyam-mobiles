import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/widgets/widgets.dart';
import '../data/cart.dart';

/// The cart in the top bar of pushed shopping screens (they have no bottom nav): the gold count, a pop when it
/// rises, and the shell's Cart tab.
class CartButton extends ConsumerStatefulWidget {
  const CartButton({super.key, this.style});

  final ButtonStyle? style; // the product page's white circle over the photo

  @override
  ConsumerState<CartButton> createState() => _CartButtonState();
}

class _CartButtonState extends ConsumerState<CartButton> {
  int _rises = 0;

  @override
  Widget build(BuildContext context) {
    final n = ref.watch(cartCountProvider);
    ref.listen(cartCountProvider, (was, now) {
      if (now > (was ?? now)) setState(() => _rises++);
    });
    return IconButton(
      tooltip: n > 0 ? 'Cart, $n items' : 'Cart',
      style: widget.style,
      onPressed: () => context.go('/cart'),
      icon: Bump(
        trigger: _rises,
        child: Badge(
          isLabelVisible: n > 0,
          label: Text('$n'),
          child: const Icon(PhosphorIconsRegular.shoppingBag, size: 20),
        ),
      ),
    );
  }
}
