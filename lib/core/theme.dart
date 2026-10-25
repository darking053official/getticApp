import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // ==========================================
  // ORİJİNAL RENKLER (Tüm sayfalarda kullanılan)
  // ==========================================
  static const Color bgPrimary = Color(0xFF0a0a0f);       // Ana arka plan
  static const Color bgSecondary = Color(0xFF12121a);     // Kartlar, Sidebar, AppBar
  static const Color bgTertiary = Color(0xFF1a1a24);      // Input alanları
  static const Color accent = Color(0xFF7c3aed);          // Mor vurgu rengi
  static const Color textPrimary = Color(0xFFf4f4f6);     // Ana yazı rengi
  static const Color textSecondary = Color(0xFFa1a1b0);   // İkincil yazı
  static const Color border = Color(0xFF1f1f2e);          // Kenarlık
  static const Color online = Color(0xFF22c55e);          // Yeşil online noktası
  static const Color danger = Color(0xFFef4444);          // Kırmızı hata

  // ==========================================
  // ALIAS'LAR (Alternatif isimler - bazı dosyalarda kullanılıyor)
  // ==========================================
  static const Color background = bgPrimary;
  static const Color surface = bgSecondary;
  static const Color primary = accent;
  static const Color inputBackground = bgTertiary;
  static const Color inputBorder = border;
  static const Color textHint = Color(0xFF6b6b7b);

  // ==========================================
  // TEMA
  // ==========================================
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: accent,
      scaffoldBackgroundColor: bgPrimary,
      canvasColor: bgPrimary,
      dividerColor: border,
      
      // Renk Şeması
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: Colors.white,
        secondary: accent,
        onSecondary: Colors.white,
        surface: bgSecondary,
        onSurface: textPrimary,
        error: danger,
        onError: Colors.white,
        background: bgPrimary,
        onBackground: textPrimary,
        outline: border,
      ),

      // Yazı Tipi Ailesi (Inter fontu için Google Fonts kullanılıyor)
      fontFamily: 'Inter',

      // AppBar Teması
      appBarTheme: const AppBarTheme(
        backgroundColor: bgSecondary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: 'Inter',
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),

      // Input Teması (TextField'lar için)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgTertiary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: textHint, fontSize: 14),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
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
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
      ),

      // Buton Teması
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: accent.withOpacity(0.4),
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
          elevation: 0,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(double.infinity, 52),
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ),

      // Floating Action Button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      // Switch (Gizlilik ayarları için)
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return Colors.white;
          return textSecondary;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return accent;
          return bgTertiary;
        }),
        trackOutlineColor: MaterialStateProperty.resolveWith((states) {
          return border;
        }),
      ),

      // Checkbox
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return accent;
          return Colors.transparent;
        }),
        checkColor: MaterialStateProperty.all(Colors.white),
        side: const BorderSide(color: textSecondary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      // Radio
      radioTheme: RadioThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return accent;
          return textSecondary;
        }),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgSecondary,
        contentTextStyle: const TextStyle(
          color: textPrimary,
          fontFamily: 'Inter',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 4,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),

      // ListTile
      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      // BottomNavigationBar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bgPrimary,
        selectedItemColor: accent,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontFamily: 'Inter',
        ),
      ),

      // Dialog
      dialogTheme: DialogTheme(
        backgroundColor: bgSecondary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'Inter',
        ),
        contentTextStyle: const TextStyle(
          color: textSecondary,
          fontSize: 14,
          fontFamily: 'Inter',
        ),
      ),

      // Modal Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: bgSecondary,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: bgTertiary,
        selectedColor: accent,
        disabledColor: bgTertiary,
        labelStyle: const TextStyle(color: textPrimary, fontFamily: 'Inter'),
        secondaryLabelStyle: const TextStyle(color: Colors.white, fontFamily: 'Inter'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: const BorderSide(color: border),
      ),

      // Progress Indicator
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: bgTertiary,
        circularTrackColor: bgTertiary,
      ),

      // Icon Teması
      iconTheme: const IconThemeData(
        color: textSecondary,
        size: 24,
      ),

      // Metin Teması (Text Style'ları)
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: textPrimary, fontFamily: 'Inter'),
        displayMedium: TextStyle(color: textPrimary, fontFamily: 'Inter'),
        displaySmall: TextStyle(color: textPrimary, fontFamily: 'Inter'),
        headlineLarge: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.bold,
          fontFamily: 'Inter',
        ),
        headlineMedium: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.bold,
          fontFamily: 'Inter',
        ),
        headlineSmall: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w500,
          fontFamily: 'Inter',
        ),
        titleSmall: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w500,
          fontFamily: 'Inter',
        ),
        bodyLarge: TextStyle(color: textPrimary, fontFamily: 'Inter'),
        bodyMedium: TextStyle(color: textPrimary, fontFamily: 'Inter'),
        bodySmall: TextStyle(color: textSecondary, fontFamily: 'Inter'),
        labelLarge: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
        labelMedium: TextStyle(color: textSecondary, fontFamily: 'Inter'),
        labelSmall: TextStyle(color: textSecondary, fontFamily: 'Inter'),
      ),
    );
  }
}
