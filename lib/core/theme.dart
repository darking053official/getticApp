import 'package:flutter/material.dart';

class GetticTheme {
  // --- WEB PROJESİ İLE BİREBİR AYNI RENKLER ---
  static const Color bgPrimary = Color(0xFF0a0a0f);      // Ana arka plan (En koyu)
  static const Color bgSecondary = Color(0xFF12121a);    // Kartlar, Sidebar
  static const Color bgTertiary = Color(0xFF1a1a24);     // Input alanları, gri mesaj balonları
  static const Color bgHover = Color(0xFF22222e);        // Hover efektleri
  
  static const Color accent = Color(0xFF7c3aed);         // Mor vurgu (Butonlar, kendi mesajlarım)
  static const Color accentHover = Color(0xFF8b5cf6);    // Mor hover
  
  static const Color textPrimary = Color(0xFFf4f4f6);    // Beyaz yazılar
  static const Color textSecondary = Color(0xFFa1a1b0);  // Gri yazılar
  static const Color textMuted = Color(0xFF6b6b7b);      // Soluk yazılar (Placeholder vb.)
  
  static const Color border = Color(0xFF1f1f2e);         // İnce kenarlıklar
  static const Color online = Color(0xFF22c55e);         // Çevrimiçi yeşili
  static const Color danger = Color(0xFFef4444);         // Hata kırmızısı

  // --- TEMA YAPILANDIRMASI ---
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgPrimary,
      primaryColor: accent,
      useMaterial3: true,
      
      // Renk Şeması
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentHover,
        surface: bgSecondary,
        error: danger,
      ),

      // Uygulama Çubuğu (AppBar)
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

      // Input (TextField) Tasarımı
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgTertiary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        
        // Kenarlıklar
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger),
        ),
        
        // Placeholder (Hint) Rengi
        hintStyle: const TextStyle(color: textMuted, fontSize: 15),
      ),

      // Buton Tasarımı
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Metin Butonları
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
        ),
      ),

      // Diller ve Genel Yazı Tipi
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: textPrimary, fontSize: 14),
        bodySmall: TextStyle(color: textSecondary, fontSize: 12),
        titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
      ),

      // Ayırıcı Çizgiler (Divider)
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      
      // Bottom Sheet (Mobildeki Arama Ekranı İçin)
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}
