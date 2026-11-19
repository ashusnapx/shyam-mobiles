import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../catalog/data/catalog.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/phone_models.dart';
import '../../catalog/data/rails.dart';
import '../../catalog/widgets/product_tile.dart' show shortName;
import 'offers_repository.dart';

// Phone packs (Admin > Offers > New pack offer): a phone plus a fitting item of every type the pack asks for gets
// the pack's percent off. The server prices it (private.pack_lines, pricing.ts); this only builds the card that
// offers the pack, and the card adds nothing until the customer taps "Add pack to cart".

/// The accessory types a pack can ask for, by the server's names.
enum PackType {
  glass('glass', 'Tempered glass'),
  cover('case', 'Case or cover'),
  lens('lens', 'Camera lens guard'),
  charger('charger', 'Charger'),
  earphones('earphones', 'Earphones');

  const PackType(this.value, this.label);
  final String value;
  final String label;

  static PackType? parse(String v) => values.where((t) => t.value == v).firstOrNull;
}

/// An accessory's type, as private.accessory_type / pricing.ts decide it: by category and name, first match wins.
PackType? accessoryType(String categorySlug, String name) {
  final n = name.toLowerCase();
  bool has(List<String> words) => words.any(n.contains);
  if (n.contains('lens')) return PackType.lens;
  if (categorySlug == 'screen-guards' || has(['glass', 'screen guard', 'screen protector'])) return PackType.glass;
  if (categorySlug == 'cases-covers' || has(['case', 'cover'])) return PackType.cover;
  if (has(['charger', 'adapter'])) return PackType.charger;
  if (categorySlug == 'earbuds-headphones' || has(['earphone', 'earbud', 'buds', 'headphone', 'airpods'])) {
    return PackType.earphones;
  }
  return null;
}

/// A running pack offer (`pack_offers()`; Firebase: publicOffers with kind pack).
class PackOffer {
  const PackOffer({
    required this.id,
    required this.title,
    required this.percent,
    required this.types,
    required this.categoryIds,
    this.whole = false,
    this.maxDiscountPaise,
  });

  final String id;
  final String title;
  final int percent; // 1..50
  final List<PackType> types;
  final Set<String> categoryIds; // the phone categories it covers
  final bool whole; // the phone is discounted too; default: the accessories only
  final int? maxDiscountPaise;

  factory PackOffer.fromJson(Map<String, dynamic> j) => PackOffer(
    id: j['id'],
    title: j['title'],
    percent: j['value'],
    types: [for (final t in (j['pack_types'] as List? ?? const [])) ?PackType.parse(t as String)],
    categoryIds: {...(j['categories'] as List? ?? const []).cast<String>()},
    whole: j['pack_whole'] ?? false,
    maxDiscountPaise: j['max_discount_paise'],
  );

  /// What the pack takes off [phonePaise] + [accessoriesPaise], as the server will (display only).
  int savingPaise(int phonePaise, int accessoriesPaise) {
    final base = accessoriesPaise + (whole ? phonePaise : 0);
    return math.min(base * percent ~/ 100, maxDiscountPaise ?? base);
  }
}

final packOffersProvider = FutureProvider.autoDispose<List<PackOffer>>(
  (ref) => ref.watch(offersRepositoryProvider).packs(),
);

/// One line of a pack: the item, and the phone it is made for when it's made to order.
typedef PackItem = ({PackType type, ProductCard card, String? forModel});

/// The pack offered for a phone: the cheapest fitting in-stock item per type, else that type's made-to-order item
/// for this phone; [choices] are the swaps per type. Null when no running pack covers the phone or a type has nothing.
typedef Pack = ({PackOffer offer, Product phone, List<PackItem> items, Map<PackType, List<PackItem>> choices});

final packProvider = FutureProvider.autoDispose.family<Pack?, String>((ref, phoneSlug) async {
  final phone = await ref.watch(productProvider(phoneSlug).future);
  if (phone == null || phone.category.kind != CategoryKind.phone) return null;
  final offer = (await ref.watch(packOffersProvider.future))
      .where((o) => o.categoryIds.contains(phone.category.id) && o.types.isNotEmpty)
      .firstOrNull;
  if (offer == null) return null;

  final repo = ref.watch(catalogRepositoryProvider);
  final fits = await ref.watch(fitsProvider(phoneSlug).future);
  final madeToOrder = await ref.watch(madeToOrderProvider.future);
  final model = tidyModel(shortName(phone.name, phone.brand.name));
  // chargers and earphones fit every phone: the shop's cheapest in stock
  Future<List<ProductCard>> universal(String category) async => (await repo.search(
    (
      q: '',
      category: category,
      brand: null,
      minPricePaise: null,
      maxPricePaise: null,
      inStock: true,
      sort: SearchSort.priceAsc,
    ),
    offset: 0,
    limit: 20,
  )).items;

  final choices = <PackType, List<PackItem>>{};
  for (final type in offer.types) {
    final pool = switch (type) {
      PackType.charger => await universal('chargers-cables'),
      PackType.earphones => await universal('earbuds-headphones'),
      _ => fits,
    };
    choices[type] = [
      for (final c in [...pool]..sort((a, b) => a.minPricePaise.compareTo(b.minPricePaise)))
        if (c.inStock && !c.madeToOrder && accessoryType(c.categorySlug, c.name) == type)
          (type: type, card: c, forModel: null),
      if (model != null)
        for (final c in madeToOrder)
          if (accessoryType(c.categorySlug, c.name) == type) (type: type, card: c, forModel: model),
    ];
    if (choices[type]!.isEmpty) return null; // can't be completed: no card
  }
  return (offer: offer, phone: phone, items: [for (final t in offer.types) choices[t]!.first], choices: choices);
});
