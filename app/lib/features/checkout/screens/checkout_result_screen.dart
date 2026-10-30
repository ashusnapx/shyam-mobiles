import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../cart/data/cart.dart';
import '../../orders/data/orders.dart';
import '../data/payment.dart';
import 'widgets.dart';

enum ResultView { success, waiting, retry, expired, cancelled, refundDue }

/// What the result screen shows. While [polling], an unpaid order waits: the webhook may still confirm it.
ResultView resultView(Order o, {required bool polling}) {
  if (o.needsRefund) return ResultView.refundDue;
  return switch (o.status) {
    OrderStatus.pendingPayment =>
      polling
          ? ResultView.waiting
          : o.canRetryPayment
          ? ResultView.retry
          : ResultView.expired,
    OrderStatus.cancelled || OrderStatus.refunded => ResultView.cancelled,
    _ => ResultView.success,
  };
}

/// Outcomes after which money may still be moving (UPI apps report cancel while paying), so wait for the webhook.
const _maybeMoving = {PayOutcome.cancelled, PayOutcome.failed, PayOutcome.unknown, PayOutcome.unverified};

// Refunds are issued by staff in v1, so never promise "automatically".
const _notLost = 'If money left your account, it isn’t lost: we’ll confirm your order or refund it in full.';

class CheckoutResultScreen extends ConsumerStatefulWidget {
  const CheckoutResultScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<CheckoutResultScreen> createState() => _CheckoutResultScreenState();
}

class _CheckoutResultScreenState extends ConsumerState<CheckoutResultScreen> {
  static const _every = Duration(seconds: 3);
  static const _window = Duration(seconds: 30);

  Timer? _timer;
  bool _celebrated = false;

  bool get _polling => _timer?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _poll() {
    _timer?.cancel();
    _timer = Timer.periodic(_every, (t) {
      ref.invalidate(orderProvider(widget.orderId));
      if (_every * t.tick >= _window) {
        t.cancel();
        setState(() {});
      }
    });
  }

  Future<void> _retry() async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await ref.read(paymentFlowProvider.notifier).pay(widget.orderId);
    if (r == null || !mounted) return;
    if (r.message case final m?) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
    ref.invalidate(orderProvider(widget.orderId));
    if (_maybeMoving.contains(r.outcome)) setState(_poll);
  }

  Future<void> _reorder(Order o) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final added = await reorder(ref.read(supabaseProvider), ref.read(cartProvider.notifier), o);
      if (added < o.items.length) {
        messenger.showSnackBar(SnackBar(content: Text(added == 0 ? 'These items are out of stock now.' : 'Some items are out of stock now.')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
    router.go('/cart');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(orderProvider(widget.orderId), (_, next) {
      if (next.value case final o? when o.status != OrderStatus.pendingPayment) _timer?.cancel();
    });
    final async = ref.watch(orderProvider(widget.orderId));
    final stage = ref.watch(paymentFlowProvider);
    // A failed poll keeps the last good order on screen.
    final order = async.value;

    final Widget body;
    if (order != null) {
      final view = resultView(order, polling: _polling);
      if (view == ResultView.success && !_celebrated) {
        _celebrated = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => HapticFeedback.mediumImpact());
      }
      body = _view(view, order, stage);
    } else if (async.hasError) {
      body = ErrorView(error: async.error!, onRetry: () => ref.invalidate(orderProvider(widget.orderId)));
    } else {
      body = Skeletonizer(child: _view(ResultView.success, placeholderOrder, PayStage.idle));
    }

    return PopScope(
      canPop: false, // the stack below is the (now empty) checkout
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Close',
            onPressed: () => context.go('/'),
            icon: const Icon(PhosphorIconsRegular.x),
          ),
        ),
        body: body,
      ),
    );
  }

  Widget _view(ResultView view, Order o, PayStage stage) {
    final c = Theme.of(context).colorScheme;
    final total = formatInr(o.totalPaise);
    final viewOrder = OutlinedButton(onPressed: () => context.go('/orders/${o.id}'), child: const Text('View order'));
    final backToCart = FilledButton(onPressed: () => _reorder(o), child: const Text('Add items to cart again'));
    return switch (view) {
      ResultView.success => _Layout(
        // the feather's dots ripple out once, then the tick pops
        visual: Column(
          children: [
            const BrandMark(size: 48, ripple: true),
            const SizedBox(height: Space.lg),
            _Badge(icon: PhosphorIconsBold.check, bg: c.secondary, fg: c.onSecondary, animate: true),
          ],
        ),
        title: o.paymentMethod == PaymentMethod.cod ? 'Order placed' : 'Payment received',
        message: o.paymentMethod == PaymentMethod.cod
            ? 'Pay $total in cash when it arrives.'
            : 'Thank you. We’ll pack your order soon.',
        number: o.number,
        actions: [
          FilledButton(onPressed: () => context.go('/orders/${o.id}'), child: const Text('View order')),
          OutlinedButton(onPressed: () => context.go('/'), child: const Text('Continue shopping')),
        ],
      ),
      ResultView.waiting => _Layout(
        visual: SizedBox.square(
          dimension: 88,
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: CircularProgressIndicator(strokeWidth: 3, color: c.primary, semanticsLabel: 'Checking payment'),
          ),
        ),
        title: 'Waiting for payment',
        message: 'If you paid in your UPI app, this updates by itself. It can take up to 30 seconds. $_notLost',
        number: o.number,
        actions: [viewOrder],
      ),
      ResultView.retry => _Layout(
        visual: _Badge(icon: PhosphorIconsBold.clockCountdown, bg: c.tertiaryContainer, fg: c.onTertiaryContainer),
        title: 'Payment not finished',
        message:
            'We’re holding your items until ${DateFormat('h:mm a').format(o.reservedUntil!.toLocal())}. '
            'Pay now to confirm the order. $_notLost',
        number: o.number,
        actions: [
          FilledButton(
            onPressed: stage == PayStage.idle ? _retry : null,
            child: Text(
              stage == PayStage.idle ? 'Retry payment · $total' : stage.label,
              style: const TextStyle(fontFeatures: tabularFigures),
            ),
          ),
          viewOrder,
        ],
      ),
      ResultView.expired || ResultView.cancelled => _Layout(
        visual: _Badge(icon: PhosphorIconsBold.x, bg: c.errorContainer, fg: c.onErrorContainer),
        title: view == ResultView.expired ? 'Payment time ran out' : 'Order cancelled',
        message: view == ResultView.expired
            ? 'We couldn’t hold the items any longer, so this order won’t go through. Add them again to order.'
            : o.events.lastOrNull?.note ?? 'This order won’t go through.',
        number: o.number,
        actions: [backToCart, viewOrder],
      ),
      ResultView.refundDue => _Layout(
        visual: _Badge(
          icon: PhosphorIconsBold.arrowCounterClockwise,
          bg: c.tertiaryContainer,
          fg: c.onTertiaryContainer,
        ),
        title: 'Payment arrived late',
        message: 'The order had already closed, so the store will refund $total. Call us if you have questions.',
        number: o.number,
        actions: [
          FilledButton(onPressed: () => context.go('/orders/${o.id}'), child: const Text('View order')),
          OutlinedButton(onPressed: () => context.go('/'), child: const Text('Continue shopping')),
        ],
      ),
    };
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.bg, required this.fg, this.animate = false});

  final IconData icon;
  final Color bg;
  final Color fg;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final badge = DecoratedBox(
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Icon(icon, size: 40, color: fg),
      ),
    );
    if (!animate || MediaQuery.disableAnimationsOf(context)) return badge;
    return badge
        .animate()
        .fadeIn(duration: Motion.normal)
        .scaleXY(begin: 0.6, end: 1, duration: 450.ms, curve: Curves.easeOutBack);
  }
}

class _Layout extends StatelessWidget {
  const _Layout({
    required this.visual,
    required this.title,
    required this.message,
    required this.number,
    required this.actions,
  });

  final Widget visual;
  final String title;
  final String message;
  final String number;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: visual),
              const SizedBox(height: Space.xl),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(title, style: t.displaySmall, textAlign: TextAlign.center),
              ),
              const SizedBox(height: Space.sm),
              Text(
                message,
                style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.lg),
              Center(child: Tag('Order $number')),
              const SizedBox(height: Space.xxl),
              for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(height: Space.md), a],
            ],
          ),
        ),
      ),
    );
  }
}
