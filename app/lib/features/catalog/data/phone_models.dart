import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import 'catalog_repository.dart';

// Made-to-order accessories: covers, glass and guards the shop arranges for ANY phone the customer names, even one
// launched today. Nothing here is per model: search spots a model-like query, the product page asks for the model.

/// Brand words as the makers write them. Any of these in a query makes it a phone-model query.
const _brands = {
  'samsung': 'Samsung',
  'galaxy': 'Galaxy',
  'vivo': 'vivo',
  'oppo': 'OPPO',
  'realme': 'realme',
  'redmi': 'Redmi',
  'xiaomi': 'Xiaomi',
  'mi': 'Mi',
  'poco': 'POCO',
  'oneplus': 'OnePlus',
  'iphone': 'iPhone',
  'apple': 'Apple',
  'motorola': 'Motorola',
  'moto': 'moto',
  'nokia': 'Nokia',
  'lava': 'LAVA',
  'itel': 'itel',
  'infinix': 'Infinix',
  'tecno': 'Tecno',
  'google': 'Google',
  'pixel': 'Pixel',
  'nothing': 'Nothing',
  'iqoo': 'iQOO',
  'honor': 'Honor',
};

/// Words that name the accessory, not the phone ("samsung a15 back cover" is for "Samsung A15").
const _accessoryWords = {
  'cover',
  'covers',
  'case',
  'cases',
  'back',
  'tempered',
  'glass',
  'guard',
  'guards',
  'lens',
  'camera',
  'flip',
  'silicone',
  'screen',
  'protector',
  'charger',
  'cable',
  'earphones',
  'earbuds',
  'mobile',
  'for',
  'ka',
  'ki',
  'ke',
};

final _wordNumber = RegExp(r'(^|\s)([a-z]+)\s+\d+[a-z+]*(\s|$)');
final _unit = RegExp(r'\b\d+\s*(w|mah|m|gb|tb|mm|cm|v|a)\b'); // "65w", "10000 mah": a spec, not a model
final _allowed = RegExp(r"^[A-Za-z0-9][A-Za-z0-9 +()./'-]*$"); // the server's check on cart_items.for_model

/// True when [query] looks like a phone model: a brand word, or `word number` ("galaxy a15", "note 13").
bool isModelQuery(String query) {
  final q = query.toLowerCase().trim();
  final words = q.split(RegExp(r'\s+'));
  if (words.any(_brands.containsKey)) return true;
  if (_unit.hasMatch(q)) return false;
  final m = _wordNumber.firstMatch(q);
  return m != null && !_accessoryWords.contains(m.group(2));
}

/// [raw] as a tidy model name ("samsung  galaxy a15 5g" → "Samsung Galaxy A15 5G"), or null when it isn't one
/// (under 2 or over 60 characters, or characters a model never has).
String? tidyModel(String raw) {
  final words = raw.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final tidy = [
    for (final w in words)
      _brands[w.toLowerCase()] ??
          // A15, 5G, SE, FE in capitals; other words capitalised
          (w.contains(RegExp(r'\d')) || (w.length <= 2 && !w.contains(RegExp(r'[^A-Za-z]')))
              ? w.toUpperCase()
              : w[0].toUpperCase() + w.substring(1).toLowerCase()),
  ].join(' ');
  return tidy.length >= 2 && tidy.length <= 60 && _allowed.hasMatch(tidy) ? tidy : null;
}

/// The phone a model query is about, with the accessory words dropped ("redmi note 13 back cover" → "Redmi Note 13").
String? modelOf(String query) => tidyModel(
  [
    for (final w in query.replaceAll(RegExp(r"[^A-Za-z0-9 +()./'-]"), ' ').split(RegExp(r'\s+')))
      if (!_accessoryWords.contains(w.toLowerCase())) w,
  ].join(' '),
);

/// Same phone, ignoring case and spaces ("galaxy a15" and "Galaxy A 15").
String modelKey(String model) => model.toLowerCase().replaceAll(' ', '');

/// The made-to-order types (back cover, tempered glass...), cheapest first.
final madeToOrderProvider = FutureProvider<List<ProductCard>>(
  (ref) async =>
      [...await ref.watch(catalogRepositoryProvider).madeToOrder()]
        ..sort((a, b) => a.minPricePaise.compareTo(b.minPricePaise)),
);

/// Suggestions for "Your phone model": the catalog's phones and the models customers ordered for, learned by the
/// server with no owner work, deduped ignoring case and spaces.
final phoneModelsProvider = FutureProvider<List<String>>((ref) async {
  final seen = <String>{};
  return [
    for (final m in await ref.watch(catalogRepositoryProvider).phoneModels())
      if (seen.add(modelKey(m))) m,
  ];
});
