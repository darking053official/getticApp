// ============================================================
// lib/services/chat_outbox.dart
// Çevrimdışı mesaj kuyruğu: gönderilemeyen metinler cihazda saklanır,
// bağlantı gelince sırayla gönderilir.
// ============================================================

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

class ChatOutbox {
  ChatOutbox._();
  static final ChatOutbox instance = ChatOutbox._();

  static const String _key = 'chat_outbox_v1';
  bool _flushing = false;

  Future<List<Map<String, dynamic>>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(raw) as List);
  }

  Future<void> _save(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(items));
    }
  }

  /// Gönderilemeyen metni kuyruğa ekler.
  Future<void> add(String conversationId, String text, String? replyToId) async {
    final items = await _load();
    items.add({
      'conversationId': conversationId,
      'text': text,
      'replyTo': replyToId,
      'at': DateTime.now().toIso8601String(),
    });
    await _save(items);
  }

  Future<int> pendingCount(String conversationId) async {
    final items = await _load();
    return items.where((e) => e['conversationId'] == conversationId).length;
  }

  /// Kuyruktaki mesajları sırayla gönderir. Biri başarısız olursa durur.
  Future<void> flush(SupabaseService service, {String? conversationId}) async {
    if (_flushing) return;
    _flushing = true;
    try {
      var items = await _load();
      var i = 0;
      while (i < items.length) {
        final item = items[i];
        if (conversationId != null && item['conversationId'] != conversationId) {
          i++;
          continue;
        }
        try {
          await service.sendMessage(
            item['conversationId'] as String,
            item['text'] as String,
            replyToId: item['replyTo'] as String?,
          );
          items.removeAt(i);
          await _save(items);
        } catch (_) {
          break; // hâlâ çevrimdışı, sonra tekrar dene
        }
      }
    } finally {
      _flushing = false;
    }
  }
}
