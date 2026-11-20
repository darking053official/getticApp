// ============================================================
// lib/services/e2ee_chat.dart
// (.txt olarak verildi. Projeye eklerken adını e2ee_chat.dart yapın.)
//
// Aşama 2: 1:1 sohbet şifrelemesi.
//  - Sohbet anahtarı: 32 bayt rastgele, sohbeti ilk gönderen cihaz üretir.
//  - Sohbet anahtarı, sohbetteki her cihaz için ECDH (X25519) + HKDF + XChaCha20-Poly1305
//    ile sarılır ve e2ee_conversation_keys tablosuna yazılır.
//  - Mesaj: XChaCha20-Poly1305. AAD = conversationId|kv|gönderenCihaz.
//  - Zarf Ed25519 ile imzalanır; alıcı imzayı doğrular.
//  - Karşı tarafın E2EE cihazı yoksa encrypt() null döner, çağıran düz metin gönderir.
//
// Bilinen sınır: Sonradan eklenen bir cihaz eski anahtarları almaz (Aşama 5).
// ============================================================

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message.dart';
import 'e2ee_device.dart';

class _DevicePub {
  final SimplePublicKey x; // anahtar anlaşması
  final SimplePublicKey ed; // imza
  _DevicePub(this.x, this.ed);
}

class E2eeChat {
  E2eeChat._();
  static final E2eeChat instance = E2eeChat._();

  static const int _envVersion = 1;

  final Xchacha20 _aead = Xchacha20.poly1305Aead();
  final X25519 _x25519 = X25519();
  final Ed25519 _ed25519 = Ed25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  final Map<String, List<int>> _keyCache = {}; // "conv|kv" -> anahtar
  final Map<String, _DevicePub> _deviceCache = {}; // deviceId -> açık anahtarlar
  final Map<String, Message> _messageCache = {}; // messageId -> çözülmüş mesaj

  SupabaseClient get _sb => Supabase.instance.client;

  // ---------- Açık anahtarlar ----------

  Future<_DevicePub?> _devicePub(String deviceId) async {
    final cached = _deviceCache[deviceId];
    if (cached != null) return cached;
    final row = await _sb
        .from('devices')
        .select('identity_pub_x25519, identity_pub_ed25519')
        .eq('id', deviceId)
        .maybeSingle();
    if (row == null) return null;
    final dp = _DevicePub(
      SimplePublicKey(base64Decode(row['identity_pub_x25519'] as String),
          type: KeyPairType.x25519),
      SimplePublicKey(base64Decode(row['identity_pub_ed25519'] as String),
          type: KeyPairType.ed25519),
    );
    _deviceCache[deviceId] = dp;
    return dp;
  }

  // ---------- Sarma (wrap / unwrap) ----------

  List<int> _aad(String convId, int kv, String deviceId) =>
      utf8.encode('$convId|$kv|$deviceId');

  Future<SecretKey> _wrapKey(SimpleKeyPair myX, SimplePublicKey theirX) async {
    final shared =
        await _x25519.sharedSecretKey(keyPair: myX, remotePublicKey: theirX);
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('gettic-e2ee'),
      info: utf8.encode('wrap-v1'),
    );
  }

  Future<String> _wrap(List<int> key, SimpleKeyPair myX, String convId, int kv,
      String targetDeviceId, SimplePublicKey targetX) async {
    final wk = await _wrapKey(myX, targetX);
    final box = await _aead.encrypt(
      key,
      secretKey: wk,
      nonce: _aead.newNonce(),
      aad: _aad(convId, kv, targetDeviceId),
    );
    return base64Encode(box.concatenation());
  }

  Future<List<int>> _unwrap(String wrappedB64, SimpleKeyPair myX, String convId,
      int kv, String myDeviceId, SimplePublicKey senderX) async {
    final wk = await _wrapKey(myX, senderX);
    final box = SecretBox.fromConcatenation(
      base64Decode(wrappedB64),
      nonceLength: 24,
      macLength: 16,
    );
    return _aead.decrypt(
      box,
      secretKey: wk,
      aad: _aad(convId, kv, myDeviceId),
    );
  }

  // ---------- Sohbet anahtarı ----------

  /// Bu cihazın sohbet anahtarını döndürür (yoksa null).
  Future<_KeyRef?> _myKey(String convId, DeviceIdentity me) async {
    final row = await _sb
        .from('e2ee_conversation_keys')
        .select('key_version')
        .eq('conversation_id', convId)
        .eq('device_id', me.deviceId)
        .order('key_version', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    final kv = (row['key_version'] as num).toInt();
    final key = await _loadKey(convId, kv, me);
    if (key == null) return null;
    return _KeyRef(kv, key);
  }

  Future<List<int>?> _loadKey(String convId, int kv, DeviceIdentity me) async {
    final cacheKey = '$convId|$kv';
    final cached = _keyCache[cacheKey];
    if (cached != null) return cached;

    final row = await _sb
        .from('e2ee_conversation_keys')
        .select('wrapped_key, sender_device_id')
        .eq('conversation_id', convId)
        .eq('key_version', kv)
        .eq('device_id', me.deviceId)
        .maybeSingle();
    if (row == null || row['sender_device_id'] == null) return null;

    final sender = await _devicePub(row['sender_device_id'].toString());
    if (sender == null) return null;

    final key = await _unwrap(
      row['wrapped_key'] as String,
      me.x25519,
      convId,
      kv,
      me.deviceId,
      sender.x,
    );
    _keyCache[cacheKey] = key;
    return key;
  }

  /// Sohbetin yeni anahtarını üretir ve bu sohbetteki tüm (iptal edilmemiş) cihazlara sarar.
  /// Karşı tarafın cihazı yoksa null döner.
  Future<_KeyRef?> _createKey(String convId, DeviceIdentity me) async {
    final members = await _sb
        .from('conversation_members')
        .select('user_id')
        .eq('conversation_id', convId);
    final userIds = (members as List).map((m) => m['user_id'].toString()).toList();
    if (userIds.isEmpty) return null;

    final devices = await _sb
        .from('devices')
        .select('id, identity_pub_x25519')
        .inFilter('user_id', userIds)
        .isFilter('revoked_at', null);
    if ((devices as List).isEmpty) return null;

    final keyObj = await _aead.newSecretKey();
    final keyBytes = await keyObj.extractBytes();
    const kv = 1;

    final inserts = <Map<String, dynamic>>[];
    for (final d in devices) {
      final pub = SimplePublicKey(
        base64Decode(d['identity_pub_x25519'] as String),
        type: KeyPairType.x25519,
      );
      final wrapped = await _wrap(
        keyBytes,
        me.x25519,
        convId,
        kv,
        d['id'].toString(),
        pub,
      );
      inserts.add({
        'conversation_id': convId,
        'key_version': kv,
        'device_id': d['id'].toString(),
        'wrapped_key': wrapped,
        'sender_device_id': me.deviceId,
      });
    }

    try {
      await _sb.from('e2ee_conversation_keys').insert(inserts);
    } catch (_) {
      // Aynı anda başka cihaz da anahtar üretmiş olabilir: mevcut olanı kullan
      return _myKey(convId, me);
    }
    _keyCache['$convId|$kv'] = keyBytes;
    return _KeyRef(kv, keyBytes);
  }

  // ---------- Şifreleme / çözme ----------

  List<int> _sigInput(List<int> nonce, List<int> ct, List<int> mac, List<int> aad) =>
      utf8.encode(
        '${base64Encode(nonce)}|${base64Encode(ct)}|${base64Encode(mac)}|${utf8.decode(aad)}',
      );

  /// Metni şifreler ve zarfı döndürür. Karşı tarafın E2EE cihazı yoksa null.
  Future<Map<String, dynamic>?> encrypt(String convId, String text) async {
    final me = await E2eeDevice.instance.ensureIdentity();
    final ref = (await _myKey(convId, me)) ?? (await _createKey(convId, me));
    if (ref == null) return null;

    final aad = _aad(convId, ref.kv, me.deviceId);
    final box = await _aead.encrypt(
      utf8.encode(text),
      secretKey: SecretKey(ref.key),
      nonce: _aead.newNonce(),
      aad: aad,
    );
    final sig = await _ed25519.sign(
      _sigInput(box.nonce, box.cipherText, box.mac.bytes, aad),
      keyPair: me.ed25519,
    );

    return {
      'v': _envVersion,
      'kv': ref.kv,
      'sd': me.deviceId,
      'alg': 'xchacha20poly1305',
      'nonce': base64Encode(box.nonce),
      'ct': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
      'sig': base64Encode(sig.bytes),
    };
  }

  /// Zarfı çözer. Başarısızsa (anahtar yok, imza hatalı, bozuk veri) null döner.
  Future<String?> decryptEnvelope(String convId, Map<String, dynamic> enc) async {
    try {
      final me = await E2eeDevice.instance.ensureIdentity();
      final kv = (enc['kv'] as num).toInt();
      final sd = enc['sd'] as String;

      final sender = await _devicePub(sd);
      if (sender == null) return null;
      final key = await _loadKey(convId, kv, me);
      if (key == null) return null;

      final nonce = base64Decode(enc['nonce'] as String);
      final ct = base64Decode(enc['ct'] as String);
      final mac = base64Decode(enc['mac'] as String);
      final aad = _aad(convId, kv, sd);

      final sigOk = await _ed25519.verify(
        _sigInput(nonce, ct, mac, aad),
        signature: Signature(
          base64Decode(enc['sig'] as String),
          publicKey: sender.ed,
        ),
      );
      if (!sigOk) return null;

      final clear = await _aead.decrypt(
        SecretBox(ct, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(key),
        aad: aad,
      );
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  /// Veritabanı satırını Message'a çevirir. Şifreli satırlar çözülür, önbelleğe alınır.
  Future<Message> toMessage(Map<String, dynamic> row) async {
    if (row['enc'] == null) return Message.fromJson(row);
    final id = row['id'].toString();
    final cached = _messageCache[id];
    if (cached != null) return cached;

    final enc = Map<String, dynamic>.from(row['enc'] as Map);
    final text = await decryptEnvelope(row['conversation_id'].toString(), enc);
    final msg = Message.fromJson({
      ...row,
      'content': text ?? '',
      'decrypt_failed': text == null,
    });
    if (text != null) _messageCache[id] = msg;
    return msg;
  }

  /// Son mesaj önizlemesi gibi düz satırlar için: içeriği çözülmüş haliyle döndürür.
  Future<Map<String, dynamic>> decryptedRow(Map<String, dynamic> row) async {
    if (row['enc'] == null) return row;
    final m = await toMessage(row);
    return {
      ...row,
      'content': m.content ?? '',
      'decrypt_failed': m.decryptFailed,
    };
  }
}

class _KeyRef {
  final int kv;
  final List<int> key;
  _KeyRef(this.kv, this.key);
}
