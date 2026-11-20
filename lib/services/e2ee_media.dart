// ============================================================
// lib/services/e2ee_media.dart
// (.txt olarak verildi. Projeye eklerken adını e2ee_media.dart yapın.)
//
// Aşama 4: medya şifrelemesi.
//  - Her dosya için rastgele 32 bayt anahtar ve 24 bayt nonce üretilir.
//  - Dosya XChaCha20-Poly1305 ile şifrelenir, şifreli bayt "chat-media" bucket'ına yüklenir.
//  - Dosya anahtarı, nonce ve mac sohbet anahtarıyla şifrelenen mesaj zarfının içine girer.
//    Sunucu dosya anahtarını bilmez.
//  - Alıcı dosyayı indirir, çözer ve geçici klasöre yazar.
//
// Not: Storage yolu "e2ee/<convId>/<rastgele>.bin" biçimindedir. Bucket yazma izni
// bu yolu kapsamalıdır (kullanıcı kendi sohbetinin klasörüne yükleyebilmeli).
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class E2eeMedia {
  E2eeMedia._();
  static final E2eeMedia instance = E2eeMedia._();

  static const String bucket = 'chat-media';

  final Xchacha20 _aead = Xchacha20.poly1305Aead();

  List<int> _aad(String convId) => utf8.encode('gettic-media|$convId');

  String _randomHex(int bytes) {
    final rnd = Random.secure();
    return List<int>.generate(bytes, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Dosyayı şifreler, yükler ve mesaja konacak sırrı döndürür.
  /// Dönüş: {'path': storageYolu, 'secret': {'k','n','a'}}
  Future<Map<String, dynamic>> encryptAndUpload(
      String convId, Uint8List clear) async {
    final key = await _aead.newSecretKey();
    final keyBytes = await key.extractBytes();
    final nonce = _aead.newNonce();

    final box = await _aead.encrypt(
      clear,
      secretKey: key,
      nonce: nonce,
      aad: _aad(convId),
    );

    final path = 'e2ee/$convId/${_randomHex(16)}.bin';
    await Supabase.instance.client.storage.from(bucket).uploadBinary(
          path,
          Uint8List.fromList(box.cipherText),
          fileOptions: const FileOptions(
            upsert: false,
            contentType: 'application/octet-stream',
          ),
        );

    return {
      'path': path,
      'secret': {
        'k': base64Encode(keyBytes),
        'n': base64Encode(nonce),
        'a': base64Encode(box.mac.bytes),
      },
    };
  }

  /// Şifreli dosyayı indirir, çözer ve geçici klasörde yerel yolunu döndürür.
  /// Aynı dosya ikinci kez istenirse önbellekten verilir.
  Future<String> localPath({
    required String convId,
    required String storagePath,
    required Map<String, dynamic> secret,
    String? fileName,
  }) async {
    final dir = await getTemporaryDirectory();
    final safe = storagePath.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final ext = (fileName != null && fileName.contains('.'))
        ? '.${fileName.split('.').last}'
        : '';
    final file = File('${dir.path}/gettic_media_$safe$ext');
    if (await file.exists()) return file.path;

    final cipher = await Supabase.instance.client.storage
        .from(bucket)
        .download(storagePath);

    final clear = await _aead.decrypt(
      SecretBox(
        cipher,
        nonce: base64Decode(secret['n'] as String),
        mac: Mac(base64Decode(secret['a'] as String)),
      ),
      secretKey: SecretKey(base64Decode(secret['k'] as String)),
      aad: _aad(convId),
    );

    await file.writeAsBytes(clear, flush: true);
    return file.path;
  }
}
