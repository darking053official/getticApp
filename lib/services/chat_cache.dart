// ============================================================
// lib/services/chat_cache.dart
// (.txt olarak verildi. Projeye eklerken adını chat_cache.dart yapın.)
// Yerel önbellek: mesajlar ve sohbet listesi açılışta hemen gösterilsin diye saklanır.
// Önbellek, cihazın güvenli deposundaki rastgele bir anahtarla şifrelenir (düz metin saklanmaz).
// ============================================================

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';

class LocalCache {
  LocalCache._();

  static const String _keyName = 'local_cache_key_v1';
  static final FlutterSecureStorage _store = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final Xchacha20 _aead = Xchacha20.poly1305Aead();
  static SecretKey? _key;

  static Future<SecretKey> _getKey() async {
    final cached = _key;
    if (cached != null) return cached;
    final existing = await _store.read(key: _keyName);
    if (existing != null) {
      _key = SecretKey(base64Decode(existing));
    } else {
      final fresh = await _aead.newSecretKey();
      await _store.write(key: _keyName, value: base64Encode(await fresh.extractBytes()));
      _key = fresh;
    }
    return _key!;
  }

  static Future<String> _seal(String plain) async {
    final box = await _aead.encrypt(
      utf8.encode(plain),
      secretKey: await _getKey(),
      nonce: _aead.newNonce(),
    );
    return base64Encode(box.concatenation());
  }

  static Future<String?> _open(String sealed) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(sealed),
        nonceLength: 24,
        macLength: 16,
      );
      final clear = await _aead.decrypt(box, secretKey: await _getKey());
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String key, String plain) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, await _seal(plain));
  }

  static Future<String?> _read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    return _open(raw);
  }

  // ---------- Mesaj önbelleği ----------

  static const int _maxMessages = 80;

  static Future<List<Message>> loadMessages(String convId) async {
    try {
      final raw = await _read('msgcache_v1_$convId');
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => Message.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMessages(String convId, List<Message> msgs) async {
    try {
      final tail = msgs.length > _maxMessages
          ? msgs.sublist(msgs.length - _maxMessages)
          : msgs;
      await _write(
        'msgcache_v1_$convId',
        jsonEncode(tail.map((m) => m.toCacheJson()).toList()),
      );
    } catch (_) {}
  }

  // ---------- Sohbet listesi önbelleği ----------

  static Future<List<Map<String, dynamic>>> loadChatList(String uid) async {
    try {
      final raw = await _read('chatlist_v1_$uid');
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveChatList(String uid, List<Map<String, dynamic>> list) async {
    try {
      await _write('chatlist_v1_$uid', jsonEncode(list));
    } catch (_) {}
  }
}
