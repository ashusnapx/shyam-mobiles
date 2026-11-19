import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/tokens.dart';
import 'widgets.dart';

/// Matching icon for a made-to-order type: cover/case a phone, glass/lens guard a shield, flip cover a book.
IconData madeToOrderIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('flip')) return PhosphorIconsRegular.bookOpen;
  if (n.contains('glass') || n.contains('guard')) return PhosphorIconsRegular.shieldCheck;
  return PhosphorIconsRegular.deviceMobile;
}

/// Tidy stand-in for the photo these products never have: a tinted rounded square with the type's icon.
class MadeToOrderArt extends StatelessWidget {
  const MadeToOrderArt(this.name, {super.key, this.radius = Radii.md, this.color});

  final String name;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: color ?? BrandColors.peacockMist, borderRadius: BorderRadius.circular(radius)),
          child: LayoutBuilder(
            builder: (_, box) => Center(child: Icon(madeToOrderIcon(name), size: box.biggest.shortestSide * 0.45, color: BrandColors.peacockInk)),
          ),
        ),
      );
}

/// [ProductImage], except a made-to-order product with no photo gets [MadeToOrderArt].
class ProductArt extends StatelessWidget {
  const ProductArt(this.path, {super.key, required this.name, required this.madeToOrder, this.radius = Radii.lg, this.padding = Space.md});

  final String? path;
  final String name;
  final bool madeToOrder;
  final double radius;
  final double padding;

  @override
  Widget build(BuildContext context) => path == null && madeToOrder
      ? MadeToOrderArt(name, radius: radius)
      : ProductImage(path, radius: radius, padding: padding);
}
