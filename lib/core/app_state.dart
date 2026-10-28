import 'package:flutter/foundation.dart';

/// Uygulama genelinde kullanılan global state.
/// Özellikle bildirim (notification) mantığı için hangi sohbetin
/// açık olduğunu ve kullanıcının aktif olup olmadığını tutar.
class AppState {
  AppState._internal();
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;

  // ==========================================
  // AKTİF SOHBET
  // ==========================================
  
  /// Kullanıcının şu an açık olduğu sohbetin ID'si.
  /// Null ise kullanıcı sohbet listesinde veya başka bir sayfadadır.
  String? _activeConversationId;
  
  String? get activeConversationId => _activeConversationId;

  /// Kullanıcı bir sohbete girdiğinde çağır.
  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
    debugPrint('Aktif sohbet değişti: $conversationId');
  }

  /// Kullanıcı sohbetten çıktığında çağır.
  void clearActiveConversation() {
    _activeConversationId = null;
  }

  /// Bir mesajın bildirim olarak gösterilip gösterilmeyeceğini kontrol et.
  /// Eğer mesaj zaten açık olan sohbete aitse, bildirim gösterme.
  bool shouldShowNotification(String conversationId) {
    return _activeConversationId != conversationId;
  }

  // ==========================================
  // UYGULAMA DURUMU
  // ==========================================
  
  /// Uygulama ön planda mı?
  bool _isAppInForeground = true;
  
  bool get isAppInForeground => _isAppInForeground;

  void setAppInForeground(bool value) {
    _isAppInForeground = value;
  }

  // ==========================================
  // BİLDİRİM SAYACI
  // ==========================================
  
  /// Toplam okunmamış mesaj sayısı (OneSignal badge için kullanılabilir)
  int _totalUnreadCount = 0;
  
  int get totalUnreadCount => _totalUnreadCount;

  void setTotalUnreadCount(int count) {
    _totalUnreadCount = count;
  }

  void incrementUnread() {
    _totalUnreadCount++;
  }

  void resetUnread() {
    _totalUnreadCount = 0;
  }

  // ==========================================
  // KULLANICI DURUMU
  // ==========================================
  
  /// Aktif kullanıcının ID'si (Supabase ile senkron)
  String? _currentUserId;
  
  String? get currentUserId => _currentUserId;

  void setCurrentUserId(String? userId) {
    _currentUserId = userId;
  }

  // ==========================================
  // SIFIRLAMA
  // ==========================================
  
  /// Çıkış yapıldığında tüm state'i sıfırla.
  void reset() {
    _activeConversationId = null;
    _isAppInForeground = true;
    _totalUnreadCount = 0;
    _currentUserId = null;
    debugPrint('AppState sıfırlandı');
  }
}
