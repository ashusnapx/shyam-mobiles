import 'package:material_ui/material_ui.dart';

import 'generative.dart' show seedHash;

/// Ink + colour (docs/palette-ideas.html, option 4 with 1–3 folded in): black buttons and text stay, and colour
/// comes from the peacock feather in the logo. Peacock teal for information, emerald for savings and anything done,
/// saffron for repairs, gold for deals. Plum, indigo and ocean widen the range for slides, categories and section
/// bands, and sand is the quiet warm neutral behind premium touches. The app is light-only by product decision. No
/// red anywhere: red means an error.
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

  static const ocean = Color(0xFF0369A1);
  static const oceanDeep = Color(0xFF082F49);
  static const oceanMist = Color(0xFFE0F2FE);
  static const oceanInk = Color(0xFF075985);

  static const sand = Color(0xFFF7F0E3);
  static const sandInk = Color(0xFF7A5B2E);

  // gold can never be text (2.14 on white): amber is the deal family's text and icon colour (7.09 on white)
  static const amber = Color(0xFF92400E);
  static const amberMist = Color(0xFFFEF3C7);

  static const violet = Color(0xFF6D28D9);
  static const violetMist = Color(0xFFEDE9FE);

  static const slate = Color(0xFF475569);
  static const slateMist = Color(0xFFF1F5F9);

  static const whatsapp = Color(0xFF25D366); // WhatsApp's own green: ink text on it (white fails)
}

/// A background and the text or icon colour that sits on it.
typedef Tint = (Color bg, Color fg);

/// Each part of the app has one colour (its nav pill, empty-state art, icon wells and section pill), so you always
/// know where you are. Every fg passes 4.5:1 on its bg.
abstract final class Worlds {
  static const Tint shop = (BrandColors.peacockMist, BrandColors.peacock);
  static const Tint search = (BrandColors.oceanMist, BrandColors.ocean);
  static const Tint repairs = (BrandColors.cream, BrandColors.saffron);
  static const Tint cart = (BrandColors.mint, BrandColors.emerald);
  static const Tint account = (BrandColors.plumMist, BrandColors.plum);
  static const Tint admin = (BrandColors.indigoMist, BrandColors.indigo);
  static const Tint offers = (BrandColors.amberMist, BrandColors.amber);
}

/// Fixed category colours, so Phones is always indigo (generated ones once made it red-pink).
const categoryTints = <String, Tint>{
  'smartphones': (BrandColors.indigoMist, BrandColors.indigo),
  'keypad-phones': (BrandColors.slateMist, BrandColors.slate),
  'cases-covers': (BrandColors.violetMist, BrandColors.violet),
  'screen-guards': (BrandColors.peacockMist, BrandColors.peacock),
  'chargers-cables': (BrandColors.oceanMist, BrandColors.ocean),
  'earbuds-headphones': (BrandColors.plumMist, BrandColors.plum),
  'power-banks': (BrandColors.sand, BrandColors.sandInk),
};

/// A category's tint; a slug added later takes a stable one from the same table.
Tint categoryTint(String slug) =>
    categoryTints[slug] ?? categoryTints.values.elementAt(seedHash(slug) % categoryTints.length);

/// One gradient per featured slide, in turn: peacock, marigold, emerald, plum, indigo, ocean. White text passes AA on
/// every stop. Banners store their tone as this index (0..5, a DB check).
const heroGradients = [
  [BrandColors.peacockDeep, BrandColors.peacock, Color(0xFF155E75)],
  [BrandColors.saffronDeep, BrandColors.saffron, Color(0xFFB4530A)],
  [BrandColors.emeraldDeep, BrandColors.emerald, Color(0xFF0E7490)],
  [BrandColors.plumDeep, Color(0xFF701A75), BrandColors.plum],
  [BrandColors.indigoDeep, BrandColors.indigoInk, BrandColors.indigo],
  [BrandColors.oceanDeep, BrandColors.oceanInk, BrandColors.ocean],
];

/// The dot under each slide and the glow behind it, matched to [heroGradients].
const heroAccents = [
  BrandColors.gold,
  Color(0xFFF5B014),
  Color(0xFFB7EB4F),
  Color(0xFFF0ABFC),
  Color(0xFFA5B4FC),
  Color(0xFF7DD3FC),
];

/// Old category tile tints, kept only for the sign-in perks until that screen moves to [Worlds] (its pink pair reads
/// as red, so nothing new should use this).
const tileTints = [
  (BrandColors.peacockMist, BrandColors.peacock),
  (BrandColors.cream, BrandColors.saffron),
  (BrandColors.mint, BrandColors.emerald),
  (BrandColors.oceanMist, BrandColors.ocean),
  (Color(0xFFFEF3C7), Color(0xFF92400E)),
  (Color(0xFFEDE9FE), Color(0xFF6D28D9)),
  (Color(0xFFFCE7F3), Color(0xFFBE185D)),
  (BrandColors.plumMist, BrandColors.plum),
  (BrandColors.indigoMist, BrandColors.indigo),
  (BrandColors.sand, BrandColors.sandInk),
];

/// Soft band behind a Home or product-page section and the accent pill beside its title (background, accent), so
/// each section reads as its own place without loud colour. Deals are amber: saffron belongs to repairs.
const sectionTints = (
  deals: (BrandColors.amberMist, BrandColors.amber),
  phones: (BrandColors.indigoMist, BrandColors.indigo),
  recent: (BrandColors.plumMist, BrandColors.plum),
  explore: (BrandColors.sand, BrandColors.sandInk),
  offers: (BrandColors.mint, BrandColors.emerald),
  fits: (BrandColors.peacockMist, BrandColors.peacock),
  similar: (BrandColors.oceanMist, BrandColors.ocean),
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
  static const xs = 6.0; // tags
  static const sm = 8.0;
  static const chip = 10.0; // chips, icon wells
  static const md = 12.0;
  static const button = 14.0;
  static const lg = 16.0;
  static const hero = 20.0; // status heroes, carousel slides
  static const xl = 24.0;
}

abstract final class IconSizes {
  static const xs = 12.0; // inside a tag
  static const sm = 16.0; // chevrons, inline
  static const md = 20.0; // list rows, wells
  static const lg = 24.0; // app bar, buttons
  static const xl = 44.0; // empty states
}

abstract final class Motion {
  static const press = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const enter = Duration(milliseconds: 420);
  static const slide = Duration(milliseconds: 500); // the home carousel
  static const bump = Duration(milliseconds: 550);
  static const slow = Duration(milliseconds: 700);
  static const stagger = Duration(milliseconds: 55); // between items rising in
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
