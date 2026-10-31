import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================
// RENK PALETİ (açık ve koyu tema için ayrı değerler)
// Sayfalarda: final c = context.appColors; ... c.surface
// ============================================================
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color background; // Ana arka plan
  final Color surface; // Kartlar, AppBar, alt menü, sheet
  final Color surfaceVariant; // Input alanları, pasif kutular
  final Color border; // Kenarlıklar, ayraçlar
  final Color primary; // Marka / vurgu rengi
  final Color textPrimary; // Ana yazı
  final Color textSecondary; // İkincil yazı
  final Color textHint; // Placeholder
  final Color online; // Çevrimiçi noktası
  final Color danger; // Hata / silme

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.border,
    required this.primary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.online,
    required this.danger,
  });

  /// Mevcut koyu tema renkleri (değişmedi, uygulama kimliği korunuyor)
  static const AppColors dark = AppColors(
    background: Color(0xFF0a0a0f),
    surface: Color(0xFF12121a),
    surfaceVariant: Color(0xFF1a1a24),
    border: Color(0xFF1f1f2e),
    primary: Color(0xFF7c3aed),
    textPrimary: Color(0xFFf4f4f6),
    textSecondary: Color(0xFFa1a1b0),
    textHint: Color(0xFF6b6b7b),
    online: Color(0xFF22c55e),
    danger: Color(0xFFef4444),
  );

  /// Açık tema: aynı marka rengi, okunabilir yüzeyler
  static const AppColors light = AppColors(
    background: Color(0xFFF6F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEFEFF5),
    border: Color(0xFFE3E3EC),
    primary: Color(0xFF7c3aed),
    textPrimary: Color(0xFF16161F),
    textSecondary: Color(0xFF5C5C6C),
    textHint: Color(0xFF9A9AAB),
    online: Color(0xFF22c55e),
    danger: Color(0xFFef4444),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? border,
    Color? primary,
    Color? textPrimary,
    Color? textSecondary,
    Color? textHint,
    Color? online,
    Color? danger,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      border: border ?? this.border,
      primary: primary ?? this.primary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textHint: textHint ?? this.textHint,
      online: online ?? this.online,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      border: Color.lerp(border, other.border, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textHint: Color.lerp(textHint, other.textHint, t)!,
      online: Color.lerp(online, other.online, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// Kullanım: context.appColors.surface
extension AppThemeContext on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.dark;
}

class AppTheme {
  // ==========================================
  // ESKİ SABİTLER (geriye dönük uyumluluk)
  // Mevcut sayfalar AppTheme.surface gibi isimleri kullanmaya devam eder.
  // Bunlar KOYU tema değerleridir. Açık temayı destekleyen sayfalarda
  // bunun yerine context.appColors kullanın.
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

  static const Color background = bgPrimary;
  static const Color surface = bgSecondary;
  static const Color primary = accent;
  static const Color inputBackground = bgTertiary;
  static const Color inputBorder = border;
  static const Color textHint = Color(0xFF6b6b7b);

  // ==========================================
  // TEMALAR
  // ==========================================
  // Not: Inter yazı tipi pubspec.yaml'da tanımlı değilse Flutter varsayılanına
  // düşer. Gerçekten kullanmak için pubspec'e fonts bölümü ekleyin.
  static const String _fontFamily = 'Inter';

  static final ThemeData dark = _build(AppColors.dark, Brightness.dark);
  static final ThemeData light = _build(AppColors.light, Brightness.light);

  /// Eski API ile uyum için (main.dart'ta darkTheme olarak kullanılıyordu)
  static ThemeData get darkTheme => dark;
  static ThemeData get lightTheme => light;

  /// Ayarlar sayfasındaki "Tema" seçeneğini ThemeMode'a çevirir.
  /// 'Karanlık' | 'Aydınlık' | 'Sistem'
  static ThemeMode themeModeFrom(String setting) {
    switch (setting) {
      case 'Aydınlık':
        return ThemeMode.light;
      case 'Sistem':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  static ThemeData _build(AppColors c, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: Colors.white,
      secondary: c.primary,
      onSecondary: Colors.white,
      error: c.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      background: c.background,
      onBackground: c.textPrimary,
      outline: c.border,
    );

    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      primaryColor: c.primary,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: c.border,
      fontFamily: _fontFamily,
      extensions: <ThemeExtension<dynamic>>[c],

      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: c.textPrimary),
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: _fontFamily,
        ),
        systemOverlayStyle: overlay,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: c.textHint, fontSize: 14),
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 14),
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
        border: _outline(c.border),
        enabledBorder: _outline(c.border),
        focusedBorder: _outline(c.primary, width: 1.5),
        errorBorder: _outline(c.danger),
        focusedErrorBorder: _outline(c.danger, width: 1.5),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: c.primary.withOpacity(0.4),
          disabledForegroundColor: Colors.white70,
          // Not: double.infinity, sayfaların tam genişlik butonlarını korur.
          // Row içinde kullanılan butonlar için sayfada SizedBox ile sınırlayın.
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: _fontFamily,
          ),
          elevation: 0,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: _fontFamily,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size(double.infinity, 52),
          side: BorderSide(color: c.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: _fontFamily,
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return Colors.white;
          return c.textSecondary;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return c.primary;
          return c.surfaceVariant;
        }),
        trackOutlineColor: MaterialStateProperty.all(c.border),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return c.primary;
          return Colors.transparent;
        }),
        checkColor: MaterialStateProperty.all(Colors.white),
        side: BorderSide(color: c.textSecondary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      radioTheme: RadioThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return c.primary;
          return c.textSecondary;
        }),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? c.surface : c.textPrimary,
        contentTextStyle: TextStyle(
          color: isDark ? c.textPrimary : Colors.white,
          fontFamily: _fontFamily,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 4,
      ),

      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      // Alt menü, AppBar ile aynı yüzey rengini kullanır (tutarlılık için)
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.primary,
        unselectedItemColor: c.textSecondary,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: _fontFamily,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontFamily: _fontFamily,
        ),
      ),

      dialogTheme: DialogTheme(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: _fontFamily,
        ),
        contentTextStyle: TextStyle(
          color: c.textSecondary,
          fontSize: 14,
          fontFamily: _fontFamily,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ).copyWith(backgroundColor: c.surface, modalBackgroundColor: c.surface),

      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceVariant,
        selectedColor: c.primary,
        disabledColor: c.surfaceVariant,
        labelStyle: TextStyle(color: c.textPrimary, fontFamily: _fontFamily),
        secondaryLabelStyle:
            TextStyle(color: Colors.white, fontFamily: _fontFamily),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: c.border),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surfaceVariant,
        circularTrackColor: c.surfaceVariant,
      ),

      iconTheme: IconThemeData(color: c.textSecondary, size: 24),

      textTheme: _textTheme(c),
    );
  }

  static OutlineInputBorder _outline(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(AppColors c) {
    TextStyle s(Color color, {FontWeight? weight}) => TextStyle(
          color: color,
          fontWeight: weight,
          fontFamily: _fontFamily,
        );

    return TextTheme(
      displayLarge: s(c.textPrimary),
      displayMedium: s(c.textPrimary),
      displaySmall: s(c.textPrimary),
      headlineLarge: s(c.textPrimary, weight: FontWeight.bold),
      headlineMedium: s(c.textPrimary, weight: FontWeight.bold),
      headlineSmall: s(c.textPrimary, weight: FontWeight.w600),
      titleLarge: s(c.textPrimary, weight: FontWeight.w600),
      titleMedium: s(c.textPrimary, weight: FontWeight.w500),
      titleSmall: s(c.textPrimary, weight: FontWeight.w500),
      bodyLarge: s(c.textPrimary),
      bodyMedium: s(c.textPrimary),
      bodySmall: s(c.textSecondary),
      labelLarge: s(c.textPrimary, weight: FontWeight.w600),
      labelMedium: s(c.textSecondary),
      labelSmall: s(c.textSecondary),
    );
  }
}
