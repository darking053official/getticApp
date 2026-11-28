// ============================================================
// lib/core/app_settings.dart
// (.txt olarak verildi. Projeye eklerken adını app_settings.dart yapın.)
//
// Cihazda saklanan uygulama ayarları. Her alan gerçekten kullanılıyor:
//  - Görünüm: main.dart (tema, yazı boyutu)
//  - Gizlilik: chat_room_page (okundu bilgisi, yazıyor göstergesi)
//  - Bildirim: main.dart (ön plan bildirimleri)
//  - Medya: chat_room_page (otomatik yükleme) -> autoLoad(type)
//  - Güvenlik: main.dart (otomatik kilit süresi)
// ============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const String _p = 'settings_';

  SharedPreferences? _prefs;
  Future<void>? _loading;

  // ---- Görünüm ----
  bool useSystemTheme = true;
  String themeMode = 'Karanlık'; // 'Karanlık' | 'Aydınlık'
  double fontScale = 1.0; // 0.8 - 1.5
  String accentKey = 'violet'; // violet | blue | teal | pink | orange | green
  String fontKey = 'default'; // default | inter | poppins | nunito | lora | montserrat

  // ---- Gizlilik ----
  bool showReadReceipts = true; // kapalıysa mesajlar okundu işaretlenmez
  bool showTypingIndicator = true;

  // ---- Bildirim ----
  bool inAppNotifications = true; // kapalıysa uygulama açıkken bildirim gösterilmez
  bool notifCallSound = true;
  bool notifCallVibrate = true;
  bool notifMessageSound = true;
  bool notifMessageVibrate = true;
  bool notifMessagePreview = true;
  bool detailedLog = false; // Ayrıntılı log: açıkken görüşme/bildirim logu kaydedilir ve gösterilir

  // ---- Medya otomatik yükleme ----
  bool autoLoadPhotos = true;
  bool autoLoadVideos = false;
  bool autoLoadAudio = true;
  bool autoLoadFiles = false;

  // ---- Güvenlik ----
  int autoLockMinutes = 2; // 0 = kapalı

  bool get isLoaded => _prefs != null;

  /// Birden çok kez çağrılabilir; yükleme yalnızca bir kez yapılır.
  Future<void> ensureLoaded() => _loading ??= _load();

  /// Bu medya türü otomatik yüklensin mi?
  bool autoLoad(String type) {
    switch (type) {
      case 'image':
      case 'gif':
        return autoLoadPhotos;
      case 'video':
        return autoLoadVideos;
      case 'audio':
        return autoLoadAudio;
      case 'file':
        return autoLoadFiles;
      default:
        return true;
    }
  }

  /// Bir ayarı değiştirir, kaydeder ve dinleyenleri uyarır.
  Future<void> update(VoidCallback change) async {
    change();
    notifyListeners();
    await _save();
    unawaited(pushToServer());
  }

  /// Ayarları hesaba bağlı olarak sunucuda saklar (uygulama silinse de kalır).
  Future<void> pushToServer() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      await Supabase.instance.client
          .from('profiles')
          .update({'app_prefs': toJson()}).eq('id', uid);
    } catch (_) {}
  }

  /// Oturum açılınca sunucudaki ayarları yerel ayarlara uygular.
  Future<void> pullFromServer() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await Supabase.instance.client
          .from('profiles')
          .select('app_prefs')
          .eq('id', uid)
          .maybeSingle();
      final j = row?['app_prefs'];
      if (j is Map && j.isNotEmpty) {
        await importJson(Map<String, dynamic>.from(j));
        notifyListeners();
      } else {
        await pushToServer();
      }
    } catch (_) {}
  }

  /// Tüm ayarları varsayılana döndürür.
  Future<void> reset() async {
    useSystemTheme = true;
    themeMode = 'Karanlık';
    fontScale = 1.0;
    showReadReceipts = true;
    showTypingIndicator = true;
    inAppNotifications = true;
    notifCallSound = true;
    notifCallVibrate = true;
    notifMessageSound = true;
    notifMessageVibrate = true;
    notifMessagePreview = true;
    detailedLog = false;
    autoLoadPhotos = true;
    autoLoadVideos = false;
    autoLoadAudio = true;
    autoLoadFiles = false;
    autoLockMinutes = 2;
    notifyListeners();
    await _save();
  }

  /// Dışa aktarma için ayarların JSON karşılığı (şifre içermez).
  Map<String, dynamic> toJson() => {
        'useSystemTheme': useSystemTheme,
        'themeMode': themeMode,
        'accentKey': accentKey,
        'fontKey': fontKey,
        'fontScale': fontScale,
        'showReadReceipts': showReadReceipts,
        'showTypingIndicator': showTypingIndicator,
        'inAppNotifications': inAppNotifications,
        'notifCallSound': notifCallSound,
        'notifCallVibrate': notifCallVibrate,
        'notifMessageSound': notifMessageSound,
        'notifMessageVibrate': notifMessageVibrate,
        'notifMessagePreview': notifMessagePreview,
        'detailedLog': detailedLog,
        'autoLoadPhotos': autoLoadPhotos,
        'autoLoadVideos': autoLoadVideos,
        'autoLoadAudio': autoLoadAudio,
        'autoLoadFiles': autoLoadFiles,
        'autoLockMinutes': autoLockMinutes,
      };

  /// İçe aktarma: geçerli alanları uygular, bilinmeyenleri yok sayar.
  Future<void> importJson(Map<String, dynamic> j) async {
    bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    String s(String k, String d) => j[k] is String ? j[k] as String : d;

    final theme = s('themeMode', themeMode);
    accentKey = s('accentKey', accentKey);
    fontKey = s('fontKey', fontKey);
    final scale = j['fontScale'] is num ? (j['fontScale'] as num).toDouble() : fontScale;
    final lock = j['autoLockMinutes'] is num ? (j['autoLockMinutes'] as num).toInt() : autoLockMinutes;

    useSystemTheme = b('useSystemTheme', useSystemTheme);
    themeMode = (theme == 'Karanlık' || theme == 'Aydınlık') ? theme : themeMode;
    fontScale = scale.clamp(0.8, 1.5).toDouble();
    showReadReceipts = b('showReadReceipts', showReadReceipts);
    showTypingIndicator = b('showTypingIndicator', showTypingIndicator);
    inAppNotifications = b('inAppNotifications', inAppNotifications);
    notifCallSound = b('notifCallSound', notifCallSound);
    notifCallVibrate = b('notifCallVibrate', notifCallVibrate);
    notifMessageSound = b('notifMessageSound', notifMessageSound);
    notifMessageVibrate = b('notifMessageVibrate', notifMessageVibrate);
    notifMessagePreview = b('notifMessagePreview', notifMessagePreview);
    detailedLog = b('detailedLog', detailedLog);
    autoLoadPhotos = b('autoLoadPhotos', autoLoadPhotos);
    autoLoadVideos = b('autoLoadVideos', autoLoadVideos);
    autoLoadAudio = b('autoLoadAudio', autoLoadAudio);
    autoLoadFiles = b('autoLoadFiles', autoLoadFiles);
    autoLockMinutes = const [0, 1, 2, 5, 15].contains(lock) ? lock : autoLockMinutes;

    notifyListeners();
    await _save();
  }

  // ----------------------------------------------------------
  // Depolama
  // ----------------------------------------------------------
  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;

      bool b(String k, bool d) => p.getBool('$_p$k') ?? d;
      String s(String k, String d) => p.getString('$_p$k') ?? d;

      useSystemTheme = b('useSystemTheme', useSystemTheme);
      themeMode = s('themeMode', themeMode);
      accentKey = s('accentKey', accentKey);
      fontKey = s('fontKey', fontKey);
      fontScale = (p.getDouble('${_p}fontScale') ?? fontScale).clamp(0.8, 1.5).toDouble();
      showReadReceipts = b('showReadReceipts', showReadReceipts);
      showTypingIndicator = b('showTypingIndicator', showTypingIndicator);
      inAppNotifications = b('inAppNotifications', inAppNotifications);
      notifCallSound = b('notifCallSound', notifCallSound);
      notifCallVibrate = b('notifCallVibrate', notifCallVibrate);
      notifMessageSound = b('notifMessageSound', notifMessageSound);
      notifMessageVibrate = b('notifMessageVibrate', notifMessageVibrate);
      notifMessagePreview = b('notifMessagePreview', notifMessagePreview);
      detailedLog = b('detailedLog', detailedLog);
      autoLoadPhotos = b('autoLoadPhotos', autoLoadPhotos);
      autoLoadVideos = b('autoLoadVideos', autoLoadVideos);
      autoLoadAudio = b('autoLoadAudio', autoLoadAudio);
      autoLoadFiles = b('autoLoadFiles', autoLoadFiles);
      autoLockMinutes = p.getInt('${_p}autoLockMinutes') ?? autoLockMinutes;

      notifyListeners();
    } catch (_) {
      // Okunamazsa varsayılanlarla devam et
    }
  }

  Future<void> _save() async {
    try {
      final p = _prefs ?? await SharedPreferences.getInstance();
      _prefs = p;

      await p.setBool('${_p}useSystemTheme', useSystemTheme);
      await p.setString('${_p}themeMode', themeMode);
      await p.setString('${_p}accentKey', accentKey);
      await p.setString('${_p}fontKey', fontKey);
      await p.setDouble('${_p}fontScale', fontScale);
      await p.setBool('${_p}showReadReceipts', showReadReceipts);
      await p.setBool('${_p}showTypingIndicator', showTypingIndicator);
      await p.setBool('${_p}inAppNotifications', inAppNotifications);
      await p.setBool('${_p}notifCallSound', notifCallSound);
      await p.setBool('${_p}notifCallVibrate', notifCallVibrate);
      await p.setBool('${_p}notifMessageSound', notifMessageSound);
      await p.setBool('${_p}notifMessageVibrate', notifMessageVibrate);
      await p.setBool('${_p}notifMessagePreview', notifMessagePreview);
      await p.setBool('${_p}detailedLog', detailedLog);
      await p.setBool('${_p}autoLoadPhotos', autoLoadPhotos);
      await p.setBool('${_p}autoLoadVideos', autoLoadVideos);
      await p.setBool('${_p}autoLoadAudio', autoLoadAudio);
      await p.setBool('${_p}autoLoadFiles', autoLoadFiles);
      await p.setInt('${_p}autoLockMinutes', autoLockMinutes);
    } catch (_) {
      // Yazılamazsa bir sonraki değişiklikte tekrar denenir
    }
  }
}
