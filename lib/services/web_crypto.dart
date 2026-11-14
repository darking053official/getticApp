// ============================================================
// lib/services/web_crypto.dart
// (.txt olarak verildi. Projeye eklerken adını web_crypto.dart yapın.)
//
// Web (gettic.dpdns.org) ve Firefox eklentisiyle BİREBİR aynı şifreleme:
//  - Anahtar: PBKDF2-HMAC-SHA256, parola, tuz = UTF-8 metin, AES-GCM 256 anahtar
//  - Şifreli değer: "base64(IV 12 bayt).base64(şifreli veri + 16 bayt etiket)"
//  - Doğrulama (check_b64): sabit metin, IV = 12 sıfır, önek: "v1:" / "v2:"
// Test: Node WebCrypto ile Python arasında iki yönlü doğrulandı.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart' as pc;

import '../core/security.dart';

class WebCrypto {
  WebCrypto._();

  static final Random _rng = Random.secure();

  /// PBKDF2-SHA256 ile 32 baytlık anahtar. Arayüzü dondurmamak için isolate'te çalışır.
  static Future<Uint8List> deriveKey(
      String password, String salt, int iterations) async {
    try {
      return await Isolate.run(() => _deriveSync(password, salt, iterations));
    } on UnsupportedError {
      return _deriveSync(password, salt, iterations);
    }
  }

  static Uint8List _deriveSync(String password, String salt, int iterations) {
    final d = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    d.init(pc.Pbkdf2Parameters(
      Uint8List.fromList(utf8.encode(salt)),
      iterations,
      32,
    ));
    return d.process(Uint8List.fromList(utf8.encode(password)));
  }

  static Uint8List _gcm(bool encrypt, Uint8List key, Uint8List iv, Uint8List input) {
    try {
      final cipher = pc.GCMBlockCipher(pc.AESEngine());
      cipher.init(
        encrypt,
        pc.AEADParameters(pc.KeyParameter(key), 128, iv, Uint8List(0)),
      );
      return cipher.process(input);
    } on pc.InvalidCipherTextException {
      throw const SecurityException('Şifre çözülemedi');
    }
  }

  static Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  /// Düz metni şifreler: "iv.ct"
  static String encryptText(String plain, Uint8List key) {
    final iv = _randomBytes(12);
    final ct = _gcm(true, key, iv, Uint8List.fromList(utf8.encode(plain)));
    return '${base64.encode(iv)}.${base64.encode(ct)}';
  }

  /// "iv.ct" biçimini çözer. Bozuk veya yanlış anahtarda SecurityException.
  static String decryptText(String payload, Uint8List key) {
    final parts = payload.split('.');
    if (parts.length != 2) throw const SecurityException('Geçersiz şifreli veri');
    final iv = base64.decode(parts[0]);
    final ct = base64.decode(parts[1]);
    final pt = _gcm(false, key, Uint8List.fromList(iv), Uint8List.fromList(ct));
    return utf8.decode(pt);
  }

  /// Doğrulama değeri üretir: prefix + base64(AES-GCM(magic), IV = 0)
  static String makeVerifier(Uint8List key, String magic, String prefix) {
    final ct = _gcm(true, key, Uint8List(12), Uint8List.fromList(utf8.encode(magic)));
    return '$prefix${base64.encode(ct)}';
  }

  /// Saklanan doğrulama değerini kontrol eder (önek "v1:", "v2:" ya da öneksiz olabilir).
  static bool checkVerifier(String stored, Uint8List key, String magic) {
    final body = stored.replaceFirst(RegExp(r'^v\d+:'), '');
    try {
      final pt = _gcm(false, key, Uint8List(12), Uint8List.fromList(base64.decode(body)));
      return utf8.decode(pt) == magic;
    } catch (_) {
      return false;
    }
  }

  /// RFC 4122 v4 UUID (veritabanı id'leri için)
  static String uuidV4() {
    final b = _randomBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// Eklentinin strengthOf() kuralının aynısı (background.js).
int webPasswordStrength(String pw) {
  if (pw.isEmpty) return 0;
  var s = 0;
  if (pw.length >= 8) s += 20;
  if (pw.length >= 12) s += 20;
  if (pw.length >= 16) s += 15;
  if (RegExp(r'[a-z]').hasMatch(pw)) s += 10;
  if (RegExp(r'[A-Z]').hasMatch(pw)) s += 10;
  if (RegExp(r'[0-9]').hasMatch(pw)) s += 10;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(pw)) s += 15;
  return s > 100 ? 100 : s;
}

/// Kasa arayüzü: PassCloud ve NotebookCloud bunu uygular.
abstract class CloudVault extends ChangeNotifier {
  /// Anahtar bellekte mi?
  bool get isUnlocked;

  /// Sunucuda doğrulama kaydı var mı? (kasa kurulmuş mu)
  Future<bool> hasVerifier();

  /// Mevcut kasayı parolayla açar.
  Future<void> unlock(String password);

  /// Yeni kasa oluşturur (doğrulama kaydını yazar) ve açar.
  Future<void> setup(String password);

  /// Parolayı değiştirir ve tüm kayıtları yeni anahtarla yeniden şifreler.
  Future<void> changePassword(String oldPassword, String newPassword);

  /// Anahtarı bellekten siler.
  void lock();
}
