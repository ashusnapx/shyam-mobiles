import 'package:material_ui/material_ui.dart';

/// Monochrome brand: ink, paper and greys. Colour appears only in product swatches and errors.
/// The app is light-only by product decision, so there is no dark scheme.
abstract final class BrandColors {
  static const ink = Color(0xFF0A0A0A);
  static const graphite = Color(0xFF262626);
  static const mist = Color(0xFF8C8C8C);
}

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
}

// Mirrors the :root tokens in docs/mockup.html (v2, monochrome).
const lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: BrandColors.ink,
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFEBEBEB),
  onPrimaryContainer: BrandColors.ink,
  secondary: BrandColors.ink, // "% off", free delivery, positive states
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFFEBEBEB),
  onSecondaryContainer: BrandColors.ink,
  tertiary: BrandColors.ink,
  onTertiary: Colors.white,
  tertiaryContainer: BrandColors.ink, // deal tags are inverted: ink pill, white text
  onTertiaryContainer: Colors.white,
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
