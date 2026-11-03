import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'tokens.dart';

ThemeData buildTheme(ColorScheme c) {
  final base = ThemeData(colorScheme: c, useMaterial3: true);
  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).copyWith(
    // Familjen Grotesk is the brand face (logo 6, docs/logo-ideas.html): wordmark, hero and status headlines.
    displayLarge: GoogleFonts.familjenGrotesk(fontSize: 40, fontWeight: FontWeight.w700, height: 1.0, letterSpacing: -1.2),
    displayMedium: GoogleFonts.familjenGrotesk(fontSize: 34, fontWeight: FontWeight.w700, height: 1.02, letterSpacing: -1.0),
    displaySmall: GoogleFonts.familjenGrotesk(fontSize: 28, fontWeight: FontWeight.w700, height: 1.05, letterSpacing: -0.8),
    headlineMedium: GoogleFonts.plusJakartaSans(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.15),
    headlineSmall: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.2),
    titleLarge: GoogleFonts.plusJakartaSans(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleMedium: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600),
    titleSmall: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: GoogleFonts.plusJakartaSans(fontSize: 16, height: 1.5),
    bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.45),
    bodySmall: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4),
    labelLarge: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600),
    labelMedium: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
    labelSmall: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2),
  ).apply(bodyColor: c.onSurface, displayColor: c.onSurface);

  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button));
  const buttonSize = Size(64, 52);

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: c.surface,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.onSurface,
      surfaceTintColor: Colors.transparent,
      // a hairline once content scrolls under it
      scrolledUnderElevation: 0.5,
      shadowColor: c.outlineVariant,
      centerTitle: false,
      // the brand face, like the section headers
      titleTextStyle: GoogleFonts.familjenGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: c.onSurface,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.primary,
      foregroundColor: c.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: buttonSize, shape: buttonShape, textStyle: text.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonSize,
        shape: buttonShape,
        textStyle: text.labelLarge,
        side: BorderSide(color: c.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      // links carry the brand
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: text.labelLarge,
        foregroundColor: BrandColors.peacockInk,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      // white with a hairline: a filled grey field looks muddy on ivory
      filled: true,
      fillColor: c.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.lg),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: c.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: c.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: c.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: c.error, width: 1.5),
      ),
      labelStyle: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
      hintStyle: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
    ),
    cardTheme: CardThemeData(
      // white with a hairline and the faintest lift, floating on the ivory canvas
      elevation: 1,
      shadowColor: c.shadow.withValues(alpha: 0.06),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      color: c.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: c.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(PhosphorIconsRegular.arrowLeft),
      closeButtonIconBuilder: (_) => const Icon(PhosphorIconsRegular.x),
    ),
    chipTheme: base.chipTheme.copyWith(
      // Selected = solid ink, as in the mockup.
      selectedColor: c.primary,
      secondaryLabelStyle: text.labelMedium?.copyWith(color: c.onPrimary),
      checkmarkColor: c.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.chip)),
      side: BorderSide(color: c.outlineVariant),
      labelStyle: text.labelMedium,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: BrandColors.peacockMist, // the open tab: one brand pill on every tab
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? BrandColors.peacock : c.onSurfaceVariant),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelSmall?.copyWith(color: s.contains(WidgetState.selected) ? c.onSurface : c.onSurfaceVariant),
      ),
    ),
    // the cart count is good news, not an error: gold, not Material's red
    badgeTheme: BadgeThemeData(backgroundColor: BrandColors.gold, textColor: BrandColors.goldInk, textStyle: text.labelSmall),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
    ),
    dividerTheme: DividerThemeData(color: c.outlineVariant, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
      iconColor: c.onSurfaceVariant,
    ),
  );
}

final lightTheme = buildTheme(lightScheme);
