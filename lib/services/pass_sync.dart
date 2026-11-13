// ============================================================
// lib/services/pass_sync.dart
//
// GetticPass uçtan uca şifreli senkron.
//  - Kayıtlar cihazda AES-256-GCM ile şifrelenir, sunucuya yalnızca
//    şifreli blob gider. Anahtar kasa parolasından PBKDF2 ile türetilir.
//  - Aynı formatı Firefox eklentisi (extension/sync-core.js) kullanır.
//  - Çakışmalar: her kayıtta updatedAt; büyük olan kazanır.
//    Silmeler "tombstone" ile yayılır.
//  - Sürüm kontrolü (optimistic): iki cihaz aynı anda yazarsa biri
//    tekrar çeker ve birleştirir, veri kaybolmaz.
//
// Gerekenler: lib/pages/pass_vault_page.dart (PassEntry, PassRepository),
//             lib/core/security.dart, lib/core/theme.dart
// Sunucu: supabase_pass_sync.sql
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/security.dart';
import '../core/theme.dart';
import '../pages/pass_vault_page.dart';

class PassSync {
  PassSync._();
  static final PassSync instance = PassSync._();

  static const String _table = 'pass_vault';
  static const String _keySlot = 'pass_sync_key_v1';
  static const String _saltSlot = 'pass_sync_salt_v1';
  static const String _ctxPrefix = 'gettic-pass-sync:';
  static const int _tombstoneTtlMs = 90 * 24 * 60 * 60 * 1000;
  static const int _maxAttempts = 3;

  Timer? _debounce;
  bool _running = false;

  /// Son senkron hatası (arayüzde göstermek için).
  String? lastError;

  SupabaseClient get _sb => Supabase.instance.client;

  String _requireUid() {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      throw const SecurityException('Senkron için giriş yapmalısınız');
    }
    return uid;
  }

  String _context(String uid) => '$_ctxPrefix$uid';

  Future<bool> isEnabled() async =>
      (await EncryptedPrefs.read(_keySlot)) != null;

  // ----------------------------------------------------------
  // Anahtar saklama (EncryptedPrefs: yalnızca kasa açıkken okunur/yazılır)
  // ----------------------------------------------------------
  Future<void> _storeKeyMaterial(Uint8List key, Uint8List salt) async {
    await EncryptedPrefs.write(_keySlot, base64.encode(key));
    await EncryptedPrefs.write(_saltSlot, base64.encode(salt));
  }

  Future<(Uint8List, Uint8List)?> _loadKeyMaterial() async {
    final k = await EncryptedPrefs.read(_keySlot);
    final s = await EncryptedPrefs.read(_saltSlot);
    if (k == null || s == null) return null;
    return (base64.decode(k), base64.decode(s));
  }

  // ----------------------------------------------------------
  // Açma / kapama
  // ----------------------------------------------------------

  /// Senkronu açar. Sunucuda kayıt varsa kasa parolası doğrulanır,
  /// yerel ve uzak kayıtlar birleştirilir.
  /// Yanlış parolada [SecurityException] fırlatır.
  Future<void> enable(String vaultPassword) async {
    final uid = _requireUid();
    final row = await _fetchRow(uid);

    final Uint8List salt = row != null
        ? base64.decode(row['salt'] as String)
        : Crypto.randomBytes(16);
    final key = await Crypto.deriveKey(
        vaultPassword, salt, Crypto.defaultIterations);

    if (row != null) {
      // Parola doğrulaması: yanlışsa çözme başarısız olur
      await _decryptRecords(row['blob'] as String, key, uid);
    }

    await _storeKeyMaterial(key, salt);
    await _safeSync();
  }

  /// Senkronu kapatır. [deleteRemote] true ise sunucudaki kopya da silinir.
  Future<void> disable({bool deleteRemote = false}) async {
    _debounce?.cancel();
    if (deleteRemote) {
      final uid = _sb.auth.currentUser?.id;
      if (uid != null) {
        await _sb.from(_table).delete().eq('user_id', uid);
      }
    }
    await EncryptedPrefs.delete(_keySlot);
    await EncryptedPrefs.delete(_saltSlot);
  }

  /// Kasa parolası değiştiğinde çağrılmalıdır (SecureVault.changeSecret sonrası).
  /// Yeni tuz ve anahtarla sunucudaki kopyayı yeniden şifreler.
  /// Diğer cihazlar yeni parolayla senkronu yeniden etkinleştirmelidir.
  Future<void> rekey(String newVaultPassword) async {
    final uid = _requireUid();
    final salt = Crypto.randomBytes(16);
    final key = await Crypto.deriveKey(
        newVaultPassword, salt, Crypto.defaultIterations);
    final records = await PassRepository.load();
    final blob = _encryptRecords(records, key, uid);
    final now = DateTime.now().toUtc().toIso8601String();

    final row = await _fetchRow(uid);
    if (row == null) {
      await _sb.from(_table).insert({
        'user_id': uid,
        'salt': base64.encode(salt),
        'blob': blob,
        'version': 1,
        'kdf_iterations': Crypto.defaultIterations,
      });
    } else {
      final version = row['version'] as int;
      final updated = await _sb
          .from(_table)
          .update({
            'salt': base64.encode(salt),
            'blob': blob,
            'version': version + 1,
            'updated_at': now,
          })
          .eq('user_id', uid)
          .eq('version', version)
          .select();
      if (updated.isEmpty) {
        throw const SecurityException('Senkron çakışması, tekrar deneyin');
      }
    }
    await _storeKeyMaterial(key, salt);
  }

  // ----------------------------------------------------------
  // Senkron
  // ----------------------------------------------------------

  /// Zamanlanmış senkron (art arda değişikliklerde tek seferde çalışır).
  void scheduleSync({Duration delay = const Duration(seconds: 2)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, () => _safeSync());
  }

  /// Hataları yutar, [lastError] üzerinden bildirir.
  Future<void> _safeSync() async {
    try {
      await sync();
      lastError = null;
    } on SecurityException catch (e) {
      lastError = e.message;
    } catch (_) {
      lastError = 'Senkron yapılamadı. İnternet bağlantınızı kontrol edin.';
    }
  }

  /// Yerel kayıtları sunucuyla birleştirir. Hata fırlatabilir.
  Future<void> sync() async {
    if (_running) return;
    _running = true;
    try {
      final uid = _requireUid();
      final material = await _loadKeyMaterial();
      if (material == null) return; // senkron kapalı
      final (key, salt) = material;

      final local = await PassRepository.load();

      for (var attempt = 0; attempt < _maxAttempts; attempt++) {
        final row = await _fetchRow(uid);

        // 1) Sunucuda kayıt yok: ilk yükleme
        if (row == null) {
          final blob = _encryptRecords(local, key, uid);
          try {
            await _sb.from(_table).insert({
              'user_id': uid,
              'salt': base64.encode(salt),
              'blob': blob,
              'version': 1,
              'kdf_iterations': Crypto.defaultIterations,
            });
            await PassRepository.save(local);
            return;
          } on PostgrestException catch (e) {
            if (e.code == '23505') continue; // aynı anda başka cihaz oluşturdu
            rethrow;
          }
        }

        // 2) Uzak kopyayı çöz (parola değiştiyse burada hata verir)
        final List<PassEntry> remote;
        try {
          remote = await _decryptRecords(row['blob'] as String, key, uid);
        } on SecurityException {
          throw const SecurityException(
              'Kasa parolası bu cihazda farklı. Senkronu yeniden etkinleştirin.');
        }

        // 3) Birleştir
        final merged = mergeRecords(local, remote);

        // 4) Uzak kopya zaten güncelse yazmaya gerek yok
        if (_fingerprint(merged) == _fingerprint(remote)) {
          await PassRepository.save(merged);
          return;
        }

        // 5) Sürüm kontrolüyle yaz
        final blob = _encryptRecords(merged, key, uid);
        final version = row['version'] as int;
        final updated = await _sb
            .from(_table)
            .update({
              'blob': blob,
              'version': version + 1,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('user_id', uid)
            .eq('version', version)
            .select();

        if (updated.isNotEmpty) {
          await PassRepository.save(merged);
          return;
        }
        // Sürüm değişmiş (başka cihaz yazmış): döngü başına dön, tekrar çek
      }

      throw const SecurityException('Senkron çakışması, tekrar deneyin');
    } finally {
      _running = false;
    }
  }

  // ----------------------------------------------------------
  // Birleştirme (saf fonksiyon, eklentideki mergeRecords ile aynı mantık)
  // ----------------------------------------------------------

  /// Aynı id için updatedAt'i büyük olan kazanır.
  /// Eski silinmiş kayıtlar (tombstone) temizlenir.
  static List<PassEntry> mergeRecords(
    List<PassEntry> a,
    List<PassEntry> b, {
    int? nowMs,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - _tombstoneTtlMs;

    final map = <String, PassEntry>{};
    for (final r in [...a, ...b]) {
      final cur = map[r.id];
      if (cur == null || r.updatedAt > cur.updatedAt) {
        map[r.id] = r;
      }
    }
    return map.values
        .where((r) => !(r.deleted && r.updatedAt < cutoff))
        .toList();
  }

  static String _fingerprint(List<PassEntry> list) {
    final sorted = [...list]..sort((x, y) => x.id.compareTo(y.id));
    return jsonEncode(sorted.map((e) => e.toJson()).toList());
  }

  // ----------------------------------------------------------
  // Şifreleme ve sunucu yardımcıları
  // ----------------------------------------------------------

  Future<Map<String, dynamic>?> _fetchRow(String uid) {
    return _sb
        .from(_table)
        .select('salt, blob, version')
        .eq('user_id', uid)
        .maybeSingle();
  }

  String _encryptRecords(List<PassEntry> records, Uint8List key, String uid) {
    final plain = utf8.encode(jsonEncode({
      'v': 1,
      'records': records.map((e) => e.toJson()).toList(),
    }));
    final enc = Crypto.encrypt(
      Uint8List.fromList(plain),
      key,
      aad: utf8.encode(_context(uid)),
    );
    return base64.encode(enc);
  }

  Future<List<PassEntry>> _decryptRecords(
      String b64, Uint8List key, String uid) async {
    final Uint8List raw;
    try {
      raw = base64.decode(b64);
    } on FormatException {
      throw const SecurityException('Sunucu verisi bozuk');
    }
    final plain = Crypto.decrypt(raw, key, aad: utf8.encode(_context(uid)));
    final map = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    final list = map['records'] as List<dynamic>;
    return list
        .map((e) => PassEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

// ============================================================
// SENKRON KURULUM DİYALOĞU
// ============================================================
Future<void> showPassSyncSetup(BuildContext context) async {
  final c = context.appColors;
  final ctrl = TextEditingController();
  String? error;
  var busy = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Senkronu aç', style: TextStyle(color: c.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kasa parolanı gir. Kayıtların şifreli olarak sunucuda saklanır. '
              'Sunucu parolanı ve kayıtlarını çözemez.',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: 'Kasa parolası'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!,
                    style: TextStyle(color: c.danger, fontSize: 12)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    setSt(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await PassSync.instance.enable(ctrl.text);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } on SecurityException catch (e) {
                      setSt(() {
                        busy = false;
                        error = e.message;
                      });
                    } catch (_) {
                      setSt(() {
                        busy = false;
                        error = 'Bağlantı kurulamadı';
                      });
                    }
                  },
            child: Text(busy ? 'Bekleniyor...' : 'Aç',
                style: TextStyle(color: c.primary)),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
}
