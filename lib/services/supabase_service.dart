import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/profile.dart';
import '../models/message.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // Typing kanallarını takip etmek için
  final Map<String, RealtimeChannel> _typingChannels = {};

  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ==========================================
  // AUTH (KİMLİK DOĞRULAMA)
  // ==========================================
  Future<AuthResponse> signInWithEmail(String email, String password) async {
    return await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<AuthResponse> signUpWithEmail(
      String email, String password, String username) async {
    return await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'username': username.trim(),
        'full_name': username.trim(),
      },
    );
  }

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(OAuthProvider.google);
  }

  Future<void> signInWithGithub() async {
    await _client.auth.signInWithOAuth(OAuthProvider.github);
  }

  Future<void> signOut() async {
    for (var channel in _typingChannels.values) {
      await channel.unsubscribe();
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
  // PROFİL
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
      print('Profil yükleme hatası: $e');
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
      print('Kullanıcı profili yükleme hatası: $e');
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

  Future<List<Profile>> searchUsers(String query) async {
    if (currentUser == null) return [];
    if (query.trim().length < AppConstants.searchMinLength) return [];

    try {
      final data = await _client
          .from(AppConstants.tableProfiles)
          .select()
          .ilike('username', '%${query.trim()}%')
          .neq('id', currentUser!.id)
          .limit(AppConstants.userSearchLimit);
      return (data as List).map((e) => Profile.fromJson(e)).toList();
    } catch (e) {
      print('Kullanıcı arama hatası: $e');
      return [];
    }
  }

  // ==========================================
  // SOHBETLER
  // ==========================================
  Future<List<Map<String, dynamic>>> getMyConversationsWithUnread() async {
    if (currentUser == null) return [];

    try {
      final memberRows = await _client
          .from(AppConstants.tableConversationMembers)
          .select('conversation_id')
          .eq('user_id', currentUser!.id);

      final conversationIds =
          memberRows.map((e) => e['conversation_id']).toList();
      if (conversationIds.isEmpty) return [];

      final List<Map<String, dynamic>> result = [];

      for (var convId in conversationIds) {
        final otherMemberData = await _client
            .from(AppConstants.tableConversationMembers)
            .select(
                'user_id, profiles(id, username, full_name, avatar_url, status, show_online_status, show_last_seen)')
            .eq('conversation_id', convId)
            .neq('user_id', currentUser!.id)
            .limit(1)
            .maybeSingle();

        final lastMsgData = await _client
            .from(AppConstants.tableMessages)
            .select('content, created_at, sender_id, type')
            .eq('conversation_id', convId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        int unreadCount = 0;
        if (lastMsgData != null &&
            lastMsgData['sender_id'] != currentUser!.id) {
          final readData = await _client
              .from(AppConstants.tableMessageReads)
              .select('id')
              .eq('conversation_id', convId)
              .eq('user_id', currentUser!.id)
              .maybeSingle();
          if (readData == null) unreadCount = 1;
        }

        result.add({
          'conversation_id': convId,
          'other_user': otherMemberData?['profiles'],
          'last_message': lastMsgData,
          'unread_count': unreadCount,
        });
      }

      result.sort((a, b) {
        final aDate = a['last_message']?['created_at'] ?? '2000-01-01';
        final bDate = b['last_message']?['created_at'] ?? '2000-01-01';
        return bDate.toString().compareTo(aDate.toString());
      });

      return result;
    } catch (e) {
      print('Sohbetleri çekme hatası: $e');
      return [];
    }
  }

  Future<String> createConversation(String otherUserId) async {
    if (currentUser == null) throw Exception('Kullanıcı giriş yapmamış');

    final convResponse = await _client
        .from(AppConstants.tableConversations)
        .insert({'type': 'direct', 'created_by': currentUser!.id})
        .select('id')
        .single();

    final convId = convResponse['id'];

    await _client.from(AppConstants.tableConversationMembers).insert([
      {'conversation_id': convId, 'user_id': currentUser!.id},
      {'conversation_id': convId, 'user_id': otherUserId},
    ]);

    return convId;
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
          .limit(AppConstants.messageFetchLimit);
      final list = (data as List).map((e) => Message.fromJson(e)).toList();
      return list.reversed.toList();
    } catch (e) {
      print('Mesajları çekme hatası: $e');
      return [];
    }
  }

  Stream<List<Message>> streamMessages(String conversationId) {
    return _client
        .from(AppConstants.tableMessages)
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map((data) => data.map((json) => Message.fromJson(json)).toList());
  }

  Future<void> sendMessage(String conversationId, String content) async {
    if (currentUser == null) throw Exception('Giriş yapmalısınız');
    if (content.trim().isEmpty) throw Exception('Boş mesaj gönderilemez');
    if (content.length > AppConstants.messageMaxLength) {
      throw Exception('Mesaj çok uzun');
    }

    await _client.from(AppConstants.tableMessages).insert({
      'conversation_id': conversationId,
      'sender_id': currentUser!.id,
      'content': content.trim(),
      'type': 'text',
    });

    try {
      await _client.from(AppConstants.tableConversations).update({
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', conversationId);
    } catch (e) {
      print('Sohbet güncelleme hatası: $e');
    }
  }

  // ==========================================
  // OKUNDU BİLGİSİ
  // ==========================================
  Future<void> markMessageAsRead(
      String messageId, String conversationId) async {
    if (currentUser == null) return;
    try {
      await _client.from(AppConstants.tableMessageReads).upsert({
        'message_id': messageId,
        'conversation_id': conversationId,
        'user_id': currentUser!.id,
        'read_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Okundu işaretleme hatası: $e');
    }
  }

  Future<bool> isMessageRead(String messageId) async {
    try {
      final data = await _client
          .from(AppConstants.tableMessageReads)
          .select('id')
          .eq('message_id', messageId)
          .maybeSingle();
      return data != null;
    } catch (e) {
      return false;
    }
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

  // ✅ DÜZELTME: 'broadcast' string yerine RealtimeListenTypes.broadcast enum
  Future<void> sendTypingEvent(String conversationId, String username) async {
    if (currentUser == null) return;

    final channelName = 'typing-$conversationId';

    if (!_typingChannels.containsKey(channelName)) {
      _typingChannels[channelName] = _client.channel(channelName);
      await _typingChannels[channelName]!.subscribe();
    }

    try {
      await _typingChannels[channelName]!.send(
        type: RealtimeListenTypes.broadcast, // ✅ Enum kullanımı
        event: 'typing',
        payload: {
          'user_id': currentUser!.id,
          'username': username,
        },
      );
    } catch (e) {
      print('Typing event gönderme hatası: $e');
    }
  }

  Future<void> unsubscribeTyping(String conversationId) async {
    final channelName = 'typing-$conversationId';
    final channel = _typingChannels.remove(channelName);
    if (channel != null) {
      await channel.unsubscribe();
    }
  }
}
