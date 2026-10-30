import 'package:material_ui/material_ui.dart';

/// Ink + colour (docs/palette-ideas.html, option 4 with 1–3 folded in): black buttons and text stay, and colour
/// comes from the peacock feather in the logo. Peacock teal for information, emerald for savings and anything done,
/// saffron for repairs, gold for deals. Plum, indigo and rose widen the range for slides, categories and section
/// bands, and sand is the quiet warm neutral behind premium touches. The app is light-only by product decision.
abstract final class BrandColors {
  static const ink = Color(0xFF0A0A0A);
  static const graphite = Color(0xFF262626);
  static const mist = Color(0xFF8C8C8C);

  static const peacock = Color(0xFF0F766E);
  static const peacockDeep = Color(0xFF0A3532);
  static const peacockMist = Color(0xFFE3F3F0);
  static const peacockInk = Color(0xFF0B4F4A);
  static const sky = Color(0xFF38BDF8); // the feather eye's core

  static const emerald = Color(0xFF047857);
  static const emeraldDeep = Color(0xFF03291F);
  static const mint = Color(0xFFE2F5EC);
  static const mintInk = Color(0xFF064E3B);

  static const saffron = Color(0xFFC2410C);
  static const saffronDeep = Color(0xFF5A1E08);
  static const cream = Color(0xFFFFEEDF);
  static const creamInk = Color(0xFF7C2D12);

  static const gold = Color(0xFFE0A82E);
  static const goldInk = Color(0xFF241A00);

  static const plum = Color(0xFF86198F);
  static const plumDeep = Color(0xFF3B0F33);
  static const plumMist = Color(0xFFF6EAF4);
  static const plumInk = Color(0xFF6B1D5C);

  static const indigo = Color(0xFF4338CA);
  static const indigoDeep = Color(0xFF1E1B4B);
  static const indigoMist = Color(0xFFEEF0FF);
  static const indigoInk = Color(0xFF3730A3);

  static const rose = Color(0xFFBE123C);
  static const roseDeep = Color(0xFF4C0519);
  static const roseMist = Color(0xFFFFE8EE);
  static const roseInk = Color(0xFF9F1239);

  static const sand = Color(0xFFF7F0E3);
  static const sandInk = Color(0xFF7A5B2E);
}

/// One gradient per featured slide, in turn: peacock, marigold, emerald, plum, indigo, rose. White text passes AA on
/// every stop. Banners store their tone as this index (0..5, a DB check).
const heroGradients = [
  [BrandColors.peacockDeep, BrandColors.peacock, Color(0xFF155E75)],
  [BrandColors.saffronDeep, BrandColors.saffron, Color(0xFFB4530A)],
  [BrandColors.emeraldDeep, BrandColors.emerald, Color(0xFF0E7490)],
  [BrandColors.plumDeep, Color(0xFF701A75), BrandColors.plum],
  [BrandColors.indigoDeep, BrandColors.indigoInk, BrandColors.indigo],
  [BrandColors.roseDeep, BrandColors.roseInk, BrandColors.rose],
];

/// The dot under each slide and the glow behind it, matched to [heroGradients].
const heroAccents = [
  BrandColors.gold,
  Color(0xFFF5B014),
  Color(0xFFB7EB4F),
  Color(0xFFF0ABFC),
  Color(0xFFA5B4FC),
  Color(0xFFFDA4AF),
];

/// Category tile tints (background, icon), so the home grid reads at a glance. Each icon passes 3:1 on its tint
/// (non-text contrast).
const tileTints = [
  (BrandColors.peacockMist, BrandColors.peacock),
  (BrandColors.cream, BrandColors.saffron),
  (BrandColors.mint, BrandColors.emerald),
  (Color(0xFFE0F2FE), Color(0xFF0369A1)),
  (Color(0xFFFEF3C7), Color(0xFF92400E)),
  (Color(0xFFEDE9FE), Color(0xFF6D28D9)),
  (Color(0xFFFCE7F3), Color(0xFFBE185D)),
  (BrandColors.plumMist, BrandColors.plum),
  (BrandColors.indigoMist, BrandColors.indigo),
  (BrandColors.roseMist, BrandColors.rose),
  (BrandColors.sand, BrandColors.sandInk),
];

/// Soft band behind a Home or product-page section and the accent pill beside its title (background, accent), so
/// each section reads as its own place without loud colour. Every accent passes 3:1 on its band.
const sectionTints = (
  deals: (BrandColors.cream, BrandColors.saffron),
  phones: (BrandColors.indigoMist, BrandColors.indigo),
  recent: (BrandColors.plumMist, BrandColors.plum),
  explore: (BrandColors.sand, BrandColors.sandInk),
  offers: (BrandColors.roseMist, BrandColors.rose),
  fits: (BrandColors.peacockMist, BrandColors.peacock),
);

abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const enter = Duration(milliseconds: 420);
}

// Ink stays primary (buttons, selection); the roles below carry the colour into every screen.
const lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: BrandColors.ink,
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFEBEBEB),
  onPrimaryContainer: BrandColors.ink,
  secondary: BrandColors.emerald, // "% off", free delivery, done steps, success: emerald
  onSecondary: Colors.white,
  secondaryContainer: BrandColors.mint,
  onSecondaryContainer: BrandColors.mintInk,
  tertiary: BrandColors.saffron, // repairs
  onTertiary: Colors.white,
  tertiaryContainer: BrandColors.gold, // deal tags: gold pill, dark text
  onTertiaryContainer: BrandColors.goldInk,
  error: Color(0xFFB3261E),
  onError: Colors.white,
  errorContainer: Color(0xFFFBE9E8),
  onErrorContainer: Color(0xFF6E120D),
  surface: Colors.white,
  onSurface: BrandColors.ink,
  onSurfaceVariant: Color(0xFF5E5E5E),
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: Color(0xFFFAFAFA),
  surfaceContainer: Color(0xFFF3F3F3),
  surfaceContainerHigh: Color(0xFFEBEBEB),
  surfaceContainerHighest: Color(0xFFE2E2E2),
  outline: Color(0xFFCFCFCF),
  outlineVariant: Color(0xFFE6E6E6),
  inverseSurface: Color(0xFF1F1F1F),
  onInverseSurface: Color(0xFFF2F2F2),
  inversePrimary: Color(0xFFF2F2F2),
  shadow: Colors.black,
  scrim: Colors.black,
);
