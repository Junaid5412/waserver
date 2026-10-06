import 'package:flutter/material.dart';

class WhatsAppTheme {
  // Primary Palette
  static const Color primaryGreen = Color(0xFF008069);
  static const Color darkAppBar = Color(0xFF075E54);
  static const Color tealGreen = Color(0xFF128C7E);
  static const Color accentGreen = Color(0xFF25D366);
  static const Color fabGreen = Color(0xFF00A884);

  // Chat Bubble Colors
  static const Color bubbleOutLight = Color(0xFFD9FDD3);
  static const Color bubbleInLight = Color(0xFFFFFFFF);
  static const Color bubbleOutDark = Color(0xFF005C4B);
  static const Color bubbleInDark = Color(0xFF202C33);

  // Backgrounds
  static const Color chatBgLight = Color(0xFFEFEAE2);
  static const Color chatBgDark = Color(0xFF0B141A);
  static const Color bgLight = Color(0xFFFFFFFF);
  static const Color bgDark = Color(0xFF111B21);
  static const Color darkBackground = Color(0xFF111B21);
  static const Color surfaceDark = Color(0xFF202C33);

  // Ticks & Badges
  static const Color blueTick = Color(0xFF53BDEB);
  static const Color grayTick = Color(0xFF8696A0);
  static const Color unreadBadge = Color(0xFF25D366);

  // Deleted & Edited Accent Colors
  static const Color deletedRed = Color(0xFFE53935);
  static const Color editedChip = Color(0xFF3B82F6);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: false,
      primaryColor: primaryGreen,
      scaffoldBackgroundColor: bgLight,
      colorScheme: const ColorScheme.light(
        primary: primaryGreen,
        secondary: fabGreen,
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: fabGreen,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: Colors.black54),
        floatingLabelStyle: TextStyle(color: primaryGreen, fontWeight: FontWeight.w600),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: false,
      primaryColor: surfaceDark,
      scaffoldBackgroundColor: bgDark,
      colorScheme: const ColorScheme.dark(
        primary: accentGreen,
        secondary: fabGreen,
        surface: surfaceDark,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: Colors.white70),
        floatingLabelStyle: TextStyle(color: accentGreen, fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceDark,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: fabGreen,
        foregroundColor: Colors.white,
      ),
    );
  }
}
