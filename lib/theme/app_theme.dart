import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Near Hotel–inspired tokens — forest, sage, mustard, serif display.
class AppColors {
  static const bg = Color(0xFFE8EFE8);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF3F7F3);
  static const border = Color(0xFFC5D4C8);
  static const forest = Color(0xFF0B3D2E);
  static const accent = forest;
  static const cta = Color(0xFFF5C518);
  static const onCta = Color(0xFF0B3D2E);
  static const success = Color(0xFF2E7D4F);
  static const danger = Color(0xFFC62828);
  static const warning = Color(0xFFD4A017);
  static const text = Color(0xFF0B3D2E);
  static const muted = Color(0xFF5A6F62);
  static const feed = Color(0xFF0B3D2E);
  static const feedText = Color(0xFFD4E0D8);
  static const overlay = Color(0x990B3D2E);
  static const chartPitch = Color(0xFFE8A317);
  static const chartYaw = Color(0xFF4A7C6F);
  static const chartGx = Color(0xFFC45C5C);
  static const chartGy = Color(0xFF5A9B6D);
  static const chartGz = Color(0xFF6B8FBF);
}

class AppFonts {
  static TextStyle display({
    double fontSize = 18,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
    double? height,
  }) {
    return GoogleFonts.playfairDisplay(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.text,
      height: height,
    );
  }

  static TextStyle body({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
    double? height,
  }) {
    return GoogleFonts.dmSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.text,
      height: height,
    );
  }
}

class AppTheme {
  static const radiusSm = 10.0;
  static const radiusMd = 16.0;
  static const radiusLg = 20.0;

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: GoogleFonts.dmSans().fontFamily,
      colorScheme: const ColorScheme.light(
        primary: AppColors.forest,
        secondary: AppColors.cta,
        surface: AppColors.surface,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSecondary: AppColors.onCta,
        onSurface: AppColors.text,
      ),
    );

    final textTheme = GoogleFonts.dmSansTextTheme(base.textTheme).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        titleLarge: AppFonts.display(fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: AppFonts.display(fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall: AppFonts.display(fontSize: 14, fontWeight: FontWeight.w600),
        headlineSmall: AppFonts.display(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppFonts.display(fontSize: 18, fontWeight: FontWeight.w700),
        iconTheme: const IconThemeData(color: AppColors.text),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        labelStyle: AppFonts.body(fontSize: 13, color: AppColors.muted),
        hintStyle: AppFonts.body(fontSize: 13, color: AppColors.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.forest, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cta,
          foregroundColor: AppColors.onCta,
          minimumSize: const Size.fromHeight(48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          textStyle: AppFonts.body(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.forest,
          minimumSize: const Size.fromHeight(44),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          textStyle: AppFonts.body(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.forest,
          textStyle: AppFonts.body(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        height: 44,
        indicatorColor: AppColors.forest.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AppFonts.body(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.forest : AppColors.muted,
          ).copyWith(height: 1.1);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 18,
            color: selected ? AppColors.forest : AppColors.muted,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.forest,
        contentTextStyle: AppFonts.body(fontSize: 13, color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerColor: AppColors.border,
      cardColor: AppColors.surface,
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        titleTextStyle: AppFonts.display(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.forest;
          return null;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.cta;
          return AppColors.muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.forest.withValues(alpha: 0.35);
          }
          return AppColors.border;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface2,
        selectedColor: AppColors.forest,
        disabledColor: AppColors.surface2,
        labelStyle: AppFonts.body(fontSize: 11, fontWeight: FontWeight.w600),
        secondaryLabelStyle: AppFonts.body(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
    );
  }

  /// Kept for any callers still referencing `.dark`.
  static ThemeData get dark => light;
}
