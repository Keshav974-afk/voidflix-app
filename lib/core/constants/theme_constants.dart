import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Exact Voidflix & Netflix palette
  static const Color primaryRed = Color(0xFFE50914);
  static const Color darkRed = Color(0xFFB81D24);
  static const Color background = Color(0xFF111116);
  static const Color backgroundBlack = Color(0xFF000000);
  static const Color surface = Color(0xFF16161E);
  static const Color surfaceVariant = Color(0xFF1F1F2B);
  static const Color cardColor = Color(0xFF181818);
  static const Color cardHover = Color(0xFF242424);
  static const Color border = Color(0xFF282836);
  static const Color borderSubtle = Color(0x33FFFFFF);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA3A3A3);
  static const Color textMuted = Color(0xFF737373);
  static const Color matchGreen = Color(0xFF46D369); // 98% Match
  static const Color starGold = Color(0xFFFFB800);

  // Glassmorphic chip decoration
  static BoxDecoration glassChip({double radius = 20, Color? borderColor}) {
    return BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? Colors.white.withValues(alpha: 0.2),
        width: 1,
      ),
    );
  }

  // Card decoration with elevation
  static BoxDecoration cardDecoration({double radius = 6}) {
    return BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primaryRed,
      fontFamily: GoogleFonts.inter().fontFamily,
      colorScheme: const ColorScheme.dark(
        primary: primaryRed,
        secondary: darkRed,
        surface: surface,
        onSurface: textPrimary,
      ),
      cardColor: cardColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.bebasNeue(
          color: textPrimary,
          fontSize: 48,
          letterSpacing: 1.5,
        ),
        displayMedium: GoogleFonts.bebasNeue(
          color: textPrimary,
          fontSize: 36,
          letterSpacing: 1.2,
        ),
        headlineMedium: const TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: const TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: const TextStyle(
          color: textPrimary,
          fontSize: 15,
        ),
        bodyMedium: const TextStyle(
          color: textSecondary,
          fontSize: 13,
        ),
      ),
      dividerColor: border,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
