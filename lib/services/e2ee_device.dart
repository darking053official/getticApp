// ============================================================
// lib/services/e2ee_device.dart
// (.txt olarak verildi. Projeye eklerken adını e2ee_device.dart yapın.)
//
// Aşama 1: cihaz kimlik anahtarları.
//  - X25519 (anahtar anlaşması) ve Ed25519 (imza) çifti üretir.
//  - Özel anahtarlar işletim sisteminin güvenli deposunda kalır, sunucuya gitmez.
//  - Açık anahtarlar "devices" tablosuna kaydedilir.
//  - Bu servis henüz hiçbir yerden çağrılmaz; mevcut mesajlaşmayı etkilemez.
//
// Gerekli paketler: cryptography, flutter_secure_storage
// Linux'ta libsecret yoksa güvenli depo açılamaz; E2EE o cihazda kullanılamaz.
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
  final bool approved; // onaylı değilse yeni anahtar sürümü almaz, mesaj gönderemez

  DeviceIdentity({
    required this.deviceId,
    required this.x25519,
    required this.ed25519,
    required this.x25519PubB64,
    required this.ed25519PubB64,
    this.approved = false,
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
      final approved = await _fetchApproved(existingId);
      final identity = await _build(existingId, x, ed, approved: approved);
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

    // İlk cihaz otomatik onaylanır; sonradan eklenenler mevcut bir cihazın onayını bekler
    final hasOthers = await _hasOtherActiveDevices(user.id);
    final row = await Supabase.instance.client.from('devices').insert({
      'user_id': user.id,
      'name': _deviceName(),
      'identity_pub_x25519': base64Encode(xPub.bytes),
      'identity_pub_ed25519': base64Encode(edPub.bytes),
      'approved_at': hasOthers ? null : DateTime.now().toUtc().toIso8601String(),
    }).select('id').single();

    final deviceId = row['id'].toString();

    await _write(_kX25519Seed, base64Encode(xSeed));
    await _write(_kEd25519Seed, base64Encode(edSeed));
    await _write(_kDeviceId, deviceId);

    final identity = await _build(deviceId, x, ed, approved: !hasOthers);
    _cached = identity;
    return identity;
  }

  /// Onay durumunu sunucudan yeniden okur (başka cihaz onayladıysa bu cihaz da onaylanır).
  Future<bool> refreshApproval() async {
    final c = _cached;
    if (c == null) return false;
    final approved = await _fetchApproved(c.deviceId);
    if (approved != c.approved) {
      _cached = null;
      await ensureIdentity();
    }
    return approved;
  }

  /// Yedekten geri yükleme sonrası: parolayı bilen bu cihazı onaylar.
  Future<void> markApprovedSelf() async {
    final me = await ensureIdentity();
    await Supabase.instance.client
        .from('devices')
        .update({'approved_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', me.deviceId);
    await refreshApproval();
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

  Future<bool> _hasOtherActiveDevices(String userId) async {
    final rows = await Supabase.instance.client
        .from('devices')
        .select('id')
        .eq('user_id', userId)
        .isFilter('revoked_at', null)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  Future<bool> _fetchApproved(String deviceId) async {
    try {
      final row = await Supabase.instance.client
          .from('devices')
          .select('approved_at')
          .eq('id', deviceId)
          .maybeSingle();
      return row != null && row['approved_at'] != null;
    } catch (_) {
      return false;
    }
  }

  Future<DeviceIdentity> _build(
      String deviceId, SimpleKeyPair x, SimpleKeyPair ed,
      {required bool approved}) async {
    final xPub = await x.extractPublicKey();
    final edPub = await ed.extractPublicKey();
    return DeviceIdentity(
      deviceId: deviceId,
      x25519: x,
      ed25519: ed,
      x25519PubB64: base64Encode(xPub.bytes),
      ed25519PubB64: base64Encode(edPub.bytes),
      approved: approved,
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
