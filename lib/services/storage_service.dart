// lib/services/storage_service.dart
// Supabase Storage yardımcıları.
//  - Sohbet medyası (düz, şifresiz): uploadChatMedia. GIF, grup fotoğrafı gibi
//    şifrelenmeyen dosyalar için kullanılır. Şifreli medya için E2eeMedia kullanılır.
//  - Profil fotoğrafı: uploadAvatar (avatars bucket, herkese açık).
//  - Başarısızlık durumunda null döner (çağıran taraf kendi hata mesajını gösterir).

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  StorageService();

  static const String chatBucket = 'chat-media';
  static const String avatarBucket = 'avatars';

  /// Chat medyası için en fazla boyut (bayt). Üstü reddedilir.
  static const int maxChatMediaBytes = 25 * 1024 * 1024;

  final SupabaseClient _client = Supabase.instance.client;

  /// Profil fotoğrafını 'avatars' bucket'ına yükler ve herkese açık URL döndürür.
  Future<String?> uploadAvatar(File file, String userId) async {
    try {
      final ext = _extensionOf(file.path).isEmpty
          ? 'jpg'
          : _extensionOf(file.path);
      final path =
          '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await _client.storage.from(avatarBucket).upload(
            path,
            file,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _mimeFor(ext),
            ),
          );
      return _client.storage.from(avatarBucket).getPublicUrl(path);
    } catch (e) {
      debugPrint('Avatar yükleme hatası: $e');
      return null;
    }
  }

  /// Dosyayı sohbet klasörüne yükler. Dönüş: storage yolu, hata varsa null.
  /// Yol biçimi: <conversationId>/<type>/<rastgele>.<uzantı>
  Future<String?> uploadChatMedia({
    required File file,
    required String conversationId,
    required String type,
  }) async {
    try {
      final size = await file.length();
      if (size > maxChatMediaBytes) {
        debugPrint('Medya çok büyük: $size bayt');
        return null;
      }

      final ext = _extensionOf(file.path);
      final path =
          '$conversationId/$type/${_randomId()}${ext.isEmpty ? '' : '.$ext'}';

      await _client.storage.from(chatBucket).upload(
            path,
            file,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _mimeFor(ext),
            ),
          );
      return path;
    } on StorageException catch (e) {
      debugPrint('Storage hatası: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Yükleme hatası: $e');
      return null;
    }
  }

  /// Storage yolundan geçici (1 saat geçerli) erişim bağlantısı üretir.
  Future<String?> signedUrl(String path, {int seconds = 3600}) async {
    try {
      return await _client.storage
          .from(chatBucket)
          .createSignedUrl(path, seconds);
    } catch (e) {
      debugPrint('İmzalı URL hatası: $e');
      return null;
    }
  }

  /// Dosyayı storage'dan siler. Başarılıysa true.
  Future<bool> deleteChatMedia(String path) async {
    try {
      await _client.storage.from(chatBucket).remove([path]);
      return true;
    } catch (e) {
      debugPrint('Silme hatası: $e');
      return false;
    }
  }

  // ---------- yardımcılar ----------

  String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  String _mimeFor(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'm4a':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'ogg':
        return 'audio/ogg';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  String _randomId() {
    final rnd = Random.secure();
    return List<int>.generate(12, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
