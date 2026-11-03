import 'package:material_ui/material_ui.dart';

import 'generative.dart' show seedHash;

/// "Ivory & Peacock" (palette v2, scratch spec of 3 Nov 2026): a warm ivory canvas with white cards, a deep blue-black
/// ink for text and commit buttons, one brand hue (deep peacock), one warm accent (brass) for deals, desaturated
/// semantic colours, and calm identity colours whose backgrounds and icons share one lightness. The app is light-only
/// by product decision. Red means an error, nothing else.
abstract final class BrandColors {
  static const ink = Color(0xFF111922);
  static const graphite = Color(0xFF2A3139);
  static const mist = Color(0xFF7B8187); // icons and disabled states only, never text (3.78 on ivory)
  static const ivory = Color(0xFFFCFAF6); // the canvas

  // the launcher icon's own colours: the mark never follows the palette
  static const logoInk = Color(0xFF0A0A0A);
  static const logoGold = Color(0xFFE0A82E);

  static const peacock = Color(0xFF0B6B6F);
  static const peacockDeep = Color(0xFF032729);
  static const peacockMist = Color(0xFFE0F5F6);
  static const peacockInk = Color(0xFF025559); // text links
  static const sky = Color(0xFF38BDF8); // the feather eye's core (logo only)

  // success: jade
  static const emerald = Color(0xFF337250);
  static const emeraldDeep = Color(0xFF112A1C);
  static const mint = Color(0xFFE4F5EB);
  static const mintInk = Color(0xFF1E4731);

  // repairs: copper, identity only (the Repairs button stays ink)
  static const saffron = Color(0xFF975529);
  static const saffronDeep = Color(0xFF3A1E0E);
  static const cream = Color(0xFFFDEDE0);
  static const creamInk = Color(0xFF61361C);

  // the warm accent: brass. gold is a fill only (2.16 on ivory: never text); text goes on goldSoft or amberMist
  static const gold = Color(0xFFCEA766);
  static const goldSoft = Color(0xFFF1DDB9);
  static const goldInk = Color(0xFF432E14);
  static const amber = Color(0xFF815B26);
  static const amberMist = Color(0xFFF8EFDD);

  static const plum = Color(0xFF824D80);
  static const plumDeep = Color(0xFF351C34);
  static const plumMist = Color(0xFFF9EBF8);
  static const plumInk = Color(0xFF593258);

  static const indigo = Color(0xFF4E5EA2);
  static const indigoDeep = Color(0xFF1C2444);
  static const indigoMist = Color(0xFFEBF0FE);
  static const indigoInk = Color(0xFF323E71);

  static const ocean = Color(0xFF1F6A96);
  static const oceanDeep = Color(0xFF06293E);
  static const oceanMist = Color(0xFFE5F2FD);
  static const oceanInk = Color(0xFF0D4768);

  static const violet = Color(0xFF6B5499);
  static const violetMist = Color(0xFFF1EEFC);
  static const violetInk = Color(0xFF48366B);

  static const slate = Color(0xFF50667C);
  static const slateMist = Color(0xFFEBF1F7);
  static const slateInk = Color(0xFF344455);

  static const sand = Color(0xFFF8EFE0);
  static const sandInk = Color(0xFF75603B);

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

/// One gradient per featured slide, in turn: peacock, brass, jade, plum, indigo, ocean (dark to light, OKLCH L .28 to
/// .42 at low chroma). White text passes 8:1 on every stop. Banners store their tone as this index (0..5, a DB check).
const heroGradients = [
  [Color(0xFF042F33), Color(0xFF0A4346), Color(0xFF075957)],
  [Color(0xFF3C2208), Color(0xFF513308), Color(0xFF65470F)],
  [Color(0xFF013125), Color(0xFF0F452E), Color(0xFF085955)],
  [Color(0xFF391E34), Color(0xFF4E2C4D), Color(0xFF5F3E69)],
  [Color(0xFF232644), Color(0xFF2E375F), Color(0xFF344C79)],
  [Color(0xFF102B43), Color(0xFF0F3F5B), Color(0xFF05556F)],
];

/// The dot under each slide and the glow behind it, matched to [heroGradients].
const heroAccents = [
  Color(0xFF97DBE7),
  Color(0xFFE6C99A),
  Color(0xFFA0DDC7),
  Color(0xFFEDBDDE),
  Color(0xFFC6C9FB),
  Color(0xFFACD2FB),
];

/// The band behind a Home or product-page section and the accent bar beside its title (band, accent): near white with
/// a trace of hue. At most one tinted band per screen; the others sit on [explore] or the plain canvas.
const sectionTints = (
  deals: (Color(0xFFFBF6EE), BrandColors.amber),
  phones: (Color(0xFFF5F7FC), BrandColors.indigo),
  recent: (Color(0xFFFBF4FB), BrandColors.plum),
  explore: (Color(0xFFF7F6F2), BrandColors.sandInk), // surfaceContainerLow: the neutral band
  offers: (Color(0xFFF0F9F4), BrandColors.emerald),
  fits: (Color(0xFFEEF9FA), BrandColors.peacock),
  similar: (Color(0xFFF0F8FE), BrandColors.ocean),
);

/// One 4/8-pt scale. [gutter] is the page's side margin, [section] the gap between Home's sections.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const gutter = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const section = 32.0;
}

abstract final class Radii {
  static const xs = 6.0; // tags
  static const sm = 8.0;
  static const chip = 10.0; // chips, icon wells
  static const md = 12.0;
  static const button = 14.0;
  static const lg = 16.0;
  static const hero = 20.0; // status heroes, carousel slides
  static const xl = 24.0; // section panels, sheets
}

/// Resting cards and tiles ([card]), and what floats above the page: bars, sheets, the hero ([raised]).
abstract final class Shadows {
  static const card = [
    BoxShadow(color: Color(0x0A111922), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0A111922), offset: Offset(0, 2), blurRadius: 8),
  ];
  static const raised = [
    BoxShadow(color: Color(0x14111922), offset: Offset(0, 8), blurRadius: 24),
    BoxShadow(color: Color(0x0D111922), offset: Offset(0, 2), blurRadius: 6),
  ];
}

/// Frosted glass. [bar]: pinned bars (never below 0.88: ink, onSurfaceVariant and peacock still pass AA over black).
/// [card]: floating chips over light aurora or a photo well only. [onDeep]: pills on a hero gradient, white text at
/// labelLarge or larger. Glass never holds a price or an error. At most two blurs on screen ([GlassSurface]).
abstract final class Glass {
  static const bar = Color(0xE0FCFAF6); // ivory at 0.88
  static const card = Color(0xB8FFFFFF); // white at 0.72
  static const onDeep = Color(0x24FFFFFF); // white at 0.14
  static const hairline = Color(0x14111922); // ink at 0.08
  static const highlight = Color(0xB3FFFFFF); // the 1px top edge
  static const hairlineOnDeep = Color(0x38FFFFFF);
  static const fallback = Color(0xF7FCFAF6); // ivory at 0.97: low-RAM phones and reduced motion, no blur
  static const barBlur = 24.0;
  static const cardBlur = 16.0;
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
  static const hero = Duration(milliseconds: 5500); // how long a carousel slide stays
  static const slide = Duration(milliseconds: 500); // the home carousel
  static const bump = Duration(milliseconds: 550);
  static const slow = Duration(milliseconds: 700);
  static const stagger = Duration(milliseconds: 55); // between items rising in
}

// Ink stays primary (buttons, selection); white cards float on the ivory canvas.
const lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: BrandColors.ink,
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFEDEAE5),
  onPrimaryContainer: BrandColors.ink,
  secondary: BrandColors.emerald, // "% off", free delivery, done steps, success
  onSecondary: Colors.white,
  secondaryContainer: BrandColors.mint,
  onSecondaryContainer: BrandColors.mintInk,
  tertiary: BrandColors.saffron, // repairs (identity)
  onTertiary: Colors.white,
  tertiaryContainer: BrandColors.goldSoft, // deal pills: brass, dark text
  onTertiaryContainer: BrandColors.goldInk,
  error: Color(0xFFA23D37),
  onError: Colors.white,
  errorContainer: Color(0xFFFDEBE9),
  onErrorContainer: Color(0xFF692823),
  surface: BrandColors.ivory,
  onSurface: BrandColors.ink,
  onSurfaceVariant: Color(0xFF5B6168),
  surfaceContainerLowest: Colors.white, // cards
  surfaceContainerLow: Color(0xFFF7F6F2),
  surfaceContainer: Color(0xFFF3F0EC), // image wells
  surfaceContainerHigh: Color(0xFFEDEAE5),
  surfaceContainerHighest: Color(0xFFE6E3DE),
  outline: Color(0xFFC7C4BD),
  outlineVariant: Color(0xFFE2DFDA), // hairlines
  inverseSurface: Color(0xFF1A222B),
  onInverseSurface: Color(0xFFF3F0EC),
  inversePrimary: Color(0xFF82C5C8),
  shadow: BrandColors.ink,
  scrim: BrandColors.ink,
);
