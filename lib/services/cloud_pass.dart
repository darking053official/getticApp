// ============================================================
// lib/services/cloud_pass.dart
// (.txt olarak verildi. Projeye eklerken adını cloud_pass.dart yapın.)
//
// Parola kasası: pass_items + pass_verifier tabloları (web ve eklenti ile aynı).
//  - Tuz: e-posta adresi. Anahtar: PBKDF2 600.000 (eski kasalar 200.000).
//  - password_encrypted ve totp_secret: AES-GCM "iv.ct".
//  - Kayıtlar sunucuda tek kaynak. Anahtar yalnızca bellekte, kilitlenince silinir.
// ============================================================

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/security.dart';
import '../pages/pass_vault_page.dart';
import 'web_crypto.dart';

class PassCloud extends CloudVault {
  PassCloud._();
  static final PassCloud instance = PassCloud._();

  static const String _magic = 'GETTIC_PASS_OK';
  static const String _prefix = 'v2:';
  static const int _iter = 600000;
  static const int _legacyIter = 200000;

  Uint8List? _key;
  /// Son okunan / yazılan kayıtların hali (değişiklik tespiti için)
  Map<String, PassEntry> _snap = {};

  SupabaseClient get _sb => Supabase.instance.client;

  String _uid() {
    final u = _sb.auth.currentUser;
    if (u == null) throw const SecurityException('Oturum yok');
    return u.id;
  }

  String _email() {
    final e = _sb.auth.currentUser?.email;
    if (e == null || e.isEmpty) throw const SecurityException('E-posta bulunamadı');
    return e;
  }

  Uint8List _requireKey() {
    final k = _key;
    if (k == null) throw const SecurityException('Parola kasası kilitli');
    return k;
  }

  void _setKey(Uint8List k) {
    _key = k;
    notifyListeners();
  }

  @override
  bool get isUnlocked => _key != null;

  @override
  void lock() {
    final k = _key;
    if (k != null) k.fillRange(0, k.length, 0);
    _key = null;
    _snap = {};
    notifyListeners();
  }

  @override
  Future<bool> hasVerifier() async {
    final r = await _sb
        .from('pass_verifier')
        .select('user_id')
        .eq('user_id', _uid())
        .maybeSingle();
    return r != null;
  }

  @override
  Future<void> setup(String password) async {
    if (password.length < 8) {
      throw const SecurityException('Yeni kasa için en az 8 karakter gerekli');
    }
    final key = await WebCrypto.deriveKey(password, _email(), _iter);
    final check = WebCrypto.makeVerifier(key, _magic, _prefix);
    await _sb.from('pass_verifier').insert({'user_id': _uid(), 'check_b64': check});
    _setKey(key);
  }

  @override
  Future<void> unlock(String password) async {
    if (password.length < 6) throw const SecurityException('En az 6 karakter gerekli');
    final row = await _sb
        .from('pass_verifier')
        .select('check_b64')
        .eq('user_id', _uid())
        .maybeSingle();
    if (row == null) throw const SecurityException('Kasa henüz oluşturulmamış');

    final stored = row['check_b64'] as String;
    final iter = stored.startsWith('v2:') ? _iter : _legacyIter;
    final key = await WebCrypto.deriveKey(password, _email(), iter);
    if (!WebCrypto.checkVerifier(stored, key, _magic)) {
      throw const SecurityException('Kasa şifresi yanlış');
    }
    _setKey(key);
  }

  @override
  Future<void> changePassword(String oldPassword, String newPassword) async {
    if (newPassword.length < 8) {
      throw const SecurityException('Yeni şifre en az 8 karakter olmalı');
    }
    await unlock(oldPassword);
    final oldKey = _requireKey();
    final newKey = await WebCrypto.deriveKey(newPassword, _email(), _iter);
    final uid = _uid();
    final now = DateTime.now().toUtc().toIso8601String();

    final rows = await _sb
        .from('pass_items')
        .select('id,password_encrypted,totp_secret')
        .eq('user_id', uid);

    for (final r in rows) {
      final pw = WebCrypto.decryptText(r['password_encrypted'] as String, oldKey);
      final changes = <String, dynamic>{
        'password_encrypted': WebCrypto.encryptText(pw, newKey),
        'updated_at': now,
      };
      final totp = r['totp_secret'] as String?;
      if (totp != null && totp.isNotEmpty) {
        changes['totp_secret'] =
            WebCrypto.encryptText(WebCrypto.decryptText(totp, oldKey), newKey);
      }
      await _sb
          .from('pass_items')
          .update(changes)
          .eq('id', r['id'])
          .eq('user_id', uid);
    }

    await _sb
        .from('pass_verifier')
        .update({'check_b64': WebCrypto.makeVerifier(newKey, _magic, _prefix)})
        .eq('user_id', uid);

    _setKey(newKey);
  }

  // ----------------------------------------------------------
  // Kayıtlar
  // ----------------------------------------------------------

  PassEntry _fromRow(Map<String, dynamic> r, Uint8List key) {
    String dec(String? v) {
      if (v == null || v.isEmpty) return '';
      try {
        return WebCrypto.decryptText(v, key);
      } catch (_) {
        return '';
      }
    }

    final updated = DateTime.tryParse(
        (r['updated_at'] ?? r['created_at'] ?? '').toString());

    return PassEntry(
      id: r['id'].toString(),
      title: (r['site_name'] ?? '').toString(),
      username: (r['username'] ?? '').toString(),
      password: dec(r['password_encrypted'] as String?),
      url: (r['site_url'] ?? '').toString(),
      notes: (r['notes'] ?? '').toString(),
      totpSecret: dec(r['totp_secret'] as String?),
      favorite: r['favorite'] == true,
      updatedAt: updated?.millisecondsSinceEpoch ?? 0,
    );
  }

  /// Tüm kayıtları sunucudan çeker ve çözer.
  Future<List<PassEntry>> fetchAll() async {
    final key = _requireKey();
    final rows = await _sb
        .from('pass_items')
        .select('id,site_name,site_url,username,password_encrypted,notes,'
            'favorite,totp_secret,created_at,updated_at')
        .eq('user_id', _uid())
        .order('created_at', ascending: false);

    final list = [
      for (final r in rows) _fromRow(Map<String, dynamic>.from(r), key),
    ];
    _snap = {for (final e in list) e.id: e};
    return list;
  }

  /// Sayfadaki listeyi sunucuya yazar: yeni kayıt ekler, değişeni günceller,
  /// silinmiş (deleted) kaydı siler. Yalnızca değişen alanlar gönderilir.
  Future<void> saveAll(List<PassEntry> items) async {
    final key = _requireKey();
    final uid = _uid();
    final now = DateTime.now().toUtc().toIso8601String();

    for (final e in items) {
      final before = _snap[e.id];

      if (e.deleted) {
        if (before != null) {
          await _sb.from('pass_items').delete().eq('id', e.id).eq('user_id', uid);
          _snap.remove(e.id);
        }
        continue;
      }

      final title = e.title.trim().isEmpty ? 'Başlıksız' : e.title.trim();

      if (before == null) {
        await _sb.from('pass_items').upsert({
          'id': e.id,
          'user_id': uid,
          'site_name': title,
          'site_url': e.url.trim().isEmpty ? null : e.url.trim(),
          'username': e.username,
          'password_encrypted': WebCrypto.encryptText(e.password, key),
          'notes': e.notes,
          'category': 'other',
          'favorite': e.favorite,
          'password_strength': webPasswordStrength(e.password),
          'totp_secret': e.totpSecret.isEmpty
              ? null
              : WebCrypto.encryptText(e.totpSecret, key),
          'created_at': now,
          'updated_at': now,
        }, onConflict: 'id');
        _snap[e.id] = e;
        continue;
      }

      final changes = <String, dynamic>{};
      if (e.title != before.title) changes['site_name'] = title;
      if (e.url != before.url) {
        changes['site_url'] = e.url.trim().isEmpty ? null : e.url.trim();
      }
      if (e.username != before.username) changes['username'] = e.username;
      if (e.notes != before.notes) changes['notes'] = e.notes;
      if (e.favorite != before.favorite) changes['favorite'] = e.favorite;
      if (e.password != before.password) {
        changes['password_encrypted'] = WebCrypto.encryptText(e.password, key);
        changes['password_strength'] = webPasswordStrength(e.password);
      }
      if (e.totpSecret != before.totpSecret) {
        changes['totp_secret'] = e.totpSecret.isEmpty
            ? null
            : WebCrypto.encryptText(e.totpSecret, key);
      }

      if (changes.isEmpty) continue;
      changes['updated_at'] = now;
      await _sb
          .from('pass_items')
          .update(changes)
          .eq('id', e.id)
          .eq('user_id', uid);
      _snap[e.id] = e;
    }
  }
}
