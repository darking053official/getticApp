// lib/services/e2ee_link.dart
//
// Aşama 5: cihaz bağlama.
//  1. Yeni cihaz, açık anahtarlarını içeren bir "bağlantı metni" üretir.
//  2. Her iki cihazda aynı 6 haneli kod görünür. Kullanıcı karşılaştırır.
//  3. Mevcut (onaylı) cihaz kodu onaylarsa, bildiği sohbet anahtarlarını
//     yeni cihazın açık anahtarıyla sarar ve cihazı onaylar.
// Sunucu araya girip sahte bir cihaz ekleyemez: kodlar iki cihazda farklı olur.

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'e2ee_chat.dart';
import 'e2ee_device.dart';

class E2eeLink {
  E2eeLink._();
  static final E2eeLink instance = E2eeLink._();

  String? _nonce; // bu oturumdaki bağlantı için rastgele değer

  /// Yeni cihazın bağlantı metni: {"d": deviceId, "x": x25519, "e": ed25519, "n": nonce}
  Future<String> pendingPayload() async {
    final me = await E2eeDevice.instance.ensureIdentity();
    _nonce ??= _randomHex(16);
    return jsonEncode({
      'd': me.deviceId,
      'x': me.x25519PubB64,
      'e': me.ed25519PubB64,
      'n': _nonce,
    });
  }

  /// İki cihazda da aynı olan 6 haneli karşılaştırma kodu.
  Future<String> codeFor(String payloadJson) async {
    final p = _parse(payloadJson);
    final material = utf8.encode('${p['d']}|${p['x']}|${p['e']}|${p['n']}');
    final hash = await Sha256().hash(material);
    final b = hash.bytes;
    final n = ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) % 1000000;
    return n.toString().padLeft(6, '0');
  }

  /// Yeni cihazın bağlantı metnini doğrular ve bilgilerini döndürür.
  Future<Map<String, dynamic>> verify(String payloadJson) async {
    final p = _parse(payloadJson);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw Exception('Oturum açık değil');

    final row = await Supabase.instance.client
        .from('devices')
        .select(
            'id, user_id, identity_pub_x25519, identity_pub_ed25519, approved_at, revoked_at')
        .eq('id', p['d'])
        .maybeSingle();

    if (row == null ||
        row['user_id'] != userId ||
        row['identity_pub_x25519'] != p['x'] ||
        row['identity_pub_ed25519'] != p['e'] ||
        row['revoked_at'] != null) {
      throw Exception(
          'Cihaz doğrulanamadı. Bağlantı metnini yeniden kopyalayın.');
    }
    return {...p, 'approved': row['approved_at'] != null};
  }

  /// Yeni cihazı onaylar: sohbet anahtarlarını sarar, sonra cihazı onaylı işaretler.
  Future<void> approve(String payloadJson) async {
    final info = await verify(payloadJson);
    final me = await E2eeDevice.instance.ensureIdentity();
    if (!me.approved) throw E2eePendingException();
    if (info['approved'] == true) return;

    await E2eeChat.instance.shareHistoryWith(
      targetDeviceId: info['d'] as String,
      targetX25519PubB64: info['x'] as String,
    );

    await Supabase.instance.client
        .from('devices')
        .update({'approved_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', info['d'] as String);
  }

  /// Bu cihaz onaylanana kadar bekler. Onaylanınca true döner.
  Future<bool> waitForApproval(
      {Duration timeout = const Duration(minutes: 5)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (await E2eeDevice.instance.refreshApproval()) return true;
      await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  // ---------- yardımcılar ----------

  Map<String, dynamic> _parse(String payloadJson) {
    final m = jsonDecode(payloadJson.trim());
    if (m is! Map ||
        m['d'] == null ||
        m['x'] == null ||
        m['e'] == null ||
        m['n'] == null) {
      throw Exception('Geçersiz bağlantı metni');
    }
    return Map<String, dynamic>.from(m);
  }

  String _randomHex(int bytes) {
    final rnd = Random.secure();
    return List<int>.generate(bytes, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
