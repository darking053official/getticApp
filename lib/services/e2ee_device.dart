// ============================================================
// lib/services/e2ee_device.dart
//
// Asama 1: cihaz kimlik anahtarlari.
//  - X25519 (anahtar anlasmasi) ve Ed25519 (imza) ciftini uretir.
//  - Ozel anahtarlar isletim sisteminin guvenli deposunda kalir, sunucuya gitmez.
//  - Acik anahtarlar "devices" tablosuna kaydedilir.
//  - Bu servis henuz hicbir yerden cagrilmaz; mevcut mesajlasmayi etkilemez.
//
// Gerekli paketler: cryptography, flutter_secure_storage
// Linux'ta libsecret yoksa guvenli depo acilamaz; E2EE o cihazda kullanilamaz.
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class E2eeDeviceException implements Exception {
  final String message;
  E2eeDeviceException(this.message);
  @override
  String toString() => message;
}

/// Cihazın kimlik bilgileri (özel anahtarlar burada bellekte tutulur).
class DeviceIdentity {
  final String deviceId; // devices.id
  final SimpleKeyPair x25519; // anahtar anlaşması
  final SimpleKeyPair ed25519; // imza
  final String x25519PubB64;
  final String ed25519PubB64;

  DeviceIdentity({
    required this.deviceId,
    required this.x25519,
    required this.ed25519,
    required this.x25519PubB64,
    required this.ed25519PubB64,
  });
}

class E2eeDevice {
  E2eeDevice._();
  static final E2eeDevice instance = E2eeDevice._();

  static const _kDeviceId = 'e2ee_device_id_v1';
  static const _kX25519Seed = 'e2ee_x25519_seed_v1';
  static const _kEd25519Seed = 'e2ee_ed25519_seed_v1';

  final FlutterSecureStorage _store = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  DeviceIdentity? _cached;

  /// Cihaz kimliğini döndürür. Yoksa üretir, depoya yazar ve sunucuya kaydeder.
  Future<DeviceIdentity> ensureIdentity() async {
    if (_cached != null) return _cached!;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw E2eeDeviceException('Oturum açık değil');

    final existingId = await _read(_kDeviceId);
    final xSeedB64 = await _read(_kX25519Seed);
    final edSeedB64 = await _read(_kEd25519Seed);

    if (existingId != null && xSeedB64 != null && edSeedB64 != null) {
      final x = await X25519().newKeyPairFromSeed(base64Decode(xSeedB64));
      final ed = await Ed25519().newKeyPairFromSeed(base64Decode(edSeedB64));
      final identity = await _build(existingId, x, ed);
      _cached = identity;
      await _touch(existingId);
      return identity;
    }

    // Yeni cihaz: anahtarları üret, önce depoya yaz, sonra sunucuya kaydet
    final x = await X25519().newKeyPair();
    final ed = await Ed25519().newKeyPair();
    final xSeed = await x.extractPrivateKeyBytes();
    final edSeed = await ed.extractPrivateKeyBytes();

    final xPub = await x.extractPublicKey();
    final edPub = await ed.extractPublicKey();

    final row = await Supabase.instance.client.from('devices').insert({
      'user_id': user.id,
      'name': _deviceName(),
      'identity_pub_x25519': base64Encode(xPub.bytes),
      'identity_pub_ed25519': base64Encode(edPub.bytes),
    }).select('id').single();

    final deviceId = row['id'].toString();

    await _write(_kX25519Seed, base64Encode(xSeed));
    await _write(_kEd25519Seed, base64Encode(edSeed));
    await _write(_kDeviceId, deviceId);

    final identity = await _build(deviceId, x, ed);
    _cached = identity;
    return identity;
  }

  /// Cihaz kaydını siler (çıkışta veya anahtar sıfırlamada). Yerel anahtarlar da silinir.
  Future<void> forgetDevice() async {
    final id = await _read(_kDeviceId);
    if (id != null) {
      try {
        await Supabase.instance.client
            .from('devices')
            .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', id);
      } catch (_) {}
    }
    await _store.delete(key: _kDeviceId);
    await _store.delete(key: _kX25519Seed);
    await _store.delete(key: _kEd25519Seed);
    _cached = null;
  }

  // ---------- yardımcılar ----------

  Future<DeviceIdentity> _build(
      String deviceId, SimpleKeyPair x, SimpleKeyPair ed) async {
    final xPub = await x.extractPublicKey();
    final edPub = await ed.extractPublicKey();
    return DeviceIdentity(
      deviceId: deviceId,
      x25519: x,
      ed25519: ed,
      x25519PubB64: base64Encode(xPub.bytes),
      ed25519PubB64: base64Encode(edPub.bytes),
    );
  }

  Future<void> _touch(String deviceId) async {
    try {
      await Supabase.instance.client
          .from('devices')
          .update({'last_seen_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', deviceId);
    } catch (_) {}
  }

  Future<String?> _read(String key) async {
    try {
      return await _store.read(key: key);
    } catch (e) {
      throw E2eeDeviceException(
          'Güvenli depoya erişilemedi. Linux\'ta libsecret kurulu olmalı. ($e)');
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _store.write(key: key, value: value);
    } catch (e) {
      throw E2eeDeviceException('Güvenli depoya yazılamadı: $e');
    }
  }

  String _deviceName() {
    final os = Platform.operatingSystem;
    return 'Gettic ($os)';
  }
}
