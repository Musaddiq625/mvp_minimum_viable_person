import 'package:flutter/material.dart';

/// Dark, dim, sloth palette. One accent, one warn color, nothing else
/// competes for attention — lazy people don't want visual noise.
class MvpTheme {
  static const bg = Color(0xFF0F110E);
  static const surface = Color(0xFF1B1E18);
  static const accent = Color(0xFFC4D18C); // sage
  static const accentDim = Color(0x66C4D18C);
  static const warn = Color(0xFFE8865C); // hungry state
  static const text = Color(0xFFE7EAE0);
  static const textMuted = Color(0xFF8A8F82);

  static ThemeData dark() => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          surface: surface,
          primary: accent,
          error: warn,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
              fontSize: 84,
              fontWeight: FontWeight.w200,
              color: text,
              fontFeatures: []),
          bodyLarge: TextStyle(fontSize: 17, color: text),
          bodyMedium: TextStyle(fontSize: 14, color: textMuted),
          labelLarge: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: bg),
        ),
        useMaterial3: true,
      );
}
