// ============================================================
// lib/core/app_settings.dart
// (Bu dosya .txt olarak verildi. Projeye eklerken adını
//  app_settings.dart yapın ve lib/core/ klasörüne koyun.)
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cihazda saklanan uygulama ayarları.
///
/// Kullanım:
///   await AppSettings.instance.ensureLoaded();
///   final s = AppSettings.instance;
///   await s.update(() => s.fontScale = 1.2);
///
/// Değişiklik kaydedilir ve dinleyenler (ListenableBuilder vb.) yeniden çizilir.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const String _p = 'settings_';

  SharedPreferences? _prefs;
  Future<void>? _loading;
  bool get isLoaded => _prefs != null;

  // ---- Gizlilik ----
  bool showReadReceipts = true;
  bool showTypingIndicator = true;
  bool blockUnknownMessages = false;

  // ---- Bildirimler ----
  bool notifSound = true;
  bool notifVibrate = true;
  bool notifPreview = true;
  bool notifLed = true;
  bool notifGroupSummary = true;
  String notifSoundTone = 'Varsayılan';

  // ---- Görünüm ----
  bool useSystemTheme = true;
  String themeMode = 'Karanlık'; // 'Karanlık' | 'Aydınlık' | 'Sistem'
  String chatWallpaper = 'Varsayılan';
  double fontScale = 1.0;
  bool highContrast = false;

  // ---- Veri ----
  bool autoDownloadWifi = true;
  bool autoDownloadMobile = false;
  bool autoDownloadPhotos = true;
  bool autoDownloadVideos = false;
  bool autoDownloadDocs = true;

  // ---- Dil ----
  String language = 'Türkçe';

  // ---- Gelişmiş ----
  bool experimentalFeatures = false;
  bool verboseLogging = false;

  /// Birden çok kez çağrılabilir; yükleme yalnızca bir kez yapılır.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;

      showReadReceipts = p.getBool('${_p}showReadReceipts') ?? showReadReceipts;
      showTypingIndicator =
          p.getBool('${_p}showTypingIndicator') ?? showTypingIndicator;
      blockUnknownMessages =
          p.getBool('${_p}blockUnknownMessages') ?? blockUnknownMessages;

      notifSound = p.getBool('${_p}notifSound') ?? notifSound;
      notifVibrate = p.getBool('${_p}notifVibrate') ?? notifVibrate;
      notifPreview = p.getBool('${_p}notifPreview') ?? notifPreview;
      notifLed = p.getBool('${_p}notifLed') ?? notifLed;
      notifGroupSummary =
          p.getBool('${_p}notifGroupSummary') ?? notifGroupSummary;
      notifSoundTone = p.getString('${_p}notifSoundTone') ?? notifSoundTone;

      useSystemTheme = p.getBool('${_p}useSystemTheme') ?? useSystemTheme;
      themeMode = p.getString('${_p}themeMode') ?? themeMode;
      chatWallpaper = p.getString('${_p}chatWallpaper') ?? chatWallpaper;
      fontScale = (p.getDouble('${_p}fontScale') ?? fontScale).clamp(0.8, 1.5);
      highContrast = p.getBool('${_p}highContrast') ?? highContrast;

      autoDownloadWifi = p.getBool('${_p}autoDownloadWifi') ?? autoDownloadWifi;
      autoDownloadMobile =
          p.getBool('${_p}autoDownloadMobile') ?? autoDownloadMobile;
      autoDownloadPhotos =
          p.getBool('${_p}autoDownloadPhotos') ?? autoDownloadPhotos;
      autoDownloadVideos =
          p.getBool('${_p}autoDownloadVideos') ?? autoDownloadVideos;
      autoDownloadDocs = p.getBool('${_p}autoDownloadDocs') ?? autoDownloadDocs;

      language = p.getString('${_p}language') ?? language;

      experimentalFeatures =
          p.getBool('${_p}experimentalFeatures') ?? experimentalFeatures;
      verboseLogging = p.getBool('${_p}verboseLogging') ?? verboseLogging;

      notifyListeners();
    } catch (_) {
      // Okunamazsa varsayılan değerlerle devam et
    }
  }

  /// Bir ayarı değiştirir, kaydeder ve dinleyenleri uyarır.
  Future<void> update(VoidCallback change) async {
    change();
    notifyListeners();
    await _save();
  }

  /// Tüm ayarları varsayılana döndürür.
  Future<void> reset() async {
    showReadReceipts = true;
    showTypingIndicator = true;
    blockUnknownMessages = false;
    notifSound = true;
    notifVibrate = true;
    notifPreview = true;
    notifLed = true;
    notifGroupSummary = true;
    notifSoundTone = 'Varsayılan';
    useSystemTheme = true;
    themeMode = 'Karanlık';
    chatWallpaper = 'Varsayılan';
    fontScale = 1.0;
    highContrast = false;
    autoDownloadWifi = true;
    autoDownloadMobile = false;
    autoDownloadPhotos = true;
    autoDownloadVideos = false;
    autoDownloadDocs = true;
    language = 'Türkçe';
    experimentalFeatures = false;
    verboseLogging = false;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs = p;

      await p.setBool('${_p}showReadReceipts', showReadReceipts);
      await p.setBool('${_p}showTypingIndicator', showTypingIndicator);
      await p.setBool('${_p}blockUnknownMessages', blockUnknownMessages);

      await p.setBool('${_p}notifSound', notifSound);
      await p.setBool('${_p}notifVibrate', notifVibrate);
      await p.setBool('${_p}notifPreview', notifPreview);
      await p.setBool('${_p}notifLed', notifLed);
      await p.setBool('${_p}notifGroupSummary', notifGroupSummary);
      await p.setString('${_p}notifSoundTone', notifSoundTone);

      await p.setBool('${_p}useSystemTheme', useSystemTheme);
      await p.setString('${_p}themeMode', themeMode);
      await p.setString('${_p}chatWallpaper', chatWallpaper);
      await p.setDouble('${_p}fontScale', fontScale);
      await p.setBool('${_p}highContrast', highContrast);

      await p.setBool('${_p}autoDownloadWifi', autoDownloadWifi);
      await p.setBool('${_p}autoDownloadMobile', autoDownloadMobile);
      await p.setBool('${_p}autoDownloadPhotos', autoDownloadPhotos);
      await p.setBool('${_p}autoDownloadVideos', autoDownloadVideos);
      await p.setBool('${_p}autoDownloadDocs', autoDownloadDocs);

      await p.setString('${_p}language', language);

      await p.setBool('${_p}experimentalFeatures', experimentalFeatures);
      await p.setBool('${_p}verboseLogging', verboseLogging);
    } catch (_) {
      // Kayıt başarısızsa uygulama çökmesin; bir sonraki değişiklikte tekrar denenir
    }
  }
}
