import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/input.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/widgets.dart';
import '../data/offers.dart';

/// "10% off", "₹500 off", "Free delivery". The offer as staff set it, not a computed saving.
String valueHeadline(OfferKind kind, int value) => switch (kind) {
      OfferKind.percent => '$value% off',
      OfferKind.flat => '${formatInr(value)} off',
      OfferKind.freeDelivery => 'Free delivery',
    };

String offerHeadline(Offer o) => valueHeadline(o.kind, o.value);

/// The fine print every offer has: minimum, cap, which products, how it applies.
List<String> offerTerms(Offer o) => [
      if (o.minSubtotalPaise > 0)
        o.wholeOrder
            ? 'On orders of ${formatInr(o.minSubtotalPaise)} or more'
            : 'When the offer’s items come to ${formatInr(o.minSubtotalPaise)} or more',
      if (o.kind == OfferKind.percent && o.maxDiscountPaise != null) 'Up to ${formatInr(o.maxDiscountPaise!)} off',
      if (!o.wholeOrder) 'Selected products only',
      if (o.firstOrderOnly) 'First order only',
      if (o.onlineOnly) 'Pay online to use it',
      if (o.automatic) 'Applied automatically at checkout',
    ];

/// "Ends in 45 min", "Ends in 5 h", "Ends in 3 days", "Till 5 Nov 2026"; null when the offer has no end.
String? timeLeft(DateTime? endsAt, {DateTime? now}) {
  if (endsAt == null) return null;
  final left = endsAt.difference(now ?? DateTime.now());
  if (left <= Duration.zero) return 'Ended';
  if (left.inHours < 1) return 'Ends in ${math.max(1, left.inMinutes)} min';
  if (left.inDays < 1) return 'Ends in ${left.inHours} h';
  if (left.inDays < 7) return 'Ends in ${left.inDays} day${left.inDays == 1 ? '' : 's'}';
  return 'Till ${formatDate(endsAt)}';
}

Future<void> copyCode(BuildContext context, String code) async {
  await Clipboard.setData(ClipboardData(text: code));
  if (context.mounted) showMessage(context, 'Code $code copied');
}

/// The snackbar after a code works, with the server's saving.
String appliedMessage(Quote q) {
  final name = q.discountLabel ?? 'Offer';
  return q.discountPaise > 0 ? '$name applied. You save ${formatInr(q.discountPaise)}.' : '$name applied: free delivery.';
}

/// An offer in the Offers list and the coupon sheet: what it gives, its terms, and the code to copy or apply.
class OfferCard extends StatelessWidget {
  const OfferCard(this.offer, {super.key, this.onApply, this.applied = false});

  final Offer offer;
  final VoidCallback? onApply; // null: no Apply button
  final bool applied;

  @override
  Widget build(BuildContext context) => Pressable(child: _card(context));

  Widget _card(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final left = timeLeft(offer.endsAt);
    final terms = offerTerms(offer);
    final muted = t.bodySmall?.copyWith(color: c.onSurfaceVariant);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/offers/${offer.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  Tag(offerHeadline(offer), tone: TagTone.deal, icon: PhosphorIconsBold.sealPercent),
                  if (left != null) Tag(left, icon: PhosphorIconsBold.clock),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(offer.title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (offer.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(offer.description, style: muted),
              ],
              if (terms.isNotEmpty) ...[
                const SizedBox(height: Space.xs),
                Text(terms.join(' · '), style: muted),
              ],
              const SizedBox(height: Space.md),
              if (offer.code case final code?)
                CodeActions(code: code, onApply: onApply, applied: applied)
              else
                const Tag('No code needed', tone: TagTone.ok, icon: PhosphorIconsBold.check),
            ],
          ),
        ),
      ),
    );
  }
}

/// The code in a dashed-look box, "Copy code" and (when given) "Apply".
class CodeActions extends StatelessWidget {
  const CodeActions({super.key, required this.code, this.onApply, this.applied = false});

  final String code;
  final VoidCallback? onApply;
  final bool applied;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceContainerLow,
            border: Border.all(color: c.outline),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            child: Text(code, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
        ),
        TextButton.icon(
          onPressed: () => copyCode(context, code),
          icon: const Icon(PhosphorIconsRegular.copy, size: 18),
          label: Text('Copy code', semanticsLabel: 'Copy code $code'),
        ),
        if (onApply != null || applied)
          FilledButton(
            onPressed: applied ? null : onApply,
            child: Text(applied ? 'Applied' : 'Apply', semanticsLabel: applied ? '$code applied' : 'Apply $code'),
          ),
      ],
    );
  }
}

/// The offer line in the cart and at checkout: "Apply a coupon", the applied code or sale and what it saves, or
/// why the code didn't work. Tapping opens the coupon sheet.
class CouponRow extends ConsumerWidget {
  const CouponRow({super.key, required this.quote, this.method, this.enabled = true});

  final Quote? quote; // null while the first quote loads
  final PaymentMethod? method;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final q = await showCouponSheet(context, method: method);
    if (q != null && context.mounted) {
      showMessage(context, q.couponError == 'COUPON_BETTER_OFFER' ? couponError(q.couponError!) : appliedMessage(q));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    final code = ref.watch(couponCodeProvider);
    final q = quote;
    final error = code == null ? null : q?.couponError;
    final promo = q?.promotion;
    final (icon, color, title, subtitle) = error != null
        ? (
            PhosphorIconsRegular.warningCircle,
            c.error,
            '$code can’t be used',
            couponError(error, minPaise: int.tryParse(q?.couponErrorDetail ?? '')),
          )
        : promo != null
            ? (
                PhosphorIconsFill.sealPercent,
                c.secondary,
                '${q!.discountLabel} applied',
                q.discountPaise > 0 ? 'You save ${formatInr(q.discountPaise)}' : 'Free delivery on this order',
              )
            : (PhosphorIconsRegular.ticket, null, 'Apply a coupon', 'Or pick one of today’s offers');
    return Card(
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: error == null && promo != null && q!.discountPaise > 0
            // the saving counts up when the code lands, and rolls when the cart changes it
            ? CountTo(
                q.discountPaise,
                format: (p) => 'You save ${formatInr(p)}',
                fromZero: true,
                style: TextStyle(color: color),
              )
            : Text(subtitle, style: color == null ? null : TextStyle(color: color)),
        trailing: code == null
            ? const Icon(PhosphorIconsRegular.caretRight, size: 18)
            : TextButton(
                onPressed: enabled ? () => ref.read(couponCodeProvider.notifier).set(null) : null,
                child: Text('Remove', semanticsLabel: 'Remove code $code'),
              ),
        onTap: () => _open(context),
      ),
    );
  }
}

/// "Apply coupon": type a code or pick a listed one. Each code is checked with `quote_order` first, so a refusal
/// shows here in plain words and only a code that works is applied. Pops with the new quote.
Future<Quote?> showCouponSheet(BuildContext context, {PaymentMethod? method}) => showModalBottomSheet<Quote>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CouponSheet(method: method),
    );

class CouponSheet extends ConsumerStatefulWidget {
  const CouponSheet({super.key, this.method});

  final PaymentMethod? method;

  @override
  ConsumerState<CouponSheet> createState() => _CouponSheetState();
}

class _CouponSheetState extends ConsumerState<CouponSheet> {
  late final _code = TextEditingController(text: ref.read(couponCodeProvider));
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply(String typed) async {
    if (_busy) return;
    final code = typed.trim();
    final invalid = validateCode(code);
    if (invalid != null) return setState(() => _error = invalid);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final q = await ref.read(offersApiProvider).quote(code: code, method: widget.method);
      if (!mounted) return;
      if (q.couponError case final e? when e != 'COUPON_BETTER_OFFER') {
        setState(() => _error = couponError(e, minPaise: int.tryParse(q.couponErrorDetail ?? '')));
        return;
      }
      // a running sale beats this code: keep the sale and leave the code unused for another order
      ref.read(couponCodeProvider.notifier).set(q.couponError == null ? code : null);
      Navigator.pop(context, q);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final offers = ref.watch(availableOffersProvider).value ?? const <Offer>[];
    final applied = ref.watch(couponCodeProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
              child: Semantics(header: true, child: Text('Apply coupon', style: t.titleLarge)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      decoration: InputDecoration(labelText: 'Coupon code', errorText: _error, errorMaxLines: 3),
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: couponCodeInput,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      onSubmitted: _apply,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: FilledButton(
                      onPressed: _busy ? null : () => _apply(_code.text),
                      child: _busy
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.lg),
                children: [
                  if (offers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: Text('Offers for you', style: t.titleSmall),
                    ),
                  for (final o in offers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: OfferCard(
                        o,
                        applied: o.code != null && o.code == applied,
                        onApply: o.code == null || _busy
                            ? null
                            : () {
                                _code.text = o.code!;
                                _apply(o.code!);
                              },
                      ),
                    ),
                  TextButton(
                    onPressed: () {
                      final router = GoRouter.of(context);
                      Navigator.pop(context);
                      router.push('/offers');
                    },
                    child: const Text('See all offers'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a vetted banner link ([isBannerLink]): Search and Repairs are tabs, so those switch tab; the rest push.
void openAppLink(BuildContext context, String link) {
  if (link.startsWith('/search') || link.startsWith('/repairs')) {
    context.go(link);
  } else {
    context.push(link);
  }
}

/// One home banner on a [heroGradients] tone (white text passes AA on every stop), with its photo when set.
class PromoBannerCard extends StatelessWidget {
  const PromoBannerCard(this.banner, {super.key, this.onTap});

  final PromoBanner banner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(child: _card(context));

  Widget _card(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final colors = heroGradients[banner.tone.clamp(0, heroGradients.length - 1)];
    return MergeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14), // compact: it's a slide in Home's carousel
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            banner.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                          if (banner.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              banner.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                            ),
                          ],
                          const SizedBox(height: 10),
                          // looks like the product slides' white button; the whole card is the tap target
                          DecoratedBox(
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 5),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: Space.xs,
                                children: [
                                  Flexible(
                                    child: Text(banner.ctaLabel, style: t.labelMedium?.copyWith(color: colors.first)),
                                  ),
                                  Icon(PhosphorIconsBold.arrowRight, size: 14, color: colors.first),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (banner.imagePath != null) ...[
                      const SizedBox(width: Space.md),
                      SizedBox(
                        width: 76,
                        child: ProductImage(banner.imagePath, radius: Radii.md, padding: 0, fit: BoxFit.cover),
                      ),
                    ],
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
