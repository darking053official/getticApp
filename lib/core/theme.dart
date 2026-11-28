// ============================================================
// lib/core/theme.dart
// (.txt olarak verildi. Projeye eklerken adını theme.dart yapın.)
// Modern tema: daha canlı marka rengi, yumuşak yüzeyler, yuvarlak köşeler,
// hafif kenarlıklar, sıkı başlık tipografisi.
// Sayfalardaki isimler (AppTheme.primary, context.appColors vb.) aynen korunur.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

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

  /// Koyu tema: derin lacivert-siyah zemin, canlı violet vurgu
  static const AppColors dark = AppColors(
    background: Color(0xFF0B0B10),
    surface: Color(0xFF15151D),
    surfaceVariant: Color(0xFF1F1F2A),
    border: Color(0xFF26263A),
    primary: Color(0xFF8B5CF6),
    textPrimary: Color(0xFFF5F5FA),
    textSecondary: Color(0xFFA3A3B8),
    textHint: Color(0xFF6E6E84),
    online: Color(0xFF34D399),
    danger: Color(0xFFF87171),
  );

  /// Açık tema: temiz beyaz yüzeyler, aynı marka ailesi
  static const AppColors light = AppColors(
    background: Color(0xFFF5F5F9),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEEEEF4),
    border: Color(0xFFE2E2EC),
    primary: Color(0xFF7C3AED),
    textPrimary: Color(0xFF111118),
    textSecondary: Color(0xFF5B5B70),
    textHint: Color(0xFF9B9BAE),
    online: Color(0xFF10B981),
    danger: Color(0xFFEF4444),
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
  // Bunlar KOYU tema değerleridir. Açık temayı destekleyen sayfalarda
  // context.appColors kullanın.
  // ==========================================
  static const Color bgPrimary = Color(0xFF0B0B10);
  static const Color bgSecondary = Color(0xFF15151D);
  static const Color bgTertiary = Color(0xFF1F1F2A);
  static const Color accent = Color(0xFF8B5CF6);
  static const Color textPrimary = Color(0xFFF5F5FA);
  static const Color textSecondary = Color(0xFFA3A3B8);
  static const Color border = Color(0xFF26263A);
  static const Color online = Color(0xFF34D399);
  static const Color danger = Color(0xFFF87171);

  static const Color background = bgPrimary;
  static const Color surface = bgSecondary;
  static const Color primary = accent;
  static const Color inputBackground = bgTertiary;
  static const Color inputBorder = border;
  static const Color textHint = Color(0xFF6E6E84);

  // ==========================================
  // TEMALAR
  // ==========================================
  // Not: Inter yazı tipi pubspec.yaml'da tanımlı değilse Flutter varsayılanına
  // düşer. Gerçekten kullanmak için pubspec'e fonts bölümü ekleyin.
  static String? _fontFamily = 'Inter';

  static final ThemeData dark = _build(AppColors.dark, Brightness.dark);
  static final ThemeData light = _build(AppColors.light, Brightness.light);

  /// Ayarlardan gelen renk ve yazı tipiyle tema üretir.
  static ThemeData build({
    required Brightness brightness,
    String accent = 'violet',
    String font = 'default',
  }) {
    _fontFamily = _fontFamilyFor(font);
    final dark = brightness == Brightness.dark;
    final base = dark ? AppColors.dark : AppColors.light;
    return _build(base.copyWith(primary: _accentFor(accent, dark)), brightness);
  }

  static String? _fontFamilyFor(String key) {
    switch (key) {
      case 'inter':
        return GoogleFonts.inter().fontFamily;
      case 'poppins':
        return GoogleFonts.poppins().fontFamily;
      case 'nunito':
        return GoogleFonts.nunito().fontFamily;
      case 'lora':
        return GoogleFonts.lora().fontFamily;
      case 'montserrat':
        return GoogleFonts.montserrat().fontFamily;
      default:
        return null;
    }
  }

  static Color _accentFor(String key, bool dark) {
    const map = <String, List<Color>>{
      'violet': [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
      'blue': [Color(0xFF60A5FA), Color(0xFF2563EB)],
      'teal': [Color(0xFF2DD4BF), Color(0xFF0D9488)],
      'pink': [Color(0xFFF472B6), Color(0xFFDB2777)],
      'orange': [Color(0xFFFB923C), Color(0xFFEA580C)],
      'green': [Color(0xFF4ADE80), Color(0xFF16A34A)],
    };
    final pair = map[key] ?? map['violet']!;
    return dark ? pair[0] : pair[1];
  }

  /// Eski API ile uyum için
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

  // Modern köşe yarıçapları
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 22;

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
      surfaceVariant: c.surfaceVariant,
      onSurfaceVariant: c.textSecondary,
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
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: c.textPrimary),
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          fontFamily: _fontFamily,
        ),
        systemOverlayStyle: overlay,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        hintStyle: TextStyle(color: c.textHint, fontSize: 14),
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 14),
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
        border: _outline(Colors.transparent, radiusMd),
        enabledBorder: _outline(Colors.transparent, radiusMd),
        focusedBorder: _outline(c.primary, radiusMd, width: 1.5),
        errorBorder: _outline(c.danger, radiusMd),
        focusedErrorBorder: _outline(c.danger, radiusMd, width: 1.5),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: c.primary.withOpacity(0.35),
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
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
          minimumSize: const Size(double.infinity, 54),
          side: BorderSide(color: c.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: _fontFamily,
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
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
        trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return c.primary;
          return Colors.transparent;
        }),
        checkColor: MaterialStateProperty.all(Colors.white),
        side: BorderSide(color: c.textSecondary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),

      radioTheme: RadioThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return c.primary;
          return c.textSecondary;
        }),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? c.surfaceVariant : c.textPrimary,
        contentTextStyle: TextStyle(
          color: isDark ? c.textPrimary : Colors.white,
          fontFamily: _fontFamily,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        elevation: 0,
      ),

      dividerTheme: DividerThemeData(
        color: c.border.withOpacity(0.6),
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

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
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          fontFamily: _fontFamily,
        ),
        contentTextStyle: TextStyle(
          color: c.textSecondary,
          fontSize: 14,
          height: 1.4,
          fontFamily: _fontFamily,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceVariant,
        selectedColor: c.primary,
        disabledColor: c.surfaceVariant,
        labelStyle: TextStyle(color: c.textPrimary, fontFamily: _fontFamily),
        secondaryLabelStyle:
            TextStyle(color: Colors.white, fontFamily: _fontFamily),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        side: BorderSide.none,
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

  static OutlineInputBorder _outline(Color color, double radius,
      {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(AppColors c) {
    TextStyle s(Color color, {FontWeight? weight, double? spacing}) => TextStyle(
          color: color,
          fontWeight: weight,
          letterSpacing: spacing,
          fontFamily: _fontFamily,
        );

    return TextTheme(
      displayLarge: s(c.textPrimary, weight: FontWeight.w800, spacing: -1),
      displayMedium: s(c.textPrimary, weight: FontWeight.w800, spacing: -0.8),
      displaySmall: s(c.textPrimary, weight: FontWeight.w700, spacing: -0.6),
      headlineLarge: s(c.textPrimary, weight: FontWeight.w800, spacing: -0.6),
      headlineMedium: s(c.textPrimary, weight: FontWeight.w700, spacing: -0.5),
      headlineSmall: s(c.textPrimary, weight: FontWeight.w700, spacing: -0.4),
      titleLarge: s(c.textPrimary, weight: FontWeight.w700, spacing: -0.3),
      titleMedium: s(c.textPrimary, weight: FontWeight.w600, spacing: -0.2),
      titleSmall: s(c.textPrimary, weight: FontWeight.w600),
      bodyLarge: s(c.textPrimary, spacing: -0.1),
      bodyMedium: s(c.textPrimary, spacing: -0.1),
      bodySmall: s(c.textSecondary),
      labelLarge: s(c.textPrimary, weight: FontWeight.w600),
      labelMedium: s(c.textSecondary, weight: FontWeight.w500),
      labelSmall: s(c.textSecondary, weight: FontWeight.w500),
    );
  }
}
