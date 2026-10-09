import 'package:flutter/material.dart';

abstract final class SalinTheme {
  static const yellow = Color(0xFFFFBA08);
  static const ink = Color(0xFF000000);
  static const muted = Color(0xFF626262);

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: yellow,
        primary: ink,
        onPrimary: Colors.white,
        secondary: yellow,
        onSecondary: ink,
        surface: Colors.white,
        onSurface: ink,
      ),
    );
    const heading = TextStyle(
      fontFamily: 'Plus Jakarta Sans',
      fontWeight: FontWeight.w800,
      color: ink,
      height: 1.2,
      letterSpacing: -0.8,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return base.copyWith(
      iconTheme: const IconThemeData(color: ink),
      textTheme: base.textTheme.copyWith(
        headlineLarge: heading.copyWith(fontSize: 36),
        headlineMedium: heading.copyWith(fontSize: 30),
        headlineSmall: heading.copyWith(fontSize: 26),
        titleLarge: heading.copyWith(fontSize: 22),
        titleMedium: heading.copyWith(fontSize: 18),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 56),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: ink,
          side: const BorderSide(color: ink),
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape.copyWith(side: const BorderSide(color: Color(0xFFE5E5E5))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: ink, width: 2),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: yellow),
    );
  }
}
