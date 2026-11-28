// ============================================================
// lib/services/chat_prefs_service.dart
// (.txt olarak verildi. Projeye eklerken adını chat_prefs_service.dart yapın.)
// Sohbet başına görünüm ayarları (baloncuk rengi, duvar kağıdı), sunucuda saklanır.
// Uygulama silinse ya da yeni cihaza geçilse de ayarlar kalır.
// Tablo: chat_prefs. Depo kovası: wallpapers (herkese açık okuma).
// ============================================================

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class ChatPrefsService {
  ChatPrefsService._();
  static final ChatPrefsService instance = ChatPrefsService._();

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  /// Kullanıcının bu sohbetteki ayarlarını getirir. Yoksa null.
  Future<Map<String, dynamic>?> load(String convId) async {
    final uid = _uid;
    if (uid == null) return null;
    return await _sb
        .from('chat_prefs')
        .select('bubble_color, wallpaper')
        .eq('user_id', uid)
        .eq('conversation_id', convId)
        .maybeSingle();
  }

  /// Verilen alanları kaydeder. Verilmeyen alanlar değişmez.
  Future<void> save(
    String convId, {
    int? bubbleColor,
    String? wallpaper,
    bool clearWallpaper = false,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final data = <String, dynamic>{
      'user_id': uid,
      'conversation_id': convId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (bubbleColor != null) data['bubble_color'] = bubbleColor;
    if (clearWallpaper) {
      data['wallpaper'] = null;
    } else if (wallpaper != null) {
      data['wallpaper'] = wallpaper;
    }
    await _sb
        .from('chat_prefs')
        .upsert(data, onConflict: 'user_id,conversation_id');
  }

  /// Duvar kağıdı görselini yükler, herkese açık adresini döndürür.
  Future<String> uploadWallpaper(File file, String convId) async {
    final uid = _uid;
    if (uid == null) throw Exception('Oturum açık değil');
    final path = '$uid/$convId.jpg';
    await _sb.storage.from('wallpapers').upload(
          path,
          file,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    final url = _sb.storage.from('wallpapers').getPublicUrl(path);
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }
}
