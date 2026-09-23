import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The academy's palette, copied by value from the web dashboard.
///
/// There is no shared file to derive these from — the dashboard is CSS and
/// this is Dart — so they are written out here and must move with
/// `haya/web/app/globals.css` if it moves. The neutrals there are OKLCH; the
/// hexes below are those values converted, not re-picked by eye.
///
/// The brand teal comes from the logo itself. It is right for chrome (buttons,
/// the selected tab) and wrong for data marks: at chroma 0.092 it reads grey
/// next to other marks, which is why charts use [AppColors.viz] instead.
abstract final class AppColors {
  static const canvas = Color(0xFFF6FBFB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF3F8F8);

  static const brand = Color(0xFF27908B);
  static const brandSoft = Color(0xFFEAF4F3);
  static const brandDeep = Color(0xFF1B6A66);

  // The brain's blue and the tree's sage — warmth without shouting.
  static const sky = Color(0xFFA8CCD8);
  static const skySoft = Color(0xFFEEF5F8);
  static const sage = Color(0xFFC0CCA8);
  static const sageSoft = Color(0xFFF3F6EC);
  static const leaf = Color(0xFF6C8484);

  static const good = Color(0xFF00908B);
  static const goodSoft = Color(0xFFE8F5F4);
  static const warn = Color(0xFFD99A1A);
  static const warnSoft = Color(0xFFFDF5E4);
  static const bad = Color(0xFFB03030);
  static const badSoft = Color(0xFFFBECEB);
  static const info = Color(0xFF2A78D6);
  static const infoSoft = Color(0xFFE9F1FB);

  static const ink = Color(0xFF172122);
  static const inkSoft = Color(0xFF394545);
  static const muted = Color(0xFF626F6F);
  static const faint = Color(0xFF93A0A0);
  static const line = Color(0xFFDFE6E7);
  static const lineSoft = Color(0xFFECF1F2);

  /// The chart teal — the logo's nearest sibling that clears the validator.
  static const viz = Color(0xFF00908B);

  /// A word from the app, a colour from the palette. Kept as words so a status
  /// is coloured the same way on every screen without each one choosing.
  static Color byName(String? tone) => switch (tone) {
        'good' => good,
        'warn' => warn,
        'bad' => bad,
        'info' => info,
        'brand' => brand,
        'leaf' => leaf,
        _ => muted,
      };

  static Color softByName(String? tone) => switch (tone) {
        'good' => goodSoft,
        'warn' => warnSoft,
        'bad' => badSoft,
        'info' => infoSoft,
        'brand' => brandSoft,
        'leaf' => sageSoft,
        _ => lineSoft,
      };
}

/// The prompt scale, 0..4 — an ordinal ramp on one hue, validated on the web
/// (`--viz-level-*`). Darker means the child needed less holding, so the
/// weight of a mark lands before its label is read.
abstract final class LevelColors {
  static const _ramp = [
    Color(0xFF71C5C2),
    Color(0xFF33ABA8),
    Color(0xFF00908B),
    Color(0xFF007270),
    Color(0xFF005453),
  ];

  static Color fill(int level) => _ramp[level.clamp(0, 4)];

  /// Ink on a swatch: the two lightest steps take dark ink, the rest white —
  /// computed from the step, so no swatch is ever white-on-pale.
  static Color ink(int level) => level <= 1 ? const Color(0xFF04302B) : Colors.white;
}

/// The four programmes. Identity, so a categorical set — in the validated
/// order; teal↔magenta and blue↔magenta are the pairs that fail if shuffled.
abstract final class SpecialtyColors {
  static Color of(String? specialty) => switch (specialty) {
        'speech' => const Color(0xFF00908B),
        'occupational' => const Color(0xFFEB6834),
        'behavioral' => const Color(0xFF2A78D6),
        'special_ed' => const Color(0xFFC2559B),
        _ => AppColors.leaf,
      };
}

abstract final class AppShape {
  static const card = BorderRadius.all(Radius.circular(18));
  static const control = BorderRadius.all(Radius.circular(12));
  static const chip = BorderRadius.all(Radius.circular(999));

  /// Tinted with the brand's own teal rather than black — a neutral shadow on
  /// a tinted page reads as grey dirt under the card. Very soft and wide: a
  /// calm app for a tired reader.
  static const cardShadow = [
    BoxShadow(color: Color(0x0D1B6A66), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x171B6A66), blurRadius: 14, spreadRadius: -4, offset: Offset(0, 4)),
  ];
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    primary: AppColors.brand,
    surface: AppColors.surface,
    error: AppColors.bad,
  );

  /*
   * Arabic glyphs sit tighter than Latin at the same size, so every style gets
   * more line height than Material's default. Without it the descenders of one
   * line touch the next line's diacritics — and the report screen is prose a
   * mother reads at ten at night, set at reading sizes, not dashboard sizes.
   */
  TextStyle ar(double size, FontWeight weight, Color color) => TextStyle(
        fontFamily: 'Cairo',
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.6,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    fontFamily: 'Cairo',
    splashFactory: InkSparkle.splashFactory,

    textTheme: TextTheme(
      displaySmall: ar(28, FontWeight.w800, AppColors.ink),
      headlineMedium: ar(22, FontWeight.w800, AppColors.ink),
      headlineSmall: ar(19, FontWeight.w700, AppColors.ink),
      titleLarge: ar(17, FontWeight.w700, AppColors.ink),
      titleMedium: ar(15, FontWeight.w700, AppColors.ink),
      titleSmall: ar(13, FontWeight.w600, AppColors.muted),
      bodyLarge: ar(15.5, FontWeight.w400, AppColors.ink),
      bodyMedium: ar(14, FontWeight.w400, AppColors.ink),
      bodySmall: ar(12.5, FontWeight.w400, AppColors.muted),
      labelLarge: ar(14, FontWeight.w600, AppColors.ink),
      labelMedium: ar(12, FontWeight.w600, AppColors.muted),
      labelSmall: ar(11, FontWeight.w400, AppColors.faint),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: const IconThemeData(color: AppColors.ink),
      titleTextStyle: ar(18, FontWeight.w800, AppColors.ink),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),

    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: AppShape.card),
    ),

    dividerTheme: const DividerThemeData(color: AppColors.lineSoft, thickness: 1, space: 1),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.line,
        disabledForegroundColor: AppColors.faint,
        minimumSize: const Size.fromHeight(50),
        shape: const RoundedRectangleBorder(borderRadius: AppShape.control),
        textStyle: ar(15, FontWeight.w700, Colors.white),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: AppColors.line),
        shape: const RoundedRectangleBorder(borderRadius: AppShape.control),
        textStyle: ar(15, FontWeight.w600, AppColors.ink),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brand,
        textStyle: ar(14, FontWeight.w700, AppColors.brand),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: ar(14, FontWeight.w400, AppColors.faint),
      labelStyle: ar(13, FontWeight.w600, AppColors.muted),
      floatingLabelStyle: ar(13, FontWeight.w700, AppColors.brand),
      border: const OutlineInputBorder(
        borderRadius: AppShape.control,
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: AppShape.control,
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: AppShape.control,
        borderSide: BorderSide(color: AppColors.brand, width: 1.6),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: AppShape.control,
        borderSide: BorderSide(color: AppColors.bad),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: AppShape.control,
        borderSide: BorderSide(color: AppColors.bad, width: 1.6),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.brandSoft,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => ar(
          11.5,
          states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          states.contains(WidgetState.selected) ? AppColors.brand : AppColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected) ? AppColors.brand : AppColors.muted,
        ),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.brandDeep,
      contentTextStyle: ar(14, FontWeight.w500, Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AppShape.control),
      insetPadding: const EdgeInsets.all(16),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppShape.card),
      titleTextStyle: ar(17, FontWeight.w700, AppColors.ink),
      contentTextStyle: ar(14, FontWeight.w400, AppColors.inkSoft),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.brandSoft,
      side: const BorderSide(color: AppColors.line),
      shape: const RoundedRectangleBorder(borderRadius: AppShape.chip),
      labelStyle: ar(12.5, FontWeight.w600, AppColors.inkSoft),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      showCheckmark: false,
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.brand,
      linearTrackColor: AppColors.lineSoft,
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.brand,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: AppShape.control),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: AppColors.muted,
      titleTextStyle: ar(14.5, FontWeight.w600, AppColors.ink),
      subtitleTextStyle: ar(12.5, FontWeight.w400, AppColors.muted),
    ),
  );
}
