import 'dart:math' as math;

import '../../../core/models/models.dart';

/// "12 GB · 256 GB", or '' when the variant has no memory (most accessories).
String memoryOf(Variant v) => [v.ram, v.storage].nonNulls.join(' · ');

String colorOf(Variant v) => v.color ?? '';

/// [available]: some variant with this option is in stock. Options keep the admin's variant order.
typedef MemoryOption = ({String label, int deltaPaise, bool available});
typedef ColorOption = ({String label, String? hex, bool available});

/// Distinct memory options; [MemoryOption.deltaPaise] is the option's cheapest price minus the product's cheapest.
List<MemoryOption> memoryOptions(List<Variant> variants) {
  final groups = <String, List<Variant>>{};
  for (final v in variants) {
    if (memoryOf(v).isNotEmpty) (groups[memoryOf(v)] ??= []).add(v);
  }
  if (groups.isEmpty) return const [];
  final cheapest = variants.map((v) => v.pricePaise).reduce(math.min);
  return [
    for (final MapEntry(key: label, value: vs) in groups.entries)
      (
        label: label,
        deltaPaise: vs.map((v) => v.pricePaise).reduce(math.min) - cheapest,
        available: vs.any((v) => v.inStock),
      ),
  ];
}

List<ColorOption> colorOptions(List<Variant> variants) {
  final groups = <String, List<Variant>>{};
  for (final v in variants) {
    if (colorOf(v).isNotEmpty) (groups[colorOf(v)] ??= []).add(v);
  }
  return [
    for (final MapEntry(key: label, value: vs) in groups.entries)
      (label: label, hex: vs.first.colorHex, available: vs.any((v) => v.inStock)),
  ];
}

/// Cheapest in-stock variant, else the first one. Null only when there are no variants.
Variant? initialVariant(List<Variant> variants) {
  final inStock = variants.where((v) => v.inStock);
  return inStock.isEmpty ? variants.firstOrNull : inStock.reduce((a, b) => b.pricePaise < a.pricePaise ? b : a);
}

/// Selection after tapping a [memory] or [color] option: keeps the other attribute when that combination is in
/// stock, else the first in-stock variant with the tapped option, else the exact combination, else any match.
Variant pickVariant(List<Variant> variants, Variant current, {String? memory, String? color}) {
  assert((memory == null) != (color == null), 'pass exactly one of memory or color');
  bool tapped(Variant v) => memory != null ? memoryOf(v) == memory : colorOf(v) == color;
  bool keepsOther(Variant v) => memory != null ? colorOf(v) == colorOf(current) : memoryOf(v) == memoryOf(current);
  final matches = variants.where(tapped);
  return matches.where((v) => keepsOther(v) && v.inStock).firstOrNull ??
      matches.where((v) => v.inStock).firstOrNull ??
      matches.where(keepsOther).firstOrNull ??
      matches.firstOrNull ??
      current;
}
