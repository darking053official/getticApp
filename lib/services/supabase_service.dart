// lib/services/supabase_service.dart
// (.txt olarak verildi. Projeye eklerken adını supabase_service.dart yapın.)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/profile.dart';
import '../models/message.dart';
import 'e2ee_chat.dart';
import 'e2ee_media.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;
  final Map<String, RealtimeChannel> _typingChannels = {};

  // ==========================================
  // GETTERS
  // ==========================================
  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ==========================================
  // AUTH (KİMLİK DOĞRULAMA)
  // ==========================================
  Future<AuthResponse> signInWithEmail(String email, String password,
      {String? captchaToken}) async {
    return await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
      captchaToken: captchaToken,
    );
  }

  Future<AuthResponse> signUpWithEmail(
      String email, String password, String username,
      {String? captchaToken}) async {
    return await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'username': username.trim(), 'full_name': username.trim()},
      captchaToken: captchaToken,
    );
  }

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(OAuthProvider.google);
  }

  Future<void> signInWithGithub() async {
    await _client.auth.signInWithOAuth(OAuthProvider.github);
  }

  Future<void> signOut() async {
    await setPresence(false);
    for (var c in _typingChannels.values) {
      await c.unsubscribe();
    }
    _typingChannels.clear();
    await _client.auth.signOut();
  }

  Future<void> deleteAccount() async {
    try {
      await _client.rpc('delete_own_account');
    } catch (e) {
      print('Hesap silme RPC hatası: $e');
    }
    await _client.auth.signOut();
  }

  // ==========================================
  // PROFİL & GİZLİLİK
  // ==========================================
  Future<Profile?> getMyProfile() async {
    if (currentUser == null) return null;
    try {
      final data = await _client
          .from(AppConstants.tableProfiles)
          .select()
          .eq('id', currentUser!.id)
          .maybeSingle();
      if (data == null) return null;
      return Profile.fromJson(data);
    } catch (e) {
      print('Profil hatası: $e');
      return null;
    }
  }

  Future<Profile?> getProfile(String userId) async {
    try {
      final data = await _client
          .from(AppConstants.tableProfiles)
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return null;
      return Profile.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  Future<void> updateProfile(String userId, Map<String, dynamic> updates) async {
    await _client
        .from(AppConstants.tableProfiles)
        .update(updates)
        .eq('id', userId);
  }

  Future<void> updatePrivacySettings({
    required bool showOnline,
    required bool showLastSeen,
  }) async {
    if (currentUser == null) return;
    await _client.from(AppConstants.tableProfiles).update({
      'show_online_status': showOnline,
      'show_last_seen': showLastSeen,
    }).eq('id', currentUser!.id);
  }

  /// Çevrimiçi durumu. Ön planda true, arka planda false.
  Future<void> setPresence(bool online) async {
    final me = currentUser?.id;
    if (me == null) return;
    try {
      await _client.from(AppConstants.tableProfiles).update({
        'status': online ? 'online' : 'offline',
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', me);
    } catch (_) {}
  }

  Future<List<Profile>> searchUsers(String query) async {
    if (currentUser == null) return [];
    if (query.trim().length < 2) return [];
    try {
      final data = await _client
          .from(AppConstants.tableProfiles)
          .select()
          .ilike('username', '%${query.trim()}%')
          .neq('id', currentUser!.id)
          .limit(20);
      return (data as List).map((e) => Profile.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  // ==========================================
  // SOHBETLER
  // ==========================================
  /// Sohbet listesi: tek RPC çağrısı (chat_list_summary). Son mesajlar şifreliyse çözülür.
  Future<List<Map<String, dynamic>>> getMyConversationsWithUnread() async {
    final me = currentUser?.id;
    if (me == null) return [];
    try {
      final data = await _client.rpc('chat_list_summary');
      final list = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      await Future.wait(list.map((row) async {
        final last = row['last_message'];
        if (last is Map && last['enc'] != null) {
          row['last_message'] = await E2eeChat.instance
              .decryptedRow(Map<String, dynamic>.from(last));
        }
      }));

      list.sort((a, b) {
        final aDate = a['last_message']?['created_at'] ?? '2000-01-01';
        final bDate = b['last_message']?['created_at'] ?? '2000-01-01';
        return bDate.toString().compareTo(aDate.toString());
      });
      return list;
    } catch (e) {
      print('Sohbet listesi hatası: $e');
      return [];
    }
  }

  /// İki kişi arasında var olan birebir sohbeti bulur (yoksa null).
  Future<String?> findDirectConversation(String otherUserId) async {
    final me = currentUser?.id;
    if (me == null) return null;
    final mine = await _client
        .from(AppConstants.tableConversationMembers)
        .select('conversation_id')
        .eq('user_id', me);
    final myIds = mine.map((e) => e['conversation_id'].toString()).toList();
    if (myIds.isEmpty) return null;

    final shared = await _client
        .from(AppConstants.tableConversationMembers)
        .select('conversation_id')
        .eq('user_id', otherUserId)
        .inFilter('conversation_id', myIds);

    for (final row in shared) {
      final id = row['conversation_id'].toString();
      final conv = await _client
          .from(AppConstants.tableConversations)
          .select('type')
          .eq('id', id)
          .maybeSingle();
      if (conv?['type'] == 'direct') return id;
    }
    return null;
  }

  Future<String> createConversation(String otherUserId) async {
    if (currentUser == null) throw Exception('Giriş yapmalısınız');

    final existing = await findDirectConversation(otherUserId);
    if (existing != null) return existing;

    final conv = await _client
        .from(AppConstants.tableConversations)
        .insert({'type': 'direct', 'created_by': currentUser!.id})
        .select('id')
        .single();

    final convId = conv['id'];

    await _client.from(AppConstants.tableConversationMembers).insert([
      {'conversation_id': convId, 'user_id': currentUser!.id},
      {'conversation_id': convId, 'user_id': otherUserId},
    ]);

    return convId;
  }

  Future<String> createGroupConversation({
    required String groupName,
    required List<String> memberIds,
  }) async {
    if (currentUser == null) throw Exception('Giriş yapmalısınız');

    final conv = await _client
        .from(AppConstants.tableConversations)
        .insert({
          'type': 'group',
          'name': groupName,
          'created_by': currentUser!.id
        })
        .select('id')
        .single();

    final convId = conv['id'];

    final List<Map<String, dynamic>> inserts = [
      {'conversation_id': convId, 'user_id': currentUser!.id},
      ...memberIds.map((uid) => {'conversation_id': convId, 'user_id': uid}),
    ];

    await _client.from(AppConstants.tableConversationMembers).insert(inserts);

    return convId;
  }

  Future<void> deleteConversation(String conversationId) async {
    if (currentUser == null) return;
    try {
      await _client
          .from(AppConstants.tableMessages)
          .delete()
          .eq('conversation_id', conversationId);
      await _client
          .from(AppConstants.tableConversationMembers)
          .delete()
          .eq('conversation_id', conversationId);
      await _client
          .from(AppConstants.tableConversations)
          .delete()
          .eq('id', conversationId);
    } catch (e) {
      print('Sohbet silme hatası: $e');
      rethrow;
    }
  }

  /// Sohbeti okundu olarak işaretler. Zaman sunucuda yazılır (cihaz saatinden bağımsız).
  Future<void> markConversationRead(String conversationId) async {
    final me = currentUser?.id;
    if (me == null) return;
    try {
      await _client.rpc('mark_conversation_read',
          params: {'p_conv': conversationId});
    } catch (e) {
      print('Okundu işaretlenemedi: $e');
    }
  }

  /// Karşı tarafın son okuma zamanı. Mesajın görüldü durumu buna göre hesaplanır.
  Future<DateTime?> getOtherReadAt(String conversationId) async {
    final me = currentUser?.id;
    if (me == null) return null;
    final row = await _client
        .from(AppConstants.tableConversationMembers)
        .select('last_read_at')
        .eq('conversation_id', conversationId)
        .neq('user_id', me)
        .maybeSingle();
    final v = row?['last_read_at'];
    return v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
  }

  // ==========================================
  // GRUP YÖNETİMİ
  // ==========================================
  Future<List<Profile>> getGroupMembers(String conversationId) async {
    try {
      final data = await _client
          .from(AppConstants.tableConversationMembers)
          .select('user_id, profiles(*)')
          .eq('conversation_id', conversationId);

      return (data as List)
          .where((e) => e['profiles'] != null)
          .map((e) => Profile.fromJson(e['profiles']))
          .toList();
    } catch (e) {
      print('Grup üyeleri çekilemedi: $e');
      return [];
    }
  }

  Future<void> updateGroupName(String conversationId, String newName) async {
    await _client
        .from(AppConstants.tableConversations)
        .update({'name': newName})
        .eq('id', conversationId);
  }

  Future<void> removeGroupMember(String conversationId, String userId) async {
    await _client
        .from(AppConstants.tableConversationMembers)
        .delete()
        .eq('conversation_id', conversationId)
        .eq('user_id', userId);
    // Çıkarılan kişi yeni anahtarı alamasın: hemen yeni sürüm üret
    unawaited(E2eeChat.instance.rotateIfNeeded(conversationId));
  }

  Future<void> addGroupMembers(String conversationId, List<String> userIds) async {
    final List<Map<String, dynamic>> inserts = userIds
        .map((uid) => {'conversation_id': conversationId, 'user_id': uid})
        .toList();

    await _client.from(AppConstants.tableConversationMembers).insert(inserts);
    // Yeni üyeler yalnızca bu andan sonraki anahtarı alsın
    unawaited(E2eeChat.instance.rotateIfNeeded(conversationId));
  }

  // ==========================================
  // MESAJLAR
  // ==========================================
  Future<List<Message>> getMessages(String conversationId) async {
    try {
      final data = await _client
          .from(AppConstants.tableMessages)
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(50);
      final list = (data as List).map((e) => Message.fromJson(e)).toList();
      return list.reversed.toList();
    } catch (e) {
      print('Mesaj çekme hatası: $e');
      return [];
    }
  }

  Stream<List<Message>> streamMessages(String conversationId) {
    return _client
        .from(AppConstants.tableMessages)
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .asyncMap((data) {
          final rows = data.where((j) {
            final e = j['expires_at'];
            if (e == null) return true;
            final t = DateTime.tryParse(e.toString());
            return t == null || t.isAfter(DateTime.now().toUtc());
          }).toList();
          // Şifre çözmeleri paralel çalıştır (sıra korunur)
          return Future.wait(rows.map((j) =>
              E2eeChat.instance.toMessage(Map<String, dynamic>.from(j))));
        });
  }

  /// Metin mesajı gönderir
  Future<void> sendMessage(String conversationId, String content,
      {String? replyToId, bool forwarded = false}) async {
    if (currentUser == null) throw Exception('Giriş yapmalısınız');
    if (content.trim().isEmpty) throw Exception('Boş mesaj gönderilemez');

    final enc = await E2eeChat.instance.encrypt(conversationId, content.trim());

    final inserted = await _client.from(AppConstants.tableMessages).insert({
      'conversation_id': conversationId,
      'sender_id': currentUser!.id,
      'content': enc == null ? content.trim() : null,
      'enc': enc,
      'enc_version': enc == null ? null : 1,
      'type': 'text',
      'forwarded': forwarded,
      if (replyToId != null) 'reply_to': replyToId,
    }).select('id').single();

    _pushMessage(conversationId, inserted['id'].toString());
    _touchConversation(conversationId);
  }

  /// Medya mesajı gönderir (fotoğraf, video, ses, dosya, gif)
  Future<void> sendMediaMessage({
    required String conversationId,
    required String type,
    required String mediaPath,
    String? content,
    String? replyToId,
    bool forwarded = false,
  }) async {
    if (currentUser == null) throw Exception('Giriş yapmalısınız');

    final inserted = await _client.from(AppConstants.tableMessages).insert({
      'conversation_id': conversationId,
      'sender_id': currentUser!.id,
      'content': content?.trim() ?? '',
      'type': type,
      'forwarded': forwarded,
      'media_url': mediaPath,
      if (replyToId != null) 'reply_to': replyToId,
    }).select('id').single();

    _pushMessage(conversationId, inserted['id'].toString());
    _touchConversation(conversationId);
  }

  /// Dosyayı şifreleyip yükler, şifreli medya mesajı olarak gönderir (Aşama 4).
  Future<void> sendEncryptedMedia({
    required String conversationId,
    required String type,
    required File file,
    String? caption,
    String? replyToId,
    String? originalName,
    bool forwarded = false,
  }) async {
    if (currentUser == null) throw Exception('Giriş yapmalısınız');
    final name = originalName ?? file.path.split(Platform.pathSeparator).last;
    final bytes = await file.readAsBytes();

    final up = await E2eeMedia.instance.encryptAndUpload(conversationId, bytes);
    final secret = Map<String, dynamic>.from(up['secret'] as Map)
      ..['type'] = type
      ..['name'] = name;
    final payload = jsonEncode({'t': (caption ?? '').trim(), 'm': secret});

    final enc = await E2eeChat.instance.encrypt(conversationId, payload);
    if (enc == null) {
      throw Exception('Karşı tarafın şifreli cihazı yok, medya gönderilemedi');
    }

    final inserted = await _client.from(AppConstants.tableMessages).insert({
      'conversation_id': conversationId,
      'sender_id': currentUser!.id,
      'content': null,
      'enc': enc,
      'enc_version': 1,
      'type': type,
      'media_url': up['path'],
      'forwarded': forwarded,
      if (replyToId != null) 'reply_to': replyToId,
    }).select('id').single();

    _pushMessage(conversationId, inserted['id'].toString());
    _touchConversation(conversationId);
  }

  // ==========================================
  // PARTİ 1: TEPKİLER, SABİTLEME, İLETME
  // ==========================================

  /// Verilen mesajların tepkilerini getirir: message_id, user_id, emoji.
  Future<List<Map<String, dynamic>>> getReactions(List<String> messageIds) async {
    if (messageIds.isEmpty) return [];
    try {
      final data = await _client
          .from('message_reactions')
          .select('message_id, user_id, emoji')
          .inFilter('message_id', messageIds);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      print('Tepki çekme hatası: $e');
      return [];
    }
  }

  /// Tepkiyi açar/kapatır. Zaten verdiysem geri alır.
  Future<void> toggleReaction(String messageId, String emoji) async {
    final me = currentUser?.id;
    if (me == null) return;
    final existing = await _client
        .from('message_reactions')
        .select('message_id')
        .eq('message_id', messageId)
        .eq('user_id', me)
        .eq('emoji', emoji)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from('message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', me)
          .eq('emoji', emoji);
    } else {
      await _client.from('message_reactions').insert({
        'message_id': messageId,
        'user_id': me,
        'emoji': emoji,
      });
    }
  }

  /// Sohbetin sabitlenen mesajının id'si (yoksa null).
  Future<String?> getPinnedMessageId(String conversationId) async {
    final row = await _client
        .from(AppConstants.tableConversations)
        .select('pinned_message_id')
        .eq('id', conversationId)
        .maybeSingle();
    return row?['pinned_message_id']?.toString();
  }

  /// Sabitlenen mesajı ayarlar. null verilirse sabitleme kaldırılır.
  Future<void> setPinnedMessage(String conversationId, String? messageId) async {
    await _client
        .from(AppConstants.tableConversations)
        .update({'pinned_message_id': messageId})
        .eq('id', conversationId);
  }

  /// Mesajı başka bir sohbete iletir. İletildi işaretlenir.
  Future<void> forwardMessage(String targetConversationId, Message m) async {
    // Şifreli medya: indir, çöz, hedef sohbet için yeniden şifreleyip yükle
    if (m.mediaSecret != null && m.mediaUrl != null) {
      final name = (m.mediaSecret!['name'] ?? '').toString();
      final local = await E2eeMedia.instance.localPath(
        convId: m.conversationId,
        storagePath: m.mediaUrl!,
        secret: m.mediaSecret!,
        fileName: name,
      );
      await sendEncryptedMedia(
        conversationId: targetConversationId,
        type: m.type,
        file: File(local),
        caption: m.content,
        originalName: name.isEmpty ? null : name,
        forwarded: true,
      );
      return;
    }
    if (m.type == 'text') {
      await sendMessage(targetConversationId, m.content ?? '', forwarded: true);
    } else {
      await sendMediaMessage(
        conversationId: targetConversationId,
        type: m.type,
        mediaPath: m.mediaUrl ?? '',
        content: m.content,
        forwarded: true,
      );
    }
  }

  // ==========================================
  // PARTİ 2: SESSİZE ALMA, KAYBOLAN MESAJLAR, BAĞLANTI ÖNİZLEMESİ
  // ==========================================

  Future<void> setMuted(String conversationId, bool muted) async {
    final me = currentUser?.id;
    if (me == null) return;
    await _client
        .from(AppConstants.tableConversationMembers)
        .update({'muted': muted})
        .eq('conversation_id', conversationId)
        .eq('user_id', me);
  }

  Future<bool> getMuted(String conversationId) async {
    final me = currentUser?.id;
    if (me == null) return false;
    final row = await _client
        .from(AppConstants.tableConversationMembers)
        .select('muted')
        .eq('conversation_id', conversationId)
        .eq('user_id', me)
        .maybeSingle();
    return row?['muted'] == true;
  }

  /// Kaybolan mesaj süresi (saniye). null = kapalı.
  Future<int?> getDisappearing(String conversationId) async {
    final row = await _client
        .from(AppConstants.tableConversations)
        .select('disappear_seconds')
        .eq('id', conversationId)
        .maybeSingle();
    final v = row?['disappear_seconds'];
    return v == null ? null : (v as num).toInt();
  }

  Future<void> setDisappearing(String conversationId, int? seconds) async {
    await _client
        .from(AppConstants.tableConversations)
        .update({'disappear_seconds': seconds})
        .eq('id', conversationId);
  }

  /// Bağlantının başlık, açıklama ve görselini getirir (link-preview fonksiyonu).
  Future<Map<String, dynamic>?> linkPreview(String url) async {
    try {
      final res = await _client.functions.invoke('link-preview', body: {'url': url});
      final d = res.data;
      if (d is Map && d['error'] == null) return Map<String, dynamic>.from(d);
      return null;
    } catch (_) {
      return null;
    }
  }

  // ==========================================
  // PARTİ 3: YÖNETİCİ DEVRİ, GRUPTAN AYRILMA, GRUP FOTOĞRAFI
  // ==========================================

  /// Grup bilgisi: ad, yönetici (created_by) ve fotoğraf yolu.
  Future<Map<String, dynamic>?> getGroupInfo(String conversationId) async {
    return await _client
        .from(AppConstants.tableConversations)
        .select('name, created_by, group_avatar_url')
        .eq('id', conversationId)
        .maybeSingle();
  }

  /// Yöneticiliği başka bir üyeye devreder (yalnızca yönetici yapabilir).
  Future<void> transferGroupAdmin(String conversationId, String newAdminId) async {
    await _client.rpc('transfer_group_admin',
        params: {'p_conv': conversationId, 'p_new': newAdminId});
  }

  /// Gruptan ayrılır. Yönetici ayrılırsa yetki en eski üyeye geçer.
  Future<void> leaveGroupRpc(String conversationId) async {
    await _client.rpc('leave_group', params: {'p_conv': conversationId});
  }

  /// Grup fotoğrafı yolunu kaydeder (yalnızca yönetici).
  Future<void> setGroupAvatar(String conversationId, String storagePath) async {
    await _client.rpc('set_group_avatar',
        params: {'p_conv': conversationId, 'p_path': storagePath});
  }

  /// Alıcılara OneSignal push gönderir (uygulama kapalıyken de bildirim gelsin).
  void _pushMessage(String conversationId, String messageId) {
    _client.functions.invoke('message-push', body: {
      'conversationId': conversationId,
      'messageId': messageId,
    }).then((_) {}, onError: (e) => print('Push hatası: $e'));
  }

  void _touchConversation(String conversationId) {
    _client
        .from(AppConstants.tableConversations)
        .update({'updated_at': DateTime.now().toIso8601String()})
        .eq('id', conversationId)
        .then((_) {}, onError: (e) => print('Sohbet güncelleme hatası: $e'));
  }

  Future<void> deleteMessage(String messageId) async {
    if (currentUser == null) return;
    await _client.from(AppConstants.tableMessages).update({
      'is_deleted': true,
      'content': null,
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', messageId);
  }

  Future<void> editMessage(String messageId, String newContent) async {
    if (currentUser == null) return;
    if (newContent.trim().isEmpty) throw Exception('Bo\u015f mesaj olamaz');
    final row = await _client
        .from(AppConstants.tableMessages)
        .select('conversation_id, enc_version')
        .eq('id', messageId)
        .maybeSingle();
    if (row != null && row['enc_version'] != null) {
      final enc = await E2eeChat.instance
          .encrypt(row['conversation_id'].toString(), newContent.trim());
      if (enc != null) {
        await _client.from(AppConstants.tableMessages).update({
          'enc': enc,
          'enc_version': 1,
          'content': null,
          'is_edited': true,
          'edited_at': DateTime.now().toIso8601String(),
        }).eq('id', messageId);
        return;
      }
    }
    await _client.from(AppConstants.tableMessages).update({
      'content': newContent.trim(),
      'is_edited': true,
      'edited_at': DateTime.now().toIso8601String(),
    }).eq('id', messageId);
  }

  // ==========================================
  // TYPING INDICATOR (YAZIYOR GÖSTERGESİ)
  // ==========================================
  RealtimeChannel subscribeToTyping(
    String conversationId,
    void Function(String username) onTyping,
  ) {
    final channelName = 'typing-$conversationId';
    if (_typingChannels.containsKey(channelName)) {
      _typingChannels[channelName]?.unsubscribe();
      _typingChannels.remove(channelName);
    }
    final channel = _client.channel(channelName);
    channel.onBroadcast(
      event: 'typing',
      callback: (payload) {
        if (payload['user_id'] != currentUser?.id) {
          onTyping(payload['username'] as String? ?? 'Biri');
        }
      },
    ).subscribe();
    _typingChannels[channelName] = channel;
    return channel;
  }

  Future<void> sendTypingEvent(String conversationId, String username) async {
    if (currentUser == null) return;
    final channelName = 'typing-$conversationId';
    if (!_typingChannels.containsKey(channelName)) {
      _typingChannels[channelName] = _client.channel(channelName);
      await _typingChannels[channelName]!.subscribe();
    }
    try {
      await _typingChannels[channelName]!.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': currentUser!.id, 'username': username},
      );
    } catch (e) {
      print('Typing hatası: $e');
    }
  }

  Future<void> unsubscribeTyping(String conversationId) async {
    final channelName = 'typing-$conversationId';
    final channel = _typingChannels.remove(channelName);
    if (channel != null) await channel.unsubscribe();
  }
}
