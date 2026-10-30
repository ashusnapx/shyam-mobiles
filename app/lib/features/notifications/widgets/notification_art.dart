import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/supabase.dart';
import '../../../core/theme/generative.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/notifications.dart';

// One small illustration per kind of notification: a soft aurora in its group's colours, a large two-tone icon for
// the event, and a status badge in the corner. The same art is a PNG in assets/notification_art/ for Android's
// notifications (rendered by test/preview/notification_art_test.dart).

/// Seeds picked so the eight groups land on distinct hues: teal, green, saffron, gold, blue, orange, violet, rose.
enum ArtGroup {
  orders('orders1'),
  payments('payments71'),
  repairs('repairs30'),
  offers('offers53'),
  staffOrders('staffOrders69'),
  staffRepairs('staffRepairs90'),
  feedback('feedback59'),
  stock('stock1');

  const ArtGroup(this.seed);
  final String seed;

  static final _palettes = {for (final g in values) g: softPalette(g.seed)};
  GenPalette get palette => _palettes[this]!;
}

/// done: emerald check; waiting: gold clock; failed (or cancelled): red ×; action (needs you): gold !.
enum ArtBadge { none, done, waiting, failed, action }

/// Two-tone icons (Phosphor's duotone look: the filled shape faint under the line drawing).
enum ArtIcon {
  bag(PhosphorIconsRegular.shoppingBagOpen, PhosphorIconsFill.shoppingBagOpen),
  newOrder(PhosphorIconsRegular.shoppingBag, PhosphorIconsFill.shoppingBag),
  box(PhosphorIconsRegular.package, PhosphorIconsFill.package),
  truck(PhosphorIconsRegular.truck, PhosphorIconsFill.truck),
  pin(PhosphorIconsRegular.mapPinLine, PhosphorIconsFill.mapPinLine),
  note(PhosphorIconsRegular.chatCircleText, PhosphorIconsFill.chatCircleText),
  home(PhosphorIconsRegular.houseLine, PhosphorIconsFill.houseLine),
  wallet(PhosphorIconsRegular.wallet, PhosphorIconsFill.wallet),
  card(PhosphorIconsRegular.creditCard, PhosphorIconsFill.creditCard),
  rupee(PhosphorIconsRegular.currencyInr, PhosphorIconsFill.currencyInr),
  receipt(PhosphorIconsRegular.receipt, PhosphorIconsFill.receipt),
  hourglass(PhosphorIconsRegular.hourglassMedium, PhosphorIconsFill.hourglassMedium),
  link(PhosphorIconsRegular.linkSimple, PhosphorIconsFill.linkSimple),
  scales(PhosphorIconsRegular.scales, PhosphorIconsFill.scales),
  calendar(PhosphorIconsRegular.calendarCheck, PhosphorIconsFill.calendarCheck),
  clipboard(PhosphorIconsRegular.clipboardText, PhosphorIconsFill.clipboardText),
  wrench(PhosphorIconsRegular.wrench, PhosphorIconsFill.wrench),
  phone(PhosphorIconsRegular.deviceMobile, PhosphorIconsFill.deviceMobile),
  gift(PhosphorIconsRegular.gift, PhosphorIconsFill.gift),
  ticket(PhosphorIconsRegular.ticket, PhosphorIconsFill.ticket),
  star(PhosphorIconsRegular.star, PhosphorIconsFill.star),
  graph(PhosphorIconsRegular.chartLineDown, PhosphorIconsFill.chartLineDown),
  shelf(PhosphorIconsRegular.warehouse, PhosphorIconsFill.warehouse),
  bell(PhosphorIconsRegular.bell, PhosphorIconsFill.bell);

  const ArtIcon(this.line, this.fill);
  final IconData line;
  final IconData fill;
}

typedef ArtSpec = ({ArtGroup group, ArtIcon icon, ArtBadge badge});

/// Every kind the database writes (supabase/migrations: ours and the payment ones); a test checks.
const notificationArt = <String, ArtSpec>{
  'order_confirmed': (group: ArtGroup.orders, icon: ArtIcon.bag, badge: ArtBadge.done),
  'order_packed': (group: ArtGroup.orders, icon: ArtIcon.box, badge: ArtBadge.none),
  'order_shipped': (group: ArtGroup.orders, icon: ArtIcon.truck, badge: ArtBadge.none),
  'order_tracking': (group: ArtGroup.orders, icon: ArtIcon.pin, badge: ArtBadge.none),
  'order_update': (group: ArtGroup.orders, icon: ArtIcon.note, badge: ArtBadge.none),
  'order_delivered': (group: ArtGroup.orders, icon: ArtIcon.home, badge: ArtBadge.done),
  'order_cancelled': (group: ArtGroup.orders, icon: ArtIcon.box, badge: ArtBadge.failed),
  'order_awaiting_payment': (group: ArtGroup.payments, icon: ArtIcon.wallet, badge: ArtBadge.waiting),
  'payment_received': (group: ArtGroup.payments, icon: ArtIcon.wallet, badge: ArtBadge.done),
  'payment_failed': (group: ArtGroup.payments, icon: ArtIcon.card, badge: ArtBadge.failed),
  'order_expired': (group: ArtGroup.payments, icon: ArtIcon.hourglass, badge: ArtBadge.failed),
  'order_late_payment': (group: ArtGroup.payments, icon: ArtIcon.receipt, badge: ArtBadge.waiting),
  'order_refunded': (group: ArtGroup.payments, icon: ArtIcon.receipt, badge: ArtBadge.done),
  'repair_booked': (group: ArtGroup.repairs, icon: ArtIcon.calendar, badge: ArtBadge.waiting),
  'repair_confirmed': (group: ArtGroup.repairs, icon: ArtIcon.calendar, badge: ArtBadge.done),
  'repair_quote': (group: ArtGroup.repairs, icon: ArtIcon.clipboard, badge: ArtBadge.action),
  'repair_quote_agreed': (group: ArtGroup.repairs, icon: ArtIcon.clipboard, badge: ArtBadge.done),
  'repair_started': (group: ArtGroup.repairs, icon: ArtIcon.wrench, badge: ArtBadge.none),
  'repair_update': (group: ArtGroup.repairs, icon: ArtIcon.note, badge: ArtBadge.none),
  'repair_ready': (group: ArtGroup.repairs, icon: ArtIcon.phone, badge: ArtBadge.action),
  'repair_completed': (group: ArtGroup.repairs, icon: ArtIcon.phone, badge: ArtBadge.done),
  'repair_cancelled': (group: ArtGroup.repairs, icon: ArtIcon.wrench, badge: ArtBadge.failed),
  'referral_welcome': (group: ArtGroup.offers, icon: ArtIcon.gift, badge: ArtBadge.none),
  'referral_reward': (group: ArtGroup.offers, icon: ArtIcon.gift, badge: ArtBadge.done),
  'coupon': (group: ArtGroup.offers, icon: ArtIcon.ticket, badge: ArtBadge.none),
  'staff_new_order': (group: ArtGroup.staffOrders, icon: ArtIcon.newOrder, badge: ArtBadge.action),
  'staff_order_paid': (group: ArtGroup.staffOrders, icon: ArtIcon.rupee, badge: ArtBadge.done),
  'staff_order_cancelled': (group: ArtGroup.staffOrders, icon: ArtIcon.box, badge: ArtBadge.failed),
  'staff_refund_needed': (group: ArtGroup.staffOrders, icon: ArtIcon.receipt, badge: ArtBadge.action),
  'staff_refund_failed': (group: ArtGroup.staffOrders, icon: ArtIcon.receipt, badge: ArtBadge.failed),
  'staff_link_paid': (group: ArtGroup.staffOrders, icon: ArtIcon.link, badge: ArtBadge.done),
  'staff_dispute': (group: ArtGroup.staffOrders, icon: ArtIcon.scales, badge: ArtBadge.action),
  'staff_new_repair': (group: ArtGroup.staffRepairs, icon: ArtIcon.wrench, badge: ArtBadge.action),
  'staff_quote_approved': (group: ArtGroup.staffRepairs, icon: ArtIcon.clipboard, badge: ArtBadge.done),
  'staff_quote_declined': (group: ArtGroup.staffRepairs, icon: ArtIcon.clipboard, badge: ArtBadge.failed),
  'staff_repair_cancelled': (group: ArtGroup.staffRepairs, icon: ArtIcon.wrench, badge: ArtBadge.failed),
  'staff_feedback': (group: ArtGroup.feedback, icon: ArtIcon.star, badge: ArtBadge.none),
  'staff_feedback_low': (group: ArtGroup.feedback, icon: ArtIcon.star, badge: ArtBadge.action),
  'staff_low_stock': (group: ArtGroup.stock, icon: ArtIcon.graph, badge: ArtBadge.action),
  'staff_out_of_stock': (group: ArtGroup.stock, icon: ArtIcon.shelf, badge: ArtBadge.failed),
};

/// A kind this build doesn't know yet (a newer server): a plain bell.
const defaultArt = (group: ArtGroup.orders, icon: ArtIcon.bell, badge: ArtBadge.none);

ArtSpec artFor(String kind) => notificationArt[kind] ?? defaultArt;

/// The PNG for Android's notifications: `assets/notification_art/<name>.png`, one per look actually used.
String artAsset(ArtSpec a) => 'assets/notification_art/${a.group.name}-${a.icon.name}-${a.badge.name}.png';

/// The notification's accent on Android (the small icon and app name): its group's colour.
Color notificationColor(String kind) => artFor(kind).group.palette.accent;

class NotificationArt extends StatelessWidget {
  const NotificationArt({super.key, required this.kind, this.size = 48});

  final String kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final a = artFor(kind);
    final p = a.group.palette;
    final glyph = size * 0.56;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: SizedBox.square(
          dimension: size,
          // still: a list of these never animates (and the PNGs are one frame of it)
          child: AuroraBackground(
            palette: p,
            seed: a.group.seed,
            still: true,
            child: Stack(
              children: [
                Align(
                  alignment: a.badge == ArtBadge.none ? Alignment.center : const Alignment(-0.14, -0.14),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(a.icon.fill, size: glyph, color: p.accent.withValues(alpha: 0.2)),
                      Icon(a.icon.line, size: glyph, color: p.accent),
                    ],
                  ),
                ),
                if (a.badge != ArtBadge.none)
                  Positioned(right: size * 0.07, bottom: size * 0.07, child: StatusBadge(a.badge, size: size * 0.34)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The corner badge, also over product photos.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.badge, {super.key, required this.size});

  final ArtBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (badge) {
      ArtBadge.done => (BrandColors.emerald, Colors.white, PhosphorIconsBold.check),
      ArtBadge.waiting => (BrandColors.gold, BrandColors.goldInk, PhosphorIconsBold.clock),
      ArtBadge.failed => (lightScheme.error, Colors.white, PhosphorIconsBold.x),
      ArtBadge.action || ArtBadge.none => (BrandColors.gold, BrandColors.goldInk, PhosphorIconsBold.exclamationMark),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: (size * 0.1).clamp(1.5, 4)),
      ),
      child: Icon(icon, size: size * 0.58, color: fg),
    );
  }
}

/// A row's or the banner's picture: the product photo (with the status badge) when there is one, else the art.
class NotificationLeading extends StatelessWidget {
  const NotificationLeading(this.n, {super.key, this.size = 48});

  final AppNotification n;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = n.imagePath;
    if (path == null) return NotificationArt(kind: n.kind, size: size);
    final badge = artFor(n.kind).badge;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(size * 0.28),
            ),
            child: ProductImage(thumbPathFor(path) ?? path, radius: size * 0.28, padding: size * 0.08, color: Colors.white),
          ),
          if (badge != ArtBadge.none)
            Positioned(right: 0, bottom: 0, child: StatusBadge(badge, size: size * 0.34)),
        ],
      ),
    );
  }
}
