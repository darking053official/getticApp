import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ==========================================
  // ORİJİNAL RENK İSİMLERİ (Sizin kullandığınız)
  // ==========================================
  static const Color bgPrimary = Color(0xFF0a0a0f);
  static const Color bgSecondary = Color(0xFF12121a);
  static const Color bgTertiary = Color(0xFF1a1a24);
  static const Color accent = Color(0xFF7c3aed);
  static const Color textPrimary = Color(0xFFf4f4f6);
  static const Color textSecondary = Color(0xFFa1a1b0);
  static const Color border = Color(0xFF1f1f2e);
  static const Color online = Color(0xFF22c55e);
  static const Color danger = Color(0xFFef4444);
  
  // ==========================================
  // ALIAS'LAR (Benim yazdığım kodlarla uyum için)
  // ==========================================
  static const Color background = bgPrimary;
  static const Color surface = bgSecondary;
  static const Color primary = accent;
  static const Color inputBackground = bgTertiary;
  static const Color inputBorder = border;

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgPrimary,
      primaryColor: accent,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: bgSecondary,
        error: danger,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      // Google Fonts Inter entegrasyonu
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme,
      ).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgSecondary,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary, 
          fontSize: 20, 
          fontWeight: FontWeight.bold,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgTertiary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), 
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), 
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), 
          borderSide: const BorderSide(color: accent, width: 2),
        ),
        hintStyle: const TextStyle(color: Color(0xFF6b6b7b)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: bgSecondary,
        contentTextStyle: TextStyle(color: textPrimary),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
      ),
    );
  }
}
