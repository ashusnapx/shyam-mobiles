import 'dart:math';

import '../../../core/format.dart';
import '../../../core/models/models.dart';
import '../../reviews/data/reviews.dart' show ratingLabel;

/// Home's automatic banners, after the owner's own: each is on or off in Admin → Banners (store_settings.auto_banners,
/// settings/store autoBanners). Off by default: Repairs, until the shop promises same-day repairs.
enum AutoBanner {
  deal('Deal of the day', 'The biggest real discount in stock, a new one each day'),
  newest('New in the shop', 'The newest product in stock'),
  exchange('Exchange your old phone', 'Opens the exchange form; the shop sends the estimate'),
  repairs('Repairs · same day', 'Only if the shop can promise same-day repairs');

  const AutoBanner(this.label, this.hint);

  final String label;
  final String hint;
}

const _ist = Duration(hours: 5, minutes: 30);

/// The day in Waidhan (IST): the deal changes at local midnight, not UTC's.
int istDay(DateTime now) => now.toUtc().add(_ist).difference(DateTime.utc(1970)).inDays;

/// The next IST midnight: when today's deal ends.
DateTime istMidnightAfter(DateTime now) {
  final ist = now.toUtc().add(_ist);
  return DateTime.utc(ist.year, ist.month, ist.day + 1).subtract(_ist);
}

/// Deal of the day: of the (up to 5) in-stock products with the biggest real discount off the MRP, one each day in
/// turn, so the hero never goes stale. Null when nothing in stock is discounted.
ProductCard? dealOfTheDay(Iterable<ProductCard> cards, DateTime now) {
  int off(ProductCard c) => discountPercent(c.minPricePaise, c.mrpPaise);
  final seen = <String>{};
  final deals = [for (final c in cards) if (c.inStock && !c.madeToOrder && off(c) > 0 && seen.add(c.id)) c]
    ..sort((a, b) => off(b) != off(a) ? off(b) - off(a) : a.id.compareTo(b.id));
  if (deals.isEmpty) return null;
  final top = deals.take(5).toList();
  return top[istDay(now) % top.length];
}

typedef AutoSlide = ({AutoBanner kind, ProductCard? card, DateTime? endsAt});

/// The automatic slides that are on and have something true to show, in [AutoBanner] order. [cards] are the
/// products Home already has; [newest] newest first.
List<AutoSlide> autoSlides(List<String> on, {required Iterable<ProductCard> cards, required List<ProductCard> newest,
    required DateTime now}) {
  final deal = on.contains(AutoBanner.deal.name) ? dealOfTheDay(cards, now) : null;
  final fresh = on.contains(AutoBanner.newest.name)
      ? newest.where((c) => c.inStock && c.id != deal?.id).firstOrNull
      : null;
  return [
    if (deal != null) (kind: AutoBanner.deal, card: deal, endsAt: istMidnightAfter(now)),
    if (fresh != null) (kind: AutoBanner.newest, card: fresh, endsAt: null),
    for (final k in [AutoBanner.exchange, AutoBanner.repairs])
      if (on.contains(k.name)) (kind: k, card: null, endsAt: null),
  ];
}

/// "Only N left" from this many down (counted stock, never typed in).
const lowStock = 3;

/// A rating shows from this many reviews: fewer proves nothing.
const minRatings = 3;

/// What a product banner adds to name and price, each only when true: the saving off the MRP, real low stock, the
/// rating. [stock] is the units across in-stock variants (null until loaded, or made to order).
({int savePaise, int? left, String? rating}) slideFacts(ProductCard card, {int? stock, int ratingCount = 0, int ratingSum = 0}) => (
      savePaise: max(0, card.mrpPaise - card.minPricePaise),
      left: stock != null && stock > 0 && stock <= lowStock ? stock : null,
      rating: ratingCount >= minRatings ? ratingLabel((ratingSum * 10 / ratingCount).round()) : null,
    );

/// Units on hand across the product's in-stock variants; null when any is made to order (no stock to count).
int? stockOf(Product p) {
  final live = p.activeVariants;
  if (live.any((v) => v.madeToOrder)) return null;
  return live.fold<int>(0, (n, v) => n + max(0, v.stock));
}
