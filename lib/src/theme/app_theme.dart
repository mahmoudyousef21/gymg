import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const background = Color(0xFF0E0E0E);
  static const surface = Color(0xFF0E0E0E);
  static const surfaceLow = Color(0xFF131313);
  static const surfaceHigh = Color(0xFF201F1F);
  static const surfaceHighest = Color(0xFF262626);
  static const surfaceBright = Color(0xFF2C2C2C);

  static const primary = Color(0xFF81ECFF);
  static const primaryContainer = Color(0xFF00E3FD);
  static const secondary = Color(0xFFFF734A);
  static const secondaryContainer = Color(0xFFB02F00);
  static const lime = Color(0xFFC1FF00);
  static const blue = Color(0xFF81ECFF);
  static const yellow = Color(0xFFFFD96A);

  static const onSurface = Color(0xFFFFFFFF);
  static const onSurfaceVariant = Color(0xFFADAAAA);
  static const outline = Color(0xFF494847);
}

class AppTheme {
  static ThemeData dark({
    Color primary = AppColors.primary,
    Color secondary = AppColors.secondary,
  }) {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
    final onPrimary = ThemeData.estimateBrightnessForColor(primary) ==
            Brightness.dark
        ? Colors.white
        : Colors.black;
    final primaryContainer = Color.alphaBlend(
      primary.withValues(alpha: 0.35),
      AppColors.surfaceHighest,
    );
    final onPrimaryContainer = ThemeData.estimateBrightnessForColor(
              primaryContainer,
            ) ==
            Brightness.dark
        ? Colors.white
        : Colors.black;

    final textTheme = GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.ibmPlexSansArabic(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
        color: AppColors.onSurface,
      ),
      displayMedium: GoogleFonts.ibmPlexSansArabic(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: AppColors.onSurface,
      ),
      headlineMedium: GoogleFonts.ibmPlexSansArabic(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.onSurface,
      ),
      titleLarge: GoogleFonts.ibmPlexSansArabic(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
        color: AppColors.onSurface,
      ),
      titleMedium: GoogleFonts.ibmPlexSansArabic(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: AppColors.onSurface,
      ),
      bodyLarge: GoogleFonts.ibmPlexSansArabic(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: GoogleFonts.ibmPlexSansArabic(
        color: AppColors.onSurface,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: GoogleFonts.ibmPlexSansArabic(
        color: AppColors.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
      labelLarge: GoogleFonts.ibmPlexSansArabic(
        color: AppColors.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 0.9,
      ),
      labelMedium: GoogleFonts.ibmPlexSansArabic(
        color: AppColors.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        fontSize: 10,
        letterSpacing: 1.0,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: const Color(0xFF430C00),
        secondaryContainer: AppColors.secondaryContainer,
        onSecondaryContainer: const Color(0xFFFFF6F4),
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: AppColors.surfaceLow,
        surfaceContainerHighest: AppColors.surfaceHighest,
        outline: AppColors.outline,
      ),
      textTheme: textTheme,
      dividerColor: Colors.transparent,
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surfaceLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.outline.withValues(alpha: 0.15)),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.onSurface,
        iconTheme: const IconThemeData(color: AppColors.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHighest,
        floatingLabelStyle: TextStyle(color: primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.14)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary.withValues(alpha: 0.65)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        circularTrackColor: AppColors.surfaceHighest,
        linearTrackColor: AppColors.surfaceHighest,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: onPrimary,
          backgroundColor: primary,
          elevation: 0,
          textStyle: GoogleFonts.ibmPlexSansArabic(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: onPrimary,
          backgroundColor: primary,
          textStyle: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onSurface,
          side: BorderSide(color: AppColors.outline.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: AppColors.outline.withValues(alpha: 0.24)),
        backgroundColor: AppColors.surfaceHighest,
        selectedColor: primary.withValues(alpha: 0.18),
        checkmarkColor: primary,
        labelStyle: GoogleFonts.ibmPlexSansArabic(
          color: AppColors.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceLow.withValues(alpha: 0.6),
        indicatorColor: primary.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: primary);
          }
          return const IconThemeData(color: AppColors.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.ibmPlexSansArabic(
            color: selected ? primary : AppColors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            letterSpacing: 0.9,
          );
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.black;
          }
          return AppColors.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary;
          }
          return AppColors.surfaceHighest;
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: GoogleFonts.ibmPlexSansArabic(
          color: AppColors.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
