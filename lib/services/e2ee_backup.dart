// ============================================================
// lib/services/e2ee_backup.dart
// (.txt olarak verildi. Projeye eklerken adını e2ee_backup.dart yapın.)
//
// Aşama 6: sohbet anahtarı yedeği (parolayla).
//  - Kullanıcı yedek parolası belirler (en az 8 karakter). Hesap parolası değildir.
//  - Paroladan PBKDF2-HMAC-SHA256 ile 256 bit anahtar türetilir.
//  - Cihazdaki tüm sohbet anahtarları bu anahtarla XChaCha20-Poly1305 ile şifrelenip
//    e2ee_key_backups tablosuna yazılır. Sunucu yalnızca şifreli veriyi görür.
//  - Türetilen anahtar ve tuz bu cihazın güvenli deposunda da tutulur; böylece yedek,
//    anahtarlar değiştikçe parola sorulmadan güncellenir.
//  - Geri yükleme: parola girilir, anahtarlar bu cihaza sarılır, cihaz onaylanır.
//    Parolayı bilmek sahiplik kanıtı sayılır (kabul edilen tasarım kararı).
//  - Parola unutulursa yedek kurtarılamaz.
// ============================================================

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme.dart';
import 'e2ee_chat.dart';
import 'e2ee_device.dart';

class E2eeBackup {
  E2eeBackup._();
  static final E2eeBackup instance = E2eeBackup._();

  static const int minPasswordLength = 8;
  static const String _kKey = 'e2ee_backup_key_v1';
  static const String _kSalt = 'e2ee_backup_salt_v1';
  static const int _iterations = 200000;
  static final List<int> _aadBytes = utf8.encode('gettic-backup-v1');

  final FlutterSecureStorage _store = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final Xchacha20 _aead = Xchacha20.poly1305Aead();

  bool _busy = false;

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  Future<bool> isEnabled() async => (await _store.read(key: _kKey)) != null;

  /// Yedeği parolayla kurar (ya da parolayı değiştirir) ve hemen yazar.
  Future<void> setup(String password) async {
    if (password.length < minPasswordLength) {
      throw Exception('Parola en az $minPasswordLength karakter olmalı');
    }
    final salt = _randomBytes(16);
    final key = await _derive(password, salt);
    await _store.write(key: _kSalt, value: base64Encode(salt));
    await _store.write(key: _kKey, value: base64Encode(key));
    await _upload(key, salt);
  }

  /// Yedeği kapatır: yerel anahtarlar ve sunucudaki yedek silinir.
  Future<void> disable() async {
    await _store.delete(key: _kKey);
    await _store.delete(key: _kSalt);
    final uid = _uid;
    if (uid != null) {
      await Supabase.instance.client
          .from('e2ee_key_backups')
          .delete()
          .eq('user_id', uid);
    }
  }

  /// Anahtarlar değiştiğinde çağrılır. Yedek kapalıysa hiçbir şey yapmaz.
  Future<void> refreshIfEnabled() async {
    if (_busy) return;
    _busy = true;
    try {
      final k = await _store.read(key: _kKey);
      final s = await _store.read(key: _kSalt);
      if (k == null || s == null) return;
      await _upload(base64Decode(k), base64Decode(s));
    } catch (_) {
      // Yedek güncellenemedi; bir sonraki anahtar değişiminde tekrar denenir
    } finally {
      _busy = false;
    }
  }

  /// Parolayla yedeği geri yükler. Dönüş: geri yüklenen anahtar sayısı.
  Future<int> restore(String password) async {
    final uid = _uid;
    if (uid == null) throw Exception('Oturum açık değil');

    final row = await Supabase.instance.client
        .from('e2ee_key_backups')
        .select('salt, nonce, ct, mac')
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) throw Exception('Bu hesap için yedek bulunamadı');

    final salt = base64Decode(row['salt'] as String);
    final key = await _derive(password, salt);

    List<int> clear;
    try {
      clear = await _aead.decrypt(
        SecretBox(
          base64Decode(row['ct'] as String),
          nonce: base64Decode(row['nonce'] as String),
          mac: Mac(base64Decode(row['mac'] as String)),
        ),
        secretKey: SecretKey(key),
        aad: _aadBytes,
      );
    } catch (_) {
      throw Exception('Parola yanlış');
    }

    final data = jsonDecode(utf8.decode(clear)) as Map;
    final entries = List<Map<String, dynamic>>.from(data['keys'] as List);

    final count = await E2eeChat.instance.importKeyEntries(entries);
    await E2eeDevice.instance.markApprovedSelf();

    // Bu cihazda da yedek etkin olsun
    await _store.write(key: _kSalt, value: base64Encode(salt));
    await _store.write(key: _kKey, value: base64Encode(key));
    return count;
  }

  // ---------- yardımcılar ----------

  Future<void> _upload(List<int> key, List<int> salt) async {
    final uid = _uid;
    if (uid == null) return;
    final entries = await E2eeChat.instance.exportKeyEntries();
    final payload = utf8.encode(jsonEncode({'v': 1, 'keys': entries}));
    final nonce = _aead.newNonce();
    final box = await _aead.encrypt(
      payload,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: _aadBytes,
    );
    await Supabase.instance.client.from('e2ee_key_backups').upsert({
      'user_id': uid,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ct': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<List<int>> _derive(String password, List<int> salt) async {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 256,
    );
    final key = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  List<int> _randomBytes(int n) {
    final rnd = Random.secure();
    return List<int>.generate(n, (_) => rnd.nextInt(256));
  }
}

// ============================================================
// DİYALOGLAR
// ============================================================

/// Yedek parolası belirleme. Kaydedilirse true döner.
Future<bool?> showBackupSetupDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _BackupSetupDialog(),
  );
}

/// Parolayla geri yükleme. Başarılıysa geri yüklenen anahtar sayısını döner.
Future<int?> showBackupRestoreDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (_) => const _BackupRestoreDialog(),
  );
}

class _BackupSetupDialog extends StatefulWidget {
  const _BackupSetupDialog();

  @override
  State<_BackupSetupDialog> createState() => _BackupSetupDialogState();
}

class _BackupSetupDialogState extends State<_BackupSetupDialog> {
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p = _pass.text;
    if (p.length < E2eeBackup.minPasswordLength) {
      setState(() => _error =
          'Parola en az ${E2eeBackup.minPasswordLength} karakter olmalı');
      return;
    }
    if (p != _pass2.text) {
      setState(() => _error = 'Parolalar eşleşmiyor');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await E2eeBackup.instance.setup(p);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Yedek kaydedilemedi: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text('Anahtar yedeği', style: TextStyle(color: c.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Yedek parolası hesap parolanızdan farklı olmalı. '
              'Bu parolayı unutursanız yedek kurtarılamaz.',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Yedek parolası'),
            ),
            TextField(
              controller: _pass2,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Parola (tekrar)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(color: c.danger, fontSize: 13)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('İptal'),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Kaydet', style: TextStyle(color: c.primary)),
        ),
      ],
    );
  }
}

class _BackupRestoreDialog extends StatefulWidget {
  const _BackupRestoreDialog();

  @override
  State<_BackupRestoreDialog> createState() => _BackupRestoreDialogState();
}

class _BackupRestoreDialogState extends State<_BackupRestoreDialog> {
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    if (_pass.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await E2eeBackup.instance.restore(_pass.text);
      if (mounted) Navigator.pop(context, n);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text('Yedekten geri yükle',
          style: TextStyle(color: c.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pass,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Yedek parolası'),
            onSubmitted: (_) => _restore(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: TextStyle(color: c.danger, fontSize: 13)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        TextButton(
          onPressed: _busy ? null : _restore,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Geri yükle', style: TextStyle(color: c.primary)),
        ),
      ],
    );
  }
}
