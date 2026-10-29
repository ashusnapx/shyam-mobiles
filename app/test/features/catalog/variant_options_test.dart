import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/catalog/data/variant_options.dart';

Variant v(String id, int rupees, int stock, Map<String, dynamic> attrs) => Variant(
      id: id,
      productId: 'p',
      sku: id,
      name: id,
      pricePaise: rupees * 100,
      mrpPaise: rupees * 100,
      stock: stock,
      attributes: attrs,
    );

Map<String, dynamic> a(String? ram, String storage, String color) =>
    {'ram': ?ram, 'storage': storage, 'color': color, 'color_hex': '#000000'};

// Shapes from supabase/seed.sql
final s25 = [
  v('navy256', 74999, 8, a('12 GB', '256 GB', 'Navy')),
  v('icy256', 74999, 5, a('12 GB', '256 GB', 'Icyblue')),
  v('navy512', 86999, 2, a('12 GB', '512 GB', 'Navy')),
];
final iphone16 = [
  v('blk128', 69900, 6, a(null, '128 GB', 'Black')),
  v('ult128', 69900, 0, a(null, '128 GB', 'Ultramarine')),
  v('blk256', 79900, 3, a(null, '256 GB', 'Black')),
];

void main() {
  test('memory options keep variant order with +delta vs the cheapest', () {
    expect(memoryOptions(s25), [
      (label: '12 GB · 256 GB', deltaPaise: 0, available: true),
      (label: '12 GB · 512 GB', deltaPaise: 1200000, available: true),
    ]);
    expect(memoryOptions(iphone16).map((o) => o.label), ['128 GB', '256 GB']);
  });

  test('a colour with no stock anywhere is unavailable', () {
    expect(colorOptions(iphone16), [
      (label: 'Black', hex: '#000000', available: true),
      (label: 'Ultramarine', hex: '#000000', available: false),
    ]);
  });

  test('accessories without attributes have no options', () {
    final guard = [v('g', 1199, 30, {})];
    expect(memoryOptions(guard), isEmpty);
    expect(colorOptions(guard), isEmpty);
  });

  test('initial pick is the cheapest in-stock variant, else the first', () {
    expect(initialVariant([s25[2], s25[1], s25[0]])!.id, 'icy256');
    final soldOut = [v('x', 59900, 0, a(null, '128 GB', 'Black')), v('y', 49900, 0, a(null, '128 GB', 'Blue'))];
    expect(initialVariant(soldOut)!.id, 'x');
    expect(initialVariant([]), isNull);
  });

  test('picking memory keeps the colour when that combination is in stock', () {
    expect(pickVariant(s25, s25[2], memory: '12 GB · 256 GB').id, 'navy256');
  });

  test('picking memory falls back to the nearest in-stock variant when the colour does not exist', () {
    expect(pickVariant(s25, s25[1], memory: '12 GB · 512 GB').id, 'navy512');
  });

  test('picking colour keeps the memory when possible', () {
    expect(pickVariant(s25, s25[0], color: 'Icyblue').id, 'icy256');
    expect(pickVariant(iphone16, iphone16[0], color: 'Black').id, 'blk128');
  });

  test('picking memory skips an out-of-stock combination for an in-stock one', () {
    final vs = [
      v('b128', 100, 0, a(null, '128 GB', 'Black')),
      v('w128', 100, 4, a(null, '128 GB', 'White')),
      v('b256', 200, 4, a(null, '256 GB', 'Black')),
    ];
    expect(pickVariant(vs, vs[2], memory: '128 GB').id, 'w128');
  });

  test('when nothing with the option is in stock, the exact combination is shown', () {
    expect(pickVariant(iphone16, iphone16[2], color: 'Ultramarine').id, 'ult128');
  });
}
