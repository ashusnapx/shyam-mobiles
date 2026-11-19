import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/widgets.dart';
import '../../catalog/data/hero.dart';
import 'offer_widgets.dart';

/// One solid, rich tone per banner (palette v2's deep shades): the banner's tone index (0..5, as the admin sets it)
/// picks it. White text, the 18% kicker pill and the product-side light all stay 4.5:1 on each (hero_card_test).
const heroTones = [
  BrandColors.peacockDeep,
  BrandColors.goldInk,
  BrandColors.emeraldDeep,
  BrandColors.plumDeep,
  BrandColors.indigoDeep,
  BrandColors.oceanDeep,
];

Color heroTone(int i) => heroTones[i.abs() % heroTones.length];

/// What a product slide shows under its title: "₹74,999  ₹80,999  [Save ₹6,000]".
typedef HeroPrice = ({String price, String? mrp, String? save});

/// The Home hero card, Apple Store style: one image, little text, one action. A fixed [height] solid tone with one
/// soft light behind the product; the text on the left (kicker pill, title, one value line, CTA), the [visual] on the
/// right, clipped by the card. No panel, no blur. The whole card opens [onTap]; the CTA runs [onCta] (default [onTap]).
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.tone,
    required this.title,
    required this.cta,
    required this.visual,
    required this.onTap,
    required this.semanticsLabel,
    this.kicker = 'OFFER',
    this.endsAt,
    this.valueLine,
    this.price,
    this.onCta,
  });

  static const height = 196.0;

  final Color tone;
  final String title;
  final String cta;
  final Widget visual;
  final VoidCallback onTap;
  final VoidCallback? onCta;
  final String semanticsLabel;
  final String kicker;
  final DateTime? endsAt; // a countdown replaces the kicker
  final String? valueLine; // one short line: an offer's benefit
  final HeroPrice? price; // a product's price line, instead of [valueLine]

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // shortcut: text is capped at 1.4x inside the card so the fixed 196 dp never overflows; lift it with the height
    final scaler = mq.textScaler.clamp(maxScaleFactor: 1.4);
    final lines = scaler.scale(10) > 10.5
        ? 1
        : 2; // a second title line only at normal text size
    final t = Theme.of(context).textTheme;
    const white = Colors.white;
    final kickerStyle = t.labelSmall?.copyWith(
      color: white,
      fontSize: 11,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    final live = endsAt != null && endsAt!.isAfter(DateTime.now());
    final value = price != null
        ? _priceLine(t, price!)
        : valueLine == null
        ? null
        : Text(
            valueLine!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodyMedium?.copyWith(
              color: white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          );
    return MediaQuery(
      data: mq.copyWith(textScaler: scaler),
      child: Pressable(
        child: Semantics(
          button: true,
          label: semanticsLabel,
          onTap: onCta ?? onTap,
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.xl),
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: tone)),
                  // the one soft light, behind the product
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0.62, 0.05),
                          radius: 0.9,
                          colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(onTap: onTap),
                    ),
                  ),
                  Positioned.fill(child: IgnorePointer(child: visual)),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.lg,
                        0,
                        Space.md,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 56,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // a tap on the words opens the card too
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: onTap,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: white.withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(
                                            Radii.lg,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: Space.sm + 2,
                                            vertical: Space.xs,
                                          ),
                                          child: live
                                              ? Countdown(
                                                  endsAt!,
                                                  style: kickerStyle,
                                                  caps: true,
                                                )
                                              : Text(
                                                  kicker.toUpperCase(),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: kickerStyle,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: Space.sm - 2),
                                      Semantics(
                                        header: true,
                                        child: Text(
                                          title,
                                          maxLines: lines,
                                          overflow: TextOverflow.ellipsis,
                                          style: t.displaySmall?.copyWith(
                                            color: white,
                                            fontSize: 24,
                                            height: 1.1,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ),
                                      if (value != null) ...[
                                        const SizedBox(height: Space.xs),
                                        value,
                                      ],
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                FilledButton(
                                  onPressed: onCta ?? onTap,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: white,
                                    foregroundColor: BrandColors.ink,
                                    minimumSize: const Size(0, 40),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: Space.lg,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        Radii.md,
                                      ),
                                    ),
                                    tapTargetSize: MaterialTapTargetSize
                                        .padded, // 40 dp drawn, 48 dp to touch
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    spacing: Space.xs + 2,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          cta,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(
                                        PhosphorIconsBold.arrowRight,
                                        size: IconSizes.sm,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(flex: 44),
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

  /// One line whatever the width: it shrinks before it wraps.
  Widget _priceLine(TextTheme t, HeroPrice p) {
    const white = Colors.white;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          Text(
            p.price,
            maxLines: 1,
            style: t.titleLarge?.copyWith(
              color: white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          if (p.mrp != null)
            Text(
              p.mrp!,
              maxLines: 1,
              style: t.bodySmall?.copyWith(
                color: white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.2,
                decoration: TextDecoration.lineThrough,
                decorationColor: white.withValues(alpha: 0.7),
              ),
            ),
          if (p.save != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm - 2,
                  vertical: 2,
                ),
                child: Text(
                  p.save!,
                  maxLines: 1,
                  style: t.labelSmall?.copyWith(
                    color: white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The right 44% of a [HeroCard]: one product cut-out large (120% of the card's height, bottom-anchored, bleeding off
/// the bottom and right edges, tilted -6°, on a soft ground shadow), a fan of up to three, or one big [icon] in a
/// 96 dp tinted circle. Fan items after the first sit behind it, left then right.
class HeroVisual extends StatelessWidget {
  const HeroVisual({
    super.key,
    this.items = const [],
    this.icon = PhosphorIconsFill.sealPercent,
    this.photo = true,
  });

  final List<HeroItem> items;
  final IconData icon; // when there is nothing to show
  final bool photo; // false for the carousel's off-screen copies in data-saver mode: nothing downloaded

  static const _tilt = -6 * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Align(
        alignment: const Alignment(0.62, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 96,
            child: Icon(icon, size: 48, color: Colors.white),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        const h = HeroCard.height;
        Widget cut(HeroItem i, {bool zoom = false}) {
          final c = Opacity(
            opacity: i.opacity,
            child: ProductCutout(photo ? i.path : null),
          );
          return zoom ? c.slowZoom(context) : c;
        }

        Widget placed(
          HeroItem i, {
          required double centre,
          required double width,
          required double height,
          required double bottom,
          required double angle,
          bool zoom = false,
        }) => Positioned(
          left: centre * w - width / 2,
          bottom: bottom,
          width: width,
          height: height,
          child: Transform.rotate(
            angle: angle,
            child: cut(i, zoom: zoom),
          ),
        );

        final lead = items.first;
        final (centre, width, height) = items.length == 1
            ? (0.78, w * 0.5, h * 1.2)
            : (0.76, w * 0.42, h * 1.05);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // the ground shadow, soft, under the lead product
            Positioned(
              left: centre * w - w * 0.16,
              bottom: 12,
              width: w * 0.32,
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(
                    Radius.elliptical(60, 6),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 16,
                    ),
                  ],
                ),
              ),
            ),
            // behind the lead: the second to its left, the third to its right
            if (items.length > 1)
              placed(
                items[1],
                centre: 0.56,
                width: w * 0.34,
                height: h * 0.85,
                bottom: -8,
                angle: -14 * math.pi / 180,
              ),
            if (items.length > 2)
              placed(
                items[2],
                centre: 0.97,
                width: w * 0.34,
                height: h * 0.85,
                bottom: -8,
                angle: 8 * math.pi / 180,
              ),
            placed(
              lead,
              centre: centre,
              width: width,
              height: height,
              bottom: items.length == 1 ? -20 : -14,
              angle: _tilt,
              zoom: true,
            ),
          ],
        );
      },
    );
  }
}

/// "5% off · up to ₹2,000": an offer's benefit on one line; without its offer, the banner's own first line.
String? heroValueLine(PromoBanner b, Offer? o) {
  if (o != null) {
    return [
      offerHeadline(o),
      if (o.kind == OfferKind.percent && o.maxDiscountPaise != null)
        'up to ${formatInr(o.maxDiscountPaise!)}',
    ].join(' · ');
  }
  final s = b.subtitle.trim().split('\n').first.trim();
  return s.isEmpty ? null : s;
}

/// An offer, exchange or repair banner on a [HeroCard]. A photo set on the banner is its picture; without one, a fan of
/// in-stock products from [pool] ([offer] a pack: phone, guard, case; [fan] overrides), else a big [icon].
class PromoBannerCard extends StatelessWidget {
  const PromoBannerCard(
    this.banner, {
    super.key,
    this.onTap,
    this.offer,
    this.pool = const [],
    this.fan,
    this.icon = PhosphorIconsFill.sealPercent,
    this.kicker = 'OFFER',
    this.photo = true,
  });

  final PromoBanner banner;
  final VoidCallback? onTap;
  final Offer?
  offer; // the offer this banner was made from, for its benefit line
  final Iterable<ProductCard> pool;
  final HeroFan? fan;
  final IconData icon;
  final String kicker;
  final bool photo;

  @override
  Widget build(BuildContext context) {
    final cta = heroCta(banner.ctaLabel);
    final items = banner.imagePath != null
        ? [(path: banner.imagePath, opacity: 1.0)]
        : heroFan(
            fan ??
                (offer?.kind == OfferKind.pack ? HeroFan.pack : HeroFan.offer),
            pool,
          );
    return HeroCard(
      tone: heroTone(banner.tone),
      kicker: kicker,
      endsAt: banner.endsAt,
      title: banner.title,
      valueLine: heroValueLine(banner, offer),
      cta: cta,
      onTap: onTap ?? () {},
      visual: HeroVisual(items: items, icon: icon, photo: photo),
      semanticsLabel: heroLabel(
        kicker == 'OFFER' ? 'Offer' : _sentence(kicker),
        banner.title,
        cta,
        endsAt: banner.endsAt,
      ),
    );
  }
}

String _sentence(String caps) =>
    caps.isEmpty ? caps : caps[0] + caps.substring(1).toLowerCase();
