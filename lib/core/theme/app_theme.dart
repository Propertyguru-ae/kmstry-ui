import 'package:flutter/material.dart';

class AppTheme {
  // Requested style:
  // - Matte black background
  // - Turquoise glow accents
  // - Orange CTA
  static const Color matteBlack = Color(0xFF0B0B0D);
  static const Color darkSurface = Color(0xFF15161A);
  static const Color turquoiseGlow = Color(0xFF1FE4D2);
  //static const Color darkCtaOrange = Color(0xFFFF8A2A);
  static const Color darkCtaOrange = Color(0xFFFF6B4A);
  static const Color darkTextPrimary = Color(0xFFF4F6F8);
  static const Color darkTextSecondary = Color(0xFFA6B1BA);

  // Light palette derived from same tones.
  static const Color lightBg = Colors.white;
  static const Color lightSurface = Colors.white;
  static const Color lightPrimaryTurquoise = Color(0xFF0AAFA0);
  //static const Color lightCtaOrange = Color(0xFFF17A1A);
  static const Color lightCtaOrange = Color(0xFFE85D2A);
  static const Color lightTextPrimary = Color(0xFF111827);
  static const Color lightTextSecondary = Color(0xFF5D6B7B);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: lightPrimaryTurquoise,
    colorScheme: const ColorScheme.light(
      primary: lightPrimaryTurquoise,
      secondary: lightCtaOrange,
      surface: lightSurface,
      error: lightCtaOrange,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: lightTextPrimary,
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: lightBg,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: lightCtaOrange,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: lightPrimaryTurquoise),
        foregroundColor: lightPrimaryTurquoise,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    cardTheme: CardThemeData(
      color: lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: lightTextPrimary),
      titleTextStyle: TextStyle(
        color: lightTextPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: lightTextPrimary,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        color: lightTextPrimary,
        fontWeight: FontWeight.bold,
      ),
      bodyLarge: TextStyle(color: lightTextPrimary),
      bodyMedium: TextStyle(color: lightTextSecondary),
    ),
    iconTheme: const IconThemeData(color: lightTextPrimary),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: turquoiseGlow,
    colorScheme: const ColorScheme.dark(
      primary: turquoiseGlow,
      secondary: darkCtaOrange,
      surface: darkSurface,
      error: darkCtaOrange,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: darkTextPrimary,
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: matteBlack,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: darkCtaOrange,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: turquoiseGlow),
        foregroundColor: turquoiseGlow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: darkTextPrimary),
      titleTextStyle: TextStyle(
        color: darkTextPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: darkTextPrimary,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        color: darkTextPrimary,
        fontWeight: FontWeight.bold,
      ),
      bodyLarge: TextStyle(color: darkTextPrimary),
      bodyMedium: TextStyle(color: darkTextSecondary),
    ),
    iconTheme: const IconThemeData(color: darkTextPrimary),
  );
}
