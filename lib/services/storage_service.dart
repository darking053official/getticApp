import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';

class StorageService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Avatar yükler ve public URL döner
  Future<String?> uploadAvatar(File file, String userId) async {
    try {
      final fileExt = file.path.split('.').last;
      final fileName = '$userId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'avatars/$fileName';

      await _client.storage.from(AppConstants.bucketAvatars).upload(filePath, file);

      final publicUrl = _client.storage.from(AppConstants.bucketAvatars).getPublicUrl(filePath);
      return publicUrl;
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
}
