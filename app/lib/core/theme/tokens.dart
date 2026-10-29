import 'package:material_ui/material_ui.dart';

/// Ink + colour (docs/palette-ideas.html, option 4 with 1–3 folded in): black buttons and text stay, and colour
/// comes from the peacock feather in the logo. Peacock teal for information, emerald for savings and anything done,
/// saffron for repairs, gold for deals. The app is light-only by product decision, so there is no dark scheme.
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
}

/// One gradient per featured slide, in turn: peacock, marigold, emerald. White text passes AA on every stop.
const heroGradients = [
  [BrandColors.peacockDeep, BrandColors.peacock, Color(0xFF155E75)],
  [BrandColors.saffronDeep, BrandColors.saffron, Color(0xFFB4530A)],
  [BrandColors.emeraldDeep, BrandColors.emerald, Color(0xFF0E7490)],
];

/// The dot under each slide and the glow behind it, matched to [heroGradients].
const heroAccents = [BrandColors.gold, Color(0xFFF5B014), Color(0xFFB7EB4F)];

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
];

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
