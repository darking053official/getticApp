import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mime/mime.dart';
import '../core/constants.dart';

class StorageService {
  final SupabaseClient _client = Supabase.instance.client;

  // ==========================================
  // AVATAR İŞLEMLERİ
  // ==========================================

  /// Avatar yükler ve public URL döner
  Future<String?> uploadAvatar(File file, String userId) async {
    try {
      final fileExt = file.path.split('.').last.toLowerCase();
      final fileName = '$userId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'avatars/$fileName';

      await _client.storage
          .from(AppConstants.bucketAvatars)
          .upload(filePath, file);

      return _client.storage
          .from(AppConstants.bucketAvatars)
          .getPublicUrl(filePath);
    } catch (e) {
      print('Avatar yükleme hatası: $e');
      return null;
    }
  }

  /// Avatar siler
  Future<void> deleteAvatar(String avatarUrl) async {
    try {
      final uri = Uri.parse(avatarUrl);
      final path = uri.pathSegments.skip(1).join('/');
      await _client.storage.from(AppConstants.bucketAvatars).remove([path]);
    } catch (e) {
      print('Avatar silme hatası: $e');
    }
  }

  // ==========================================
  // SOHBET MEDYASI (YENİ)
  // ==========================================

  /// Sohbet medyasını (fotoğraf, video, ses, dosya) Supabase Storage'a yükler.
  /// Dosya yolu döner (bucket içindeki path).
  Future<String?> uploadChatMedia({
    required File file,
    required String conversationId,
    required String type, // 'image', 'video', 'audio', 'file'
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Giriş yapmamış');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = file.path.split('.').last.toLowerCase();
      final fileName = '${userId}_${timestamp}.$ext';
      final path = 'chats/$conversationId/$fileName';

      // MIME type'ı belirle
      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';

      await _client.storage.from(AppConstants.bucketChatMedia).upload(
        path,
        file,
        fileOptions: FileOptions(contentType: mimeType),
      );

      return path;
    } catch (e) {
      print('Medya yükleme hatası: $e');
      return null;
    }
  }

  /// Özel (private) dosya için geçici signed URL oluşturur.
  /// Varsayılan süre 1 saattir.
  Future<String?> getSignedUrl(String path, {int expiresInSeconds = 3600}) async {
    try {
      return await _client.storage
          .from(AppConstants.bucketChatMedia)
          .createSignedUrl(path, expiresInSeconds);
    } catch (e) {
      print('Signed URL hatası: $e');
      return null;
    }
  }

  /// Sohbet medyasını siler
  Future<void> deleteChatMedia(String path) async {
    try {
      await _client.storage.from(AppConstants.bucketChatMedia).remove([path]);
    } catch (e) {
      print('Medya silme hatası: $e');
    }
  }
}
