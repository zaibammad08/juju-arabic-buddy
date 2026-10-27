import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens from BUILD_GUIDE.md (mint lesson palette). No other colours.
class AppColors {
  static const bg = Color(0xFFE6F7F4);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF0FAF8);
  static const ink = Color(0xFF0B2A3D);
  static const muted = Color(0xFF4C6A7A);
  static const accent = Color(0xFFF5B83D); // My Letter, Listen
  static const accentShadow = Color(0xFFC98A12);
  static const good = Color(0xFF1FA67A); // Treasure Hunt, Say it!, success
  static const goodShadow = Color(0xFF13775A);
  static const highlight = Color(0xFFE5536B); // the letter inside words
  static const blue = Color(0xFF1A8FB0); // links, passport
  static const line = Color(0xFFCDE7EC); // borders, card shadows
  static const tip = Color(0xFFFFF5DA); // parent tips
  static const masculine = Color(0xFF2F6FDE);
  static const feminine = Color(0xFFF08A24);
  static const feminineBadge = Color(0xFFB45309);
}

class AppTheme {
  static const double radius = 30; // buttons 26–34
  static const double shadowDepth = 6; // solid bottom shadow 5–7 px
  static const double minTap = 64; // kids' tap targets ≥ 64 px

  /// Arabic text style (Baloo Bhaijaan 2). Always pair with TextDirection.rtl.
  static TextStyle arabic({
    double size = 32,
    Color color = AppColors.ink,
    FontWeight weight = FontWeight.w700,
  }) => GoogleFonts.balooBhaijaan2(
    fontSize: size,
    color: color,
    fontWeight: weight,
    height: 1.7, // room for full vowel marks above and below
  );

  /// English text style (Baloo 2).
  static TextStyle english({
    double size = 18,
    Color color = AppColors.ink,
    FontWeight weight = FontWeight.w600,
  }) => GoogleFonts.baloo2(fontSize: size, color: color, fontWeight: weight);

  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.good,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.good,
          onPrimary: Colors.white,
          secondary: AppColors.accent,
          onSecondary: AppColors.ink,
          tertiary: AppColors.blue,
          surface: AppColors.surface,
          onSurface: AppColors.ink,
          outline: AppColors.line,
        );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final buttonText = GoogleFonts.baloo2(
      fontSize: 20,
      fontWeight: FontWeight.w700,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: GoogleFonts.baloo2TextTheme(
        base.textTheme,
      ).apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: english(size: 22, weight: FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(minTap, minTap),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: buttonShape,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minTap, minTap),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: buttonShape,
          side: const BorderSide(color: AppColors.line, width: 2),
          foregroundColor: AppColors.ink,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(minTap, minTap)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.good,
        linearTrackColor: AppColors.line,
      ),
      dividerColor: AppColors.line,
    );
  }
}
