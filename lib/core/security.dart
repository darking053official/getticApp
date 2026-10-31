// ============================================================
// lib/core/security.dart
//
// Gettic güvenlik katmanı. Tamamı saf Dart'tır; Android, iOS, Windows,
// macOS ve Linux'ta aynı çalışır (flutter_secure_storage gerektirmez).
//
// GEREKEN PAKETLER (pubspec.yaml -> dependencies):
//   pointycastle: ^3.9.1     (zaten çözümlenmiş sürüm, ek indirme yok)
//   crypto: ^3.0.3           (zaten çözümlenmiş sürüm, ek indirme yok)
//   shared_preferences: 2.2.3 (zaten var)
//
// İÇERİK
//   Crypto          AES-256-GCM şifreleme, PBKDF2-SHA256, HKDF, güvenli rastgele,
//                   SHA-256/HMAC, sabit zamanlı karşılaştırma, kendi kendini test
//   SecureVault     Parolayla açılan şifreli kasa (zarf şifreleme), deneme
//                   sınırlama, otomatik kilit
//   EncryptedPrefs  Kasa açıkken şifreli anahtar-değer deposu
//   SecureClipboard Panoya kopyala, süre sonra otomatik temizle
//   SecureFiles     Dosyayı üzerine yazarak sil (en iyi çaba)
//   InputGuard      E-posta, dosya adı, URL doğrulama; log maskeleme
//   PasswordReport  Parola gücü analizi
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show Random, log, ln2;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// HATALAR
// ============================================================
class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}

/// Çok fazla hatalı denemeden sonra kasa geçici olarak kilitlenir.
class VaultLockedOutException extends SecurityException {
  final Duration remaining;
  VaultLockedOutException(this.remaining)
      : super('Çok fazla hatalı deneme. ${remaining.inSeconds} saniye sonra tekrar dene.');
}

// ============================================================
// KRİPTO
// ============================================================
class Crypto {
  Crypto._();

  // ---- Biçim sürümleri ----
  // v1 (anahtarla):  [0x01][nonce 12][şifreli veri + etiket 16]
  // v2 (parolayla):  [0x02][iterasyon 4][salt 16][nonce 12][şifreli veri + etiket 16]
  // Başlık (sürüm, iterasyon, salt) AAD olarak doğrulanır; kurcalanırsa çözme başarısız olur.
  static const int _versionKey = 1;
  static const int _versionPassword = 2;

  static const int keyLength = 32; // AES-256
  static const int nonceLength = 12; // GCM için önerilen 96 bit
  static const int saltLength = 16;
  static const int tagLength = 16; // 128 bit kimlik doğrulama etiketi

  /// PBKDF2-HMAC-SHA256 iterasyonu (OWASP 2023 önerisi: 600.000).
  /// Değer şifreli verinin başlığında saklanır; ileride artırılabilir,
  /// eski veriler kendi iterasyonuyla açılmaya devam eder.
  static const int defaultIterations = 600000;
  static const int _minIterations = 10000;
  static const int _maxIterations = 10000000; // sahte dosyayla DoS'u önler

  static final Random _rng = Random.secure();

  // ---------- Rastgelelik ----------
  static Uint8List randomBytes(int length) {
    final b = Uint8List(length);
    for (var i = 0; i < length; i++) {
      b[i] = _rng.nextInt(256);
    }
    return b;
  }

  /// URL'de güvenle kullanılabilir rastgele token (varsayılan 256 bit).
  static String randomToken([int bytes = 32]) =>
      base64Url.encode(randomBytes(bytes)).replaceAll('=', '');

  /// Yeni rastgele AES-256 anahtarı.
  static Uint8List generateKey() => randomBytes(keyLength);

  // ---------- Özet / HMAC / karşılaştırma ----------
  static String sha256Hex(List<int> data) =>
      crypto.sha256.convert(data).toString();

  static String sha256HexOfString(String s) => sha256Hex(utf8.encode(s));

  static Uint8List hmacSha256(List<int> key, List<int> data) =>
      Uint8List.fromList(crypto.Hmac(crypto.sha256, key).convert(data).bytes);

  /// Zamanlama saldırılarına karşı sabit sürede karşılaştırır.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a[i] ^ b[i];
    }
    return r == 0;
  }

  /// Bellekteki gizli veriyi sıfırlar.
  static void wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

  static String toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  // ---------- Anahtar türetme ----------
  /// Paroladan AES anahtarı türetir (PBKDF2-HMAC-SHA256). Senkron; yavaştır.
  static Uint8List deriveKeySync(
    String password,
    List<int> salt,
    int iterations, {
    int length = keyLength,
  }) {
    if (iterations < 1) throw ArgumentError('iterations >= 1 olmalı');
    final d = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    d.init(pc.Pbkdf2Parameters(Uint8List.fromList(salt), iterations, length));
    return d.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// Arayüzü dondurmamak için ayrı isolate'te çalışır.
  static Future<Uint8List> deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) async {
    final saltCopy = Uint8List.fromList(salt);
    try {
      return await Isolate.run(
          () => deriveKeySync(password, saltCopy, iterations));
    } on UnsupportedError {
      return deriveKeySync(password, saltCopy, iterations);
    }
  }

  /// HKDF-SHA256 (RFC 5869). Tek anahtardan amaca özel alt anahtarlar üretir.
  static Uint8List hkdfSha256(
    List<int> ikm, {
    List<int>? salt,
    List<int> info = const <int>[],
    int length = 32,
  }) {
    if (length < 1 || length > 255 * 32) {
      throw ArgumentError('length 1..8160 arasında olmalı');
    }
    final s = (salt == null || salt.isEmpty) ? List<int>.filled(32, 0) : salt;
    final prk = crypto.Hmac(crypto.sha256, s).convert(ikm).bytes;
    final okm = BytesBuilder();
    var t = <int>[];
    var counter = 1;
    while (okm.length < length) {
      t = crypto.Hmac(crypto.sha256, prk)
          .convert(<int>[...t, ...info, counter]).bytes;
      okm.add(t);
      counter++;
    }
    return Uint8List.fromList(okm.toBytes().sublist(0, length));
  }

  // ---------- AES-256-GCM (anahtarla) ----------
  /// [key] 32 bayt olmalı. [aad] şifrelenmez ama doğrulanır (örn. kayıt kimliği).
  static Uint8List encrypt(Uint8List plaintext, Uint8List key,
      {List<int>? aad}) {
    _checkKey(key);
    final nonce = randomBytes(nonceLength);
    final header = Uint8List.fromList([_versionKey]);
    final ct = _gcm(true, key, nonce, plaintext, _join([header, aad ?? const <int>[]]));
    return _join([header, nonce, ct]);
  }

  static Uint8List decrypt(Uint8List data, Uint8List key, {List<int>? aad}) {
    _checkKey(key);
    if (data.length < 1 + nonceLength + tagLength || data[0] != _versionKey) {
      throw const SecurityException('Geçersiz veya desteklenmeyen şifreli veri');
    }
    final header = Uint8List.fromList([data[0]]);
    final nonce = Uint8List.fromList(data.sublist(1, 1 + nonceLength));
    final ct = Uint8List.fromList(data.sublist(1 + nonceLength));
    return _gcmSafe(false, key, nonce, ct, _join([header, aad ?? const <int>[]]));
  }

  /// Metni şifreler, base64 döndürür. [context] verinin bağlandığı alan adıdır
  /// (örn. kayıt anahtarı); başka alana taşınırsa çözülemez.
  static String encryptString(String text, Uint8List key, {String? context}) {
    final enc = encrypt(
      Uint8List.fromList(utf8.encode(text)),
      key,
      aad: context == null ? null : utf8.encode(context),
    );
    return base64.encode(enc);
  }

  static String decryptString(String b64, Uint8List key, {String? context}) {
    final Uint8List raw;
    try {
      raw = base64.decode(b64);
    } on FormatException {
      throw const SecurityException('Geçersiz şifreli veri biçimi');
    }
    final plain = decrypt(raw, key,
        aad: context == null ? null : utf8.encode(context));
    return utf8.decode(plain);
  }

  // ---------- AES-256-GCM (parolayla) ----------
  static Future<Uint8List> encryptWithPassword(
    Uint8List plaintext,
    String password, {
    int iterations = defaultIterations,
    List<int>? aad,
  }) async {
    if (iterations < _minIterations || iterations > _maxIterations) {
      throw ArgumentError('iterations $_minIterations..$_maxIterations arasında olmalı');
    }
    final salt = randomBytes(saltLength);
    final key = await deriveKey(password, salt, iterations);
    try {
      final nonce = randomBytes(nonceLength);
      final header = _join([
        [_versionPassword],
        _u32(iterations),
        salt,
      ]);
      final ct = _gcm(true, key, nonce, plaintext, _join([header, aad ?? const <int>[]]));
      return _join([header, nonce, ct]);
    } finally {
      wipe(key);
    }
  }

  static Future<Uint8List> decryptWithPassword(
    Uint8List data,
    String password, {
    List<int>? aad,
  }) async {
    const headerLen = 1 + 4 + saltLength;
    if (data.length < headerLen + nonceLength + tagLength ||
        data[0] != _versionPassword) {
      throw const SecurityException('Geçersiz veya desteklenmeyen şifreli veri');
    }
    final iterations = ByteData.sublistView(data, 1, 5).getUint32(0);
    if (iterations < _minIterations || iterations > _maxIterations) {
      throw const SecurityException('Geçersiz anahtar türetme ayarı');
    }
    final header = Uint8List.fromList(data.sublist(0, headerLen));
    final salt = Uint8List.fromList(data.sublist(5, headerLen));
    final nonce = Uint8List.fromList(data.sublist(headerLen, headerLen + nonceLength));
    final ct = Uint8List.fromList(data.sublist(headerLen + nonceLength));

    final key = await deriveKey(password, salt, iterations);
    try {
      return _gcmSafe(false, key, nonce, ct, _join([header, aad ?? const <int>[]]));
    } finally {
      wipe(key);
    }
  }

  static Future<String> encryptStringWithPassword(
      String text, String password) async {
    final enc = await encryptWithPassword(
        Uint8List.fromList(utf8.encode(text)), password);
    return base64.encode(enc);
  }

  static Future<String> decryptStringWithPassword(
      String b64, String password) async {
    final Uint8List raw;
    try {
      raw = base64.decode(b64);
    } on FormatException {
      throw const SecurityException('Geçersiz şifreli veri biçimi');
    }
    return utf8.decode(await decryptWithPassword(raw, password));
  }

  // ---------- Dosya ----------
  /// Dosyayı parolayla şifreler. Tüm dosya belleğe okunur, [maxBytes] ile sınırlıdır.
  static Future<void> encryptFile(
    File input,
    File output,
    String password, {
    int maxBytes = 100 * 1024 * 1024,
  }) async {
    if (await input.length() > maxBytes) {
      throw const SecurityException('Dosya şifrelemek için çok büyük');
    }
    final enc = await encryptWithPassword(await input.readAsBytes(), password);
    await output.writeAsBytes(enc, flush: true);
  }

  static Future<void> decryptFile(
    File input,
    File output,
    String password, {
    int maxBytes = 120 * 1024 * 1024,
  }) async {
    if (await input.length() > maxBytes) {
      throw const SecurityException('Dosya çözmek için çok büyük');
    }
    final plain = await decryptWithPassword(await input.readAsBytes(), password);
    await output.writeAsBytes(plain, flush: true);
  }

  // ---------- Kendi kendini test ----------
  /// Bilinen test vektörleriyle şifreleme altyapısını doğrular.
  /// Geliştirmede `assert(Crypto.selfTest());` olarak çağırabilirsin.
  static bool selfTest() {
    try {
      // AES-256-GCM: McGrew/Viega GCM Test Case 14
      final out = _gcm(true, Uint8List(32), Uint8List(12), Uint8List(16), Uint8List(0));
      if (toHex(out) !=
          'cea7403d4d606b6e074ec5d3baf39d18d0d1c8a799996bf0265b98b5d48ab919') {
        return false;
      }

      // PBKDF2-HMAC-SHA256: RFC 7914 §11 (P="passwd", S="salt", c=1)
      final dk = deriveKeySync('passwd', utf8.encode('salt'), 1);
      if (toHex(dk) !=
          '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc') {
        return false;
      }

      // HKDF-SHA256: RFC 5869 Test Case 1
      final okm = hkdfSha256(
        List<int>.filled(22, 0x0b),
        salt: List<int>.generate(13, (i) => i),
        info: List<int>.generate(10, (i) => 0xf0 + i),
        length: 42,
      );
      if (toHex(okm) !=
          '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865') {
        return false;
      }

      // Gidiş-dönüş + kurcalama tespiti
      final key = generateKey();
      final enc = encrypt(Uint8List.fromList(utf8.encode('merhaba')), key);
      if (utf8.decode(decrypt(enc, key)) != 'merhaba') return false;
      enc[enc.length - 1] ^= 0x01;
      try {
        decrypt(enc, key);
        return false; // kurcalanmış veri çözülmemeliydi
      } on SecurityException {
        // beklenen
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- İç yardımcılar ----------
  static void _checkKey(Uint8List key) {
    if (key.length != keyLength) {
      throw ArgumentError('Anahtar $keyLength bayt (AES-256) olmalı');
    }
  }

  static Uint8List _gcm(bool encrypt, Uint8List key, Uint8List nonce,
      Uint8List input, List<int> aad) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    cipher.init(
      encrypt,
      pc.AEADParameters(
        pc.KeyParameter(key),
        tagLength * 8,
        nonce,
        Uint8List.fromList(aad),
      ),
    );
    return cipher.process(input);
  }

  static Uint8List _gcmSafe(bool encrypt, Uint8List key, Uint8List nonce,
      Uint8List input, List<int> aad) {
    try {
      return _gcm(encrypt, key, nonce, input, aad);
    } on pc.InvalidCipherTextException {
      throw const SecurityException(
          'Çözme başarısız: parola/anahtar yanlış ya da veri bozulmuş');
    } on ArgumentError {
      throw const SecurityException('Çözme başarısız: veri geçersiz');
    } on StateError {
      throw const SecurityException('Çözme başarısız: veri geçersiz');
    }
  }

  static Uint8List _join(List<List<int>> parts) {
    final b = BytesBuilder(copy: false);
    for (final p in parts) {
      b.add(p);
    }
    return b.toBytes();
  }

  static Uint8List _u32(int v) {
    final b = Uint8List(4);
    b.buffer.asByteData().setUint32(0, v); // big-endian
    return b;
  }
}

// ============================================================
// ŞİFRELİ KASA (zarf şifreleme)
//
// Nasıl çalışır:
//   1. Rastgele 256 bit "veri anahtarı" üretilir.
//   2. Bu anahtar, kullanıcının parolasından türetilen anahtarla (PBKDF2 +
//      AES-GCM) şifrelenip cihazda saklanır.
//   3. Kasa açılınca veri anahtarı yalnızca bellekte tutulur; kilitlenince
//      sıfırlanır. Parola değişince sadece anahtar yeniden sarılır, veriler
//      yeniden şifrelenmez.
//
// Sınırlar (dürüstçe):
//   - Parolanın gücü kasanın gücüdür. 4-6 haneli PIN, cihaz dosyalarına erişen
//     biri tarafından çevrimdışı denenebilir. En az 8 karakterli bir parola kullan.
//   - Deneme sınırı yalnızca uygulama arayüzü içindir; cihaz verisini silen/
//     kopyalayan biri bunu atlatabilir.
//   - Parola unutulursa veriler kurtarılamaz.
// ============================================================
class SecureVault extends ChangeNotifier with WidgetsBindingObserver {
  SecureVault._();
  static final SecureVault instance = SecureVault._();

  static const String _kVault = 'security_vault_v1';
  static const String _kFails = 'security_vault_fails';
  static const String _kLockUntil = 'security_vault_lock_until';

  static const int minSecretLength = 4;
  static const int _freeAttempts = 5;

  Uint8List? _dataKey;
  bool _observing = false;
  DateTime? _backgroundedAt;

  /// Uygulama bu süre arka planda kalırsa kasa otomatik kilitlenir.
  Duration autoLockAfter = const Duration(minutes: 1);

  bool get isUnlocked => _dataKey != null;

  Future<bool> get isSetUp async {
    final p = await SharedPreferences.getInstance();
    return p.containsKey(_kVault);
  }

  /// Kalan bekleme süresi (kilitli değilse null).
  Future<Duration?> lockoutRemaining() async {
    final p = await SharedPreferences.getInstance();
    return _remainingLockout(p);
  }

  /// İlk kurulum. Kasa kurulduktan sonra açık kalır.
  Future<void> setUp(String secret) async {
    _validateSecret(secret);
    final p = await SharedPreferences.getInstance();
    if (p.containsKey(_kVault)) {
      throw const SecurityException('Kasa zaten kurulmuş');
    }
    final dataKey = Crypto.generateKey();
    final wrapped = await Crypto.encryptWithPassword(dataKey, secret);
    await p.setString(_kVault, base64.encode(wrapped));
    await _resetFailures(p);
    _dataKey = dataKey;
    notifyListeners();
  }

  /// Kasayı açar. Yanlış parolada [SecurityException], çok denemede
  /// [VaultLockedOutException] fırlatır.
  Future<void> unlock(String secret) async {
    final p = await SharedPreferences.getInstance();

    final remaining = _remainingLockout(p);
    if (remaining != null) throw VaultLockedOutException(remaining);

    final stored = p.getString(_kVault);
    if (stored == null) throw const SecurityException('Kasa kurulmamış');

    try {
      final key = await Crypto.decryptWithPassword(base64.decode(stored), secret);
      _dataKey = key;
      await _resetFailures(p);
      notifyListeners();
    } on SecurityException {
      await _registerFailure(p);
      final lock = _remainingLockout(p);
      if (lock != null) throw VaultLockedOutException(lock);
      throw const SecurityException('Parola yanlış');
    } on FormatException {
      throw const SecurityException('Kasa verisi bozuk');
    }
  }

  /// Anahtarı bellekten siler.
  void lock() {
    final k = _dataKey;
    if (k != null) Crypto.wipe(k);
    _dataKey = null;
    notifyListeners();
  }

  /// Parolayı değiştirir (eski parola doğrulanır, veriler yeniden şifrelenmez).
  Future<void> changeSecret(String oldSecret, String newSecret) async {
    _validateSecret(newSecret);
    await unlock(oldSecret); // doğrulama + deneme sınırı
    final key = _dataKey;
    if (key == null) throw const SecurityException('Kasa kilitli');
    final wrapped = await Crypto.encryptWithPassword(key, newSecret);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kVault, base64.encode(wrapped));
  }

  /// Kasayı tamamen siler. Bu kasayla şifrelenmiş veriler kurtarılamaz hale gelir.
  Future<void> reset() async {
    lock();
    final p = await SharedPreferences.getInstance();
    await p.remove(_kVault);
    await _resetFailures(p);
  }

  // ---- Şifreleme (kasa açıkken) ----
  /// [purpose]: amaca özel alt anahtar (ör. 'prefs', 'backup'). Bir alt anahtar
  /// sızsa bile diğerleri güvende kalır.
  Uint8List _subKey(String purpose) {
    final k = _dataKey;
    if (k == null) throw const SecurityException('Kasa kilitli');
    return Crypto.hkdfSha256(k, info: utf8.encode('gettic/v1/$purpose'));
  }

  Future<String> encryptString(String text,
      {String purpose = 'data', String? context}) async {
    final sub = _subKey(purpose);
    try {
      return Crypto.encryptString(text, sub, context: context);
    } finally {
      Crypto.wipe(sub);
    }
  }

  Future<String> decryptString(String b64,
      {String purpose = 'data', String? context}) async {
    final sub = _subKey(purpose);
    try {
      return Crypto.decryptString(b64, sub, context: context);
    } finally {
      Crypto.wipe(sub);
    }
  }

  // ---- Otomatik kilit ----
  /// Uygulama arka plana alınıp [after] süre geçerse kasayı kilitler.
  void enableAutoLock({Duration after = const Duration(minutes: 1)}) {
    autoLockAfter = after;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  void disableAutoLock() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final t = _backgroundedAt;
      _backgroundedAt = null;
      if (t != null &&
          isUnlocked &&
          DateTime.now().difference(t) >= autoLockAfter) {
        lock();
      }
    }
  }

  // ---- İç ----
  void _validateSecret(String s) {
    if (s.length < minSecretLength) {
      throw const SecurityException('Parola en az $minSecretLength karakter olmalı');
    }
  }

  Duration? _remainingLockout(SharedPreferences p) {
    final until = p.getInt(_kLockUntil);
    if (until == null) return null;
    final diff = until - DateTime.now().millisecondsSinceEpoch;
    return diff > 0 ? Duration(milliseconds: diff) : null;
  }

  Future<void> _registerFailure(SharedPreferences p) async {
    final fails = (p.getInt(_kFails) ?? 0) + 1;
    await p.setInt(_kFails, fails);
    if (fails >= _freeAttempts) {
      // 30 sn, 60 sn, 120 sn ... en fazla 15 dk
      final int exp = (fails - _freeAttempts).clamp(0, 5).toInt();
      final int seconds = (30 * (1 << exp)).clamp(30, 900).toInt();
      final int until =
          DateTime.now().millisecondsSinceEpoch + seconds * 1000;
      await p.setInt(_kLockUntil, until);
    }
  }

  Future<void> _resetFailures(SharedPreferences p) async {
    await p.remove(_kFails);
    await p.remove(_kLockUntil);
  }

  @override
  void dispose() {
    disableAutoLock();
    final k = _dataKey;
    if (k != null) Crypto.wipe(k);
    super.dispose();
  }
}

// ============================================================
// ŞİFRELİ ANAHTAR-DEĞER DEPOSU
// Kasa açıkken değerleri AES-256-GCM ile şifreleyip SharedPreferences'a yazar.
// Anahtar adı AAD olarak bağlanır; bir değer başka anahtara taşınırsa çözülmez.
// ============================================================
class EncryptedPrefs {
  EncryptedPrefs._();
  static const String _prefix = 'enc_';
  static const String _purpose = 'prefs';

  static Future<void> write(String key, String value) async {
    final enc = await SecureVault.instance
        .encryptString(value, purpose: _purpose, context: key);
    final p = await SharedPreferences.getInstance();
    await p.setString('$_prefix$key', enc);
  }

  /// Anahtar yoksa, kasa kilitliyse veya veri bozuksa null döner.
  static Future<String?> read(String key) async {
    final p = await SharedPreferences.getInstance();
    final stored = p.getString('$_prefix$key');
    if (stored == null) return null;
    try {
      return await SecureVault.instance
          .decryptString(stored, purpose: _purpose, context: key);
    } on SecurityException {
      return null;
    }
  }

  static Future<void> delete(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.remove('$_prefix$key');
  }
}

// ============================================================
// PANO
// ============================================================
class SecureClipboard {
  SecureClipboard._();
  static Timer? _timer;

  /// Metni kopyalar; [clearAfter] sonra pano hâlâ aynı metni içeriyorsa temizler.
  static Future<void> copy(
    String text, {
    Duration clearAfter = const Duration(seconds: 30),
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    _timer?.cancel();
    _timer = Timer(clearAfter, () async {
      try {
        final cur = await Clipboard.getData(Clipboard.kTextPlain);
        if (cur?.text == text) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } catch (_) {}
    });
  }
}

// ============================================================
// DOSYA
// ============================================================
class SecureFiles {
  SecureFiles._();

  /// Dosyanın içeriğini rastgele veriyle üzerine yazıp siler.
  /// En iyi çabadır: SSD/flash bellekte (aşınma dengeleme) ve kopya-yaz
  /// dosya sistemlerinde eski blokların kalmayacağı garanti edilemez.
  /// Asıl koruma, hassas dosyaları baştan şifreli saklamaktır.
  static Future<void> shred(File file, {int passes = 1}) async {
    try {
      if (!await file.exists()) return;
      final len = await file.length();
      final raf = await file.open(mode: FileMode.writeOnly);
      try {
        for (var pass = 0; pass < passes; pass++) {
          await raf.setPosition(0);
          var written = 0;
          while (written < len) {
            final n = (len - written) > 65536 ? 65536 : (len - written);
            await raf.writeFrom(Crypto.randomBytes(n));
            written += n;
          }
          await raf.flush();
        }
      } finally {
        await raf.close();
      }
    } catch (_) {
      // Üzerine yazılamasa bile silmeyi dene
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}

// ============================================================
// GİRDİ DOĞRULAMA / LOG GÜVENLİĞİ
// ============================================================
class InputGuard {
  InputGuard._();

  static final RegExp _email =
      RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$');

  static bool isValidEmail(String s) {
    final t = s.trim();
    return t.length <= 254 && _email.hasMatch(t);
  }

  /// Sunucuya/dosya sistemine giden dosya adlarını güvenli hale getirir:
  /// yol ayırıcıları (../), kontrol karakterleri ve Windows yasaklı adları temizlenir.
  static String sanitizeFileName(String name, {int maxLength = 100}) {
    var n = name.split(RegExp(r'[\\/]')).last;
    n = n.replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"|?*]'), '_');
    n = n.replaceAll(RegExp(r'^[.\s]+'), '').trim();
    if (n.isEmpty) n = 'dosya';

    const reserved = {
      'CON', 'PRN', 'AUX', 'NUL',
      'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
      'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
    };
    final dotIndex = n.indexOf('.');
    final baseName = (dotIndex == -1 ? n : n.substring(0, dotIndex)).toUpperCase();
    if (reserved.contains(baseName)) n = '_$n';

    if (n.length > maxLength) {
      final dot = n.lastIndexOf('.');
      if (dot > 0 && n.length - dot <= 10) {
        final ext = n.substring(dot);
        n = n.substring(0, maxLength - ext.length) + ext;
      } else {
        n = n.substring(0, maxLength);
      }
    }
    return n;
  }

  /// Yalnızca https ve geçerli sunucu adı olan URL'lere izin verir.
  static bool isSafeHttpsUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// ahmet@example.com -> a***t@example.com
  static String maskEmail(String email) {
    final at = email.indexOf('@');
    if (at < 1) return '***';
    final user = email.substring(0, at);
    final domain = email.substring(at);
    if (user.length <= 2) return '${user[0]}***$domain';
    return '${user[0]}***${user[user.length - 1]}$domain';
  }

  static final RegExp _jwt =
      RegExp(r'eyJ[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]*');
  static final RegExp _bearer =
      RegExp(r'bearer\s+[A-Za-z0-9._\-]+', caseSensitive: false);
  static final RegExp _emailInText =
      RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');

  /// Log/hata mesajlarındaki token ve e-postaları maskeler.
  static String redact(String text) {
    return text
        .replaceAll(_jwt, '[JWT]')
        .replaceAll(_bearer, 'Bearer [TOKEN]')
        .replaceAllMapped(_emailInText, (m) => maskEmail(m[0]!));
  }
}

// ============================================================
// PAROLA GÜCÜ
// ============================================================
enum PasswordStrength { veryWeak, weak, fair, strong, veryStrong }

class PasswordReport {
  final PasswordStrength strength;
  final double entropyBits;
  final List<String> hints;
  const PasswordReport(this.strength, this.entropyBits, this.hints);

  /// 0.0 - 1.0 (ilerleme çubuğu için)
  double get progress => (strength.index + 1) / PasswordStrength.values.length;

  String get label {
    switch (strength) {
      case PasswordStrength.veryWeak:
        return 'Çok zayıf';
      case PasswordStrength.weak:
        return 'Zayıf';
      case PasswordStrength.fair:
        return 'Orta';
      case PasswordStrength.strong:
        return 'Güçlü';
      case PasswordStrength.veryStrong:
        return 'Çok güçlü';
    }
  }

  /// Kayıt/parola değişikliğinde kabul edilebilir mi?
  bool get isAcceptable => strength.index >= PasswordStrength.fair.index;

  static const Set<String> _common = {
    'password', 'passw0rd', 'qwerty', 'qwertyuiop', 'abc123', 'letmein',
    'welcome', 'admin', 'login', 'iloveyou', 'monkey', 'dragon', 'football',
    'sifre', 'şifre', 'parola', 'gettic', 'turkiye', 'türkiye', 'galatasaray',
    'fenerbahce', 'fenerbahçe', 'besiktas', 'beşiktaş', 'trabzonspor',
    '12345678', '123456789', '1234567890', '1q2w3e4r', '1qaz2wsx', '11111111',
    '00000000', 'asdfghjkl', 'zxcvbnm', 'password1', 'sifre123', 'parola123',
  };

  static const List<String> _keyboardRows = [
    'qwertyuiop', 'asdfghjkl', 'zxcvbnm', '1234567890', 'qwertzuiop',
  ];

  static PasswordReport evaluate(String pw,
      {List<String> userInputs = const []}) {
    if (pw.isEmpty) {
      return const PasswordReport(
          PasswordStrength.veryWeak, 0, ['Parola boş olamaz']);
    }

    final hints = <String>[];
    final lower = pw.toLowerCase();

    var pool = 0;
    if (RegExp(r'[a-z]').hasMatch(pw)) pool += 26;
    if (RegExp(r'[A-Z]').hasMatch(pw)) pool += 26;
    if (RegExp(r'[0-9]').hasMatch(pw)) pool += 10;
    if (RegExp(r'[^A-Za-z0-9\u0080-\uFFFF]').hasMatch(pw)) pool += 33;
    if (RegExp(r'[\u0080-\uFFFF]').hasMatch(pw)) pool += 60;
    if (pool == 0) pool = 10;

    // Tekrarlanan karakterler etkin uzunluğu düşürür
    final unique = pw.runes.toSet().length;
    final effectiveLen = (pw.runes.length + unique) / 2;
    var entropy = effectiveLen * (log(pool) / ln2);

    if (pw.length < 12) hints.add('En az 12 karakter kullan');
    if (!RegExp(r'[a-zçğıöşü]').hasMatch(pw) ||
        !RegExp(r'[A-ZÇĞİÖŞÜ]').hasMatch(pw)) {
      hints.add('Büyük ve küçük harfleri birlikte kullan');
    }
    if (!RegExp(r'[0-9]').hasMatch(pw)) hints.add('Rakam ekle');
    if (!RegExp(r'[^A-Za-z0-9\u0080-\uFFFF]').hasMatch(pw)) {
      hints.add('Özel karakter ekle (! ? # vb.)');
    }

    // Çok kullanılan parolalar
    final stripped = lower.replaceAll(RegExp(r'[0-9!@#$%^&*._\-]+$'), '');
    if (_common.contains(lower) || _common.contains(stripped)) {
      entropy = entropy < 12 ? entropy : 12;
      hints.insert(0, 'Çok yaygın bir parola, kullanma');
    }

    // Ardışık / klavye dizileri
    if (_hasSequence(lower)) {
      entropy -= 8;
      hints.add('abc, 123 veya klavye sırası gibi dizilerden kaçın');
    }

    // Kişisel bilgi
    for (final input in userInputs) {
      final t = input.trim().toLowerCase();
      if (t.length >= 3 && lower.contains(t)) {
        entropy -= 15;
        hints.add('Ad, kullanıcı adı veya e-posta içermemeli');
        break;
      }
    }

    if (entropy < 0) entropy = 0;

    PasswordStrength s;
    if (entropy < 30) {
      s = PasswordStrength.veryWeak;
    } else if (entropy < 45) {
      s = PasswordStrength.weak;
    } else if (entropy < 60) {
      s = PasswordStrength.fair;
    } else if (entropy < 80) {
      s = PasswordStrength.strong;
    } else {
      s = PasswordStrength.veryStrong;
    }
    if (pw.length < 8 && s.index > PasswordStrength.weak.index) {
      s = PasswordStrength.weak;
    }

    return PasswordReport(s, entropy, hints);
  }

  static bool _hasSequence(String lower) {
    final codes = lower.codeUnits;
    for (var i = 0; i + 2 < codes.length; i++) {
      final d1 = codes[i + 1] - codes[i];
      final d2 = codes[i + 2] - codes[i + 1];
      if ((d1 == 1 && d2 == 1) || (d1 == -1 && d2 == -1)) return true;
    }
    if (lower.length >= 4) {
      for (final row in _keyboardRows) {
        final rev = row.split('').reversed.join();
        for (var i = 0; i + 4 <= lower.length; i++) {
          final part = lower.substring(i, i + 4);
          if (row.contains(part) || rev.contains(part)) return true;
        }
      }
    }
    return false;
  }
}
