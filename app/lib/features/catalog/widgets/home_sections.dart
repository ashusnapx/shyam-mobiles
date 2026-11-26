import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart' show currentUserIdProvider;
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/widgets.dart';
import '../../cart/data/cart.dart';
import '../../exchange/widgets/exchange_widgets.dart' show showExchangeSheet;
import '../../offers/data/auto_apply.dart' show bestAutoApply;
import '../../offers/data/offers.dart';
import '../../offers/widgets/offer_widgets.dart' show copyCode, offerHeadline, timeLeft;

/// The search hint cycles through what the shop sells, every 3 s, so the field reads as "you can find it here".
/// Still with reduce-motion on.
class RotatingSearchHint extends StatefulWidget {
  const RotatingSearchHint({super.key, required this.style});

  final TextStyle? style;

  static const words = ['phones', 'earbuds', 'chargers', 'back covers', 'power banks', 'screen guards'];

  @override
  State<RotatingSearchHint> createState() => _RotatingSearchHintState();
}

class _RotatingSearchHintState extends State<RotatingSearchHint> {
  Timer? _timer;
  int _i = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    _timer = MediaQuery.disableAnimationsOf(context)
        ? null
        : Timer.periodic(const Duration(seconds: 3), (_) {
            // another tab is showing: skip the frame, the word changes when Home is back
            if (mounted && TickerMode.valuesOf(context).enabled) {
              setState(() => _i = (_i + 1) % RotatingSearchHint.words.length);
            }
          });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text('Search ', style: widget.style),
          Expanded(
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: Motion.normal,
                layoutBuilder: (current, previous) =>
                    Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                transitionBuilder: (child, a) => SlideTransition(
                  position: Tween(begin: const Offset(0, 0.8), end: Offset.zero)
                      .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
                  child: FadeTransition(opacity: a, child: child),
                ),
                child: Text(
                  '“${RotatingSearchHint.words[_i]}”',
                  key: ValueKey(_i),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: widget.style?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      );
}

/// "Complete your order": the signed-in customer's cart, back on Home: up to three photos, the count and the total,
/// and Checkout. Nothing when the cart is empty, signed out, loading or failing.
class CartNudge extends ConsumerWidget {
  const CartNudge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = [for (final l in ref.watch(cartProvider).value ?? const <CartLine>[]) if (l.purchasable) l];
    if (lines.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final count = lines.fold(0, (n, l) => n + l.qty);
    final total = lines.fold(0, (n, l) => n + l.lineTotalPaise);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
      child: Material(
        color: BrandColors.peacockMist,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: InkWell(
          onTap: () => context.go('/cart'),
          borderRadius: BorderRadius.circular(Radii.lg),
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              children: [
                for (final l in lines.take(2))
                  Padding(
                    padding: const EdgeInsets.only(right: Space.xs),
                    child: SizedBox.square(
                      dimension: 44,
                      child: ProductImage(l.coverPath, radius: Radii.md, padding: Space.xs),
                    ),
                  ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Complete your order',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(color: BrandColors.peacockInk)),
                      Text('$count ${count == 1 ? 'item' : 'items'} · ${formatInr(total)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                FilledButton(
                  onPressed: () => context.go('/cart'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.peacock,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  ),
                  child: const Text('Checkout'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The coupon codes running now, as tickets in a row: the saving big on the left, the code on the right. A tap applies
/// the code (the cart shows whether it fits) and says so. The auto-applied occasion offer has its own chip above.
class CouponTickets extends ConsumerWidget {
  const CouponTickets({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(availableOffersProvider).value ?? const <Offer>[];
    final auto = bestAutoApply(offers, DateTime.now())?.id;
    final coded = [for (final o in offers) if (o.code != null && o.id != auto) o].take(6).toList();
    if (coded.isEmpty) return const SizedBox.shrink();
    final applied = ref.watch(couponCodeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Coupons for you', gutter: Space.gutter, onSeeAll: () => context.push('/offers')),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Row(
            spacing: Space.md,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final o in coded)
                _Ticket(o, applied: applied == o.code, onTap: () {
                  // signed out, the code would be dropped at sign-in (couponCodeProvider): copy it instead
                  if (ref.read(currentUserIdProvider) == null) return unawaited(copyCode(context, o.code!));
                  ref.read(couponCodeProvider.notifier).set(o.code);
                  showMessage(context, '${o.code} applied. It comes off at checkout.');
                }),
            ],
          ),
        ),
      ],
    );
  }
}

class _Ticket extends StatelessWidget {
  const _Ticket(this.offer, {required this.applied, required this.onTap});

  final Offer offer;
  final bool applied;
  final VoidCallback onTap;

  static const width = 248.0, height = 92.0, stub = 96.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final left = timeLeft(offer.endsAt);
    final min = offer.minSubtotalPaise > 0 ? 'On ${formatInr(offer.minSubtotalPaise)}+' : 'No minimum';
    return Semantics(
      button: true,
      label: '${offerHeadline(offer)}, code ${offer.code}, ${applied ? 'applied' : 'tap to apply'}',
      excludeSemantics: true,
      child: Pressable(
        child: GestureDetector(
          onTap: onTap,
          child: ClipPath(
            clipper: const _TicketClipper(stub: stub),
            child: SizedBox(
              width: width,
              height: height,
              child: Row(
                children: [
                  // the stub: the saving, on gold
                  Container(
                    width: stub,
                    color: BrandColors.gold,
                    padding: const EdgeInsets.all(Space.sm),
                    alignment: Alignment.center,
                    child: Text(
                      offerHeadline(offer).toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium?.copyWith(color: BrandColors.goldInk, fontWeight: FontWeight.w800, height: 1.1),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: BrandColors.amberMist,
                      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.sm, Space.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(offer.code!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall?.copyWith(color: BrandColors.goldInk, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                          Text([min, ?left].join(' · '),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: BrandColors.amber)),
                          const SizedBox(height: Space.xs),
                          Row(
                            spacing: Space.xs,
                            children: [
                              Icon(applied ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.tag,
                                  size: IconSizes.sm, color: applied ? BrandColors.emerald : BrandColors.amber),
                              Text(applied ? 'Applied' : 'Tap to apply',
                                  style: t.labelMedium?.copyWith(color: applied ? BrandColors.emerald : BrandColors.amber)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ticket: rounded corners and a half-circle notch top and bottom where the stub tears off.
class _TicketClipper extends CustomClipper<Path> {
  const _TicketClipper({required this.stub});

  final double stub;

  @override
  Path getClip(Size size) {
    const notch = 7.0;
    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Radii.md)));
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(stub, 0), radius: notch))
      ..addOval(Rect.fromCircle(center: Offset(stub, size.height), radius: notch));
    return Path.combine(PathOperation.difference, body, holes);
  }

  @override
  bool shouldReclip(_TicketClipper old) => old.stub != stub;
}

/// "Shop by budget": price tiles, phones on one row and accessories on the next, each opening Search at that price.
class BudgetTiles extends StatelessWidget {
  const BudgetTiles(this.phoneCategory, {super.key});

  final String phoneCategory;

  static const _phones = [
    ('Under', '₹10,000', 'max=1000000'),
    ('Under', '₹15,000', 'max=1500000'),
    ('Under', '₹25,000', 'max=2500000'),
    ('Premium', '₹25,000+', 'min=2500000'),
  ];
  static const _accessories = [
    ('Under', '₹299', 'max=29900'),
    ('Under', '₹499', 'max=49900'),
    ('Under', '₹999', 'max=99900'),
    ('Under', '₹1,999', 'max=199900'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget row(String label, List<(String, String, String)> bands, Tint tint, String? category) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.sm),
              child: Text(label, style: t.labelLarge?.copyWith(color: tint.$2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Row(
                spacing: Space.sm,
                children: [
                  for (final (kicker, price, q) in bands)
                    Expanded(
                      child: Pressable(
                        child: Material(
                          color: tint.$1,
                          borderRadius: BorderRadius.circular(Radii.md),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(Radii.md),
                            onTap: () => context.go('/search?${category == null ? '' : 'category=$category&'}$q'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: Space.md, horizontal: Space.xs),
                              child: Column(
                                children: [
                                  Text(kicker, style: t.labelSmall?.copyWith(color: tint.$2)),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(price,
                                        maxLines: 1,
                                        style: t.titleMedium?.copyWith(color: tint.$2, fontWeight: FontWeight.w800)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Shop by budget', gutter: Space.gutter),
        row('Phones', _phones, (BrandColors.indigoMist, BrandColors.indigoInk), phoneCategory),
        row('Accessories', _accessories, (BrandColors.plumMist, BrandColors.plumInk), null),
      ],
    );
  }
}

/// Exchange and Repairs side by side: the two services that bring people to the shop, each a tap from its form.
class ServiceTiles extends StatelessWidget {
  const ServiceTiles({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.section, Space.gutter, 0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              Expanded(
                child: _ServiceTile(
                  icon: PhosphorIconsFill.arrowsClockwise,
                  title: 'Exchange',
                  line: 'Old phone in, new one out. Get a price now.',
                  action: 'Get estimate',
                  tint: (BrandColors.mint, BrandColors.mintInk),
                  onTap: () => showExchangeSheet(context),
                ),
              ),
              Expanded(
                child: _ServiceTile(
                  icon: PhosphorIconsFill.wrench,
                  title: 'Repair',
                  line: 'Screen, battery, port. You approve the price first.',
                  action: 'Book free',
                  tint: (BrandColors.cream, BrandColors.creamInk),
                  onTap: () => context.push('/repairs/new'),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.icon,
    required this.title,
    required this.line,
    required this.action,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String title, line, action;
  final Tint tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Pressable(
      child: Material(
        color: tint.$1,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.lg),
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconWell(icon, tint: (Colors.white, tint.$2), size: 36),
                const SizedBox(height: Space.sm),
                Text(title, style: t.titleSmall?.copyWith(color: tint.$2, fontWeight: FontWeight.w700)),
                Text(line, style: t.bodySmall?.copyWith(color: tint.$2)),
                const Spacer(),
                const SizedBox(height: Space.sm),
                Row(
                  spacing: Space.xs,
                  children: [
                    Text(action, style: t.labelLarge?.copyWith(color: tint.$2)),
                    Icon(PhosphorIconsBold.arrowRight, size: IconSizes.sm, color: tint.$2),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
