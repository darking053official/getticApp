// ============================================================
// lib/services/cloud_notebook.dart
// (.txt olarak verildi. Projeye eklerken adını cloud_notebook.dart yapın.)
//
// Notebook: notebook_notes + notebook_verifier (web ile aynı).
//  - Tuz: "e-posta:notebook". Anahtar: PBKDF2 600.000.
//  - payload: AES-GCM "iv.ct" içinde JSON {t, b, f, tags, pin, c}.
//  - Webdeki tags ve c alanları korunur (düzenlemede kaybolmaz).
// ============================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/security.dart';
import '../pages/notebook_page.dart';
import 'web_crypto.dart';

class NotebookCloud extends CloudVault {
  NotebookCloud._();
  static final NotebookCloud instance = NotebookCloud._();

  static const String _magic = 'GETTIC_NOTEBOOK_OK';
  static const String _prefix = 'v1:';
  static const int _iter = 600000;

  Uint8List? _key;
  /// id -> çözülmüş payload (tags gibi bilinmeyen alanlar burada korunur)
  Map<String, Map<String, dynamic>> _raw = {};

  SupabaseClient get _sb => Supabase.instance.client;

  String _uid() {
    final u = _sb.auth.currentUser;
    if (u == null) throw const SecurityException('Oturum yok');
    return u.id;
  }

  String _salt() {
    final e = _sb.auth.currentUser?.email;
    if (e == null || e.isEmpty) throw const SecurityException('E-posta bulunamadı');
    return '$e:notebook';
  }

  Uint8List _requireKey() {
    final k = _key;
    if (k == null) throw const SecurityException('Defter kilitli');
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
    _raw = {};
    notifyListeners();
  }

  @override
  Future<bool> hasVerifier() async {
    final r = await _sb
        .from('notebook_verifier')
        .select('user_id')
        .eq('user_id', _uid())
        .maybeSingle();
    return r != null;
  }

  @override
  Future<void> setup(String password) async {
    if (password.length < 8) {
      throw const SecurityException('Yeni defter için en az 8 karakter gerekli');
    }
    final key = await WebCrypto.deriveKey(password, _salt(), _iter);
    final check = WebCrypto.makeVerifier(key, _magic, _prefix);
    await _sb
        .from('notebook_verifier')
        .insert({'user_id': _uid(), 'check_b64': check});
    _setKey(key);
  }

  @override
  Future<void> unlock(String password) async {
    if (password.length < 6) throw const SecurityException('En az 6 karakter gerekli');
    final row = await _sb
        .from('notebook_verifier')
        .select('check_b64')
        .eq('user_id', _uid())
        .maybeSingle();
    if (row == null) throw const SecurityException('Defter henüz oluşturulmamış');

    final key = await WebCrypto.deriveKey(password, _salt(), _iter);
    if (!WebCrypto.checkVerifier(row['check_b64'] as String, key, _magic)) {
      throw const SecurityException('Defter şifresi yanlış');
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
    final newKey = await WebCrypto.deriveKey(newPassword, _salt(), _iter);
    final uid = _uid();
    final now = DateTime.now().toUtc().toIso8601String();

    final rows = await _sb
        .from('notebook_notes')
        .select('id,payload')
        .eq('user_id', uid);

    for (final r in rows) {
      final plain = WebCrypto.decryptText(r['payload'] as String, oldKey);
      await _sb
          .from('notebook_notes')
          .update({
            'payload': WebCrypto.encryptText(plain, newKey),
            'updated_at': now,
          })
          .eq('id', r['id'])
          .eq('user_id', uid);
    }

    await _sb
        .from('notebook_verifier')
        .update({'check_b64': WebCrypto.makeVerifier(newKey, _magic, _prefix)})
        .eq('user_id', uid);

    _setKey(newKey);
  }

  // ----------------------------------------------------------
  // Notlar
  // ----------------------------------------------------------

  /// Notları sunucudan çeker ve çözer. Çözülemeyen kayıtlar atlanır.
  Future<List<NoteItem>> fetchAll() async {
    final key = _requireKey();
    final rows = await _sb
        .from('notebook_notes')
        .select('id,payload,updated_at')
        .eq('user_id', _uid())
        .order('updated_at', ascending: false);

    final out = <NoteItem>[];
    final raw = <String, Map<String, dynamic>>{};

    for (final r in rows) {
      try {
        final map = jsonDecode(WebCrypto.decryptText(r['payload'] as String, key))
            as Map<String, dynamic>;
        final id = r['id'].toString();
        raw[id] = map;
        final updated = DateTime.tryParse((r['updated_at'] ?? '').toString());
        out.add(NoteItem(
          id: id,
          title: (map['t'] ?? '').toString(),
          body: (map['b'] ?? '').toString(),
          folder: (map['f'] ?? '').toString(),
          pinned: map['pin'] == true,
          updatedAt: updated?.millisecondsSinceEpoch ?? 0,
        ));
      } catch (_) {
        // çözülemeyen not: listelenmez, silinmez, değiştirilmez
      }
    }

    _raw = raw;
    return out;
  }

  /// Sayfadaki listeyi sunucuya yazar. Silinmiş notlar sunucudan silinir.
  Future<void> saveAll(List<NoteItem> notes) async {
    final key = _requireKey();
    final uid = _uid();
    final now = DateTime.now().toUtc().toIso8601String();

    for (final n in notes) {
      final before = _raw[n.id];

      if (n.deleted) {
        if (before != null) {
          await _sb.from('notebook_notes').delete().eq('id', n.id).eq('user_id', uid);
          _raw.remove(n.id);
        }
        continue;
      }

      if (before == null) {
        final map = <String, dynamic>{
          't': n.title,
          'b': n.body,
          'f': n.folder,
          'tags': <String>[],
          'pin': n.pinned,
          'c': now,
        };
        await _sb.from('notebook_notes').upsert({
          'id': n.id,
          'user_id': uid,
          'payload': WebCrypto.encryptText(jsonEncode(map), key),
          'updated_at': now,
        }, onConflict: 'id');
        _raw[n.id] = map;
        continue;
      }

      final map = Map<String, dynamic>.from(before)
        ..['t'] = n.title
        ..['b'] = n.body
        ..['f'] = n.folder
        ..['pin'] = n.pinned;

      if (jsonEncode(map) == jsonEncode(before)) continue;

      await _sb
          .from('notebook_notes')
          .update({
            'payload': WebCrypto.encryptText(jsonEncode(map), key),
            'updated_at': now,
          })
          .eq('id', n.id)
          .eq('user_id', uid);
      _raw[n.id] = map;
    }
  }
}
