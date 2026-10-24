import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import '../models/message.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ==========================================
  // AUTH (KİMLİK DOĞRULAMA)
  // ==========================================
  
  // main.dart ve auth_page.dart ile uyumlu isimlendirme
  Future<AuthResponse> signInWithEmail(String email, String password) async {
    return await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUpWithEmail(String email, String password, String username) async {
    return await _client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username, 'full_name': username},
    );
  }

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(OAuthProvider.google);
  }

  Future<void> signInWithGithub() async {
    await _client.auth.signInWithOAuth(OAuthProvider.github);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<void> deleteAccount() async {
    try {
      await _client.rpc('delete_own_account');
    } catch (e) {
      print('Hesap silme RPC hatası (RPC yoksa manuel silinecek): $e');
    }
    await _client.auth.signOut();
  }

  // ==========================================
  // PROFİL & GİZLİLİK
  // ==========================================
  Future<Profile?> getMyProfile() async {
    if (currentUser == null) return null;
    final data = await _client.from('profiles').select().eq('id', currentUser!.id).single();
    return Profile.fromJson(data);
  }

  Future<Profile?> getProfile(String userId) async {
    final data = await _client.from('profiles').select().eq('id', userId).maybeSingle();
    if (data == null) return null;
    return Profile.fromJson(data);
  }

  Future<void> updateProfile(String userId, Map<String, dynamic> updates) async {
    await _client.from('profiles').update(updates).eq('id', userId);
  }

  Future<void> updatePrivacySettings({required bool showOnline, required bool showLastSeen}) async {
    if (currentUser == null) return;
    await _client.from('profiles').update({
      'show_online_status': showOnline,
      'show_last_seen': showLastSeen,
    }).eq('id', currentUser!.id);
  }

  Future<List<Profile>> searchUsers(String query) async {
    if (query.trim().length < 2) return [];
    final data = await _client.from('profiles').select()
        .ilike('username', '%${query.trim()}%')
        .neq('id', currentUser!.id)
        .limit(20);
    return (data as List).map((e) => Profile.fromJson(e)).toList();
  }

  // ==========================================
  // SOHBETLER (CONVERSATIONS)
  // ==========================================
  
  // chat_list_page.dart'ın beklediği fonksiyon.
  // Sizin detaylı join yapınızı kullanıp, sayfanın anlayacağı formata çeviriyor.
  Future<List<Map<String, dynamic>>> getMyConversationsWithUnread() async {
    if (currentUser == null) return [];
    
    try {
      // Sizin yazdığınız detaylı join sorgusu
      final data = await _client.from('conversation_members').select('''
        conversation_id,
        conversations(
          id, type, name, updated_at,
          conversation_members(
            user_id,
            profiles(id, username, full_name, avatar_url, status, show_online_status)
          )
        )
      ''').eq('user_id', currentUser!.id);

      final List<Map<String, dynamic>> result = [];

      for (var row in data) {
        final conv = row['conversations'];
        if (conv == null) continue;

        // Karşı tarafı bul
        final members = conv['conversation_members'] as List;
        Map<String, dynamic>? otherUser;
        
        for (var m in members) {
          if (m['user_id'] != currentUser!.id) {
            otherUser = m['profiles'];
            break;
          }
        }

        // Son mesajı al
        final lastMsgData = await _client
            .from('messages')
            .select('content, created_at, sender_id')
            .eq('conversation_id', conv['id'])
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        // Okunmamış sayısını al (Şimdilik basit bir hesaplama, geliştirilebilir)
        int unreadCount = 0;
        if (lastMsgData != null && lastMsgData['sender_id'] != currentUser!.id) {
           // Gerçek okunmamış sayısı için message_reads tablosuyla join yapılmalı
           unreadCount = 1; 
        }

        result.add({
          'conversation_id': conv['id'],
          'other_user': otherUser,
          'last_message': lastMsgData,
          'unread_count': unreadCount,
        });
      }

      // Son mesaj tarihine göre sırala (En yeni en üstte)
      result.sort((a, b) {
        final aDate = a['last_message']?['created_at'] ?? '2000-01-01';
        final bDate = b['last_message']?['created_at'] ?? '2000-01-01';
        return bDate.compareTo(aDate);
      });

      return result;
    } catch (e) {
      print("Sohbetleri çekme hatası: $e");
      return [];
    }
  }

  Future<String> createConversation(String otherUserId) async {
    final myId = currentUser!.id;
    final newConv = await _client.from('conversations').insert({
      'type': 'direct', 
      'created_by': myId
    }).select('id').single();
    
    final convId = newConv['id'];
    
    await _client.from('conversation_members').insert([
      {'conversation_id': convId, 'user_id': myId},
      {'conversation_id': convId, 'user_id': otherUserId},
    ]);
    
    return convId;
  }

  // ==========================================
  // MESAJLAR (MESSAGES)
  // ==========================================
  Future<List<Message>> getMessages(String conversationId) async {
    final data = await _client.from('messages').select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(100);
    return (data as List).map((e) => Message.fromJson(e)).toList();
  }

  Future<void> sendMessage(String conversationId, String content) async {
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': currentUser!.id,
      'content': content,
      'type': 'text',
    });
  }

  // ==========================================
  // OKUNDU BİLGİSİ (READ RECEIPTS)
  // ==========================================
  Future<void> markMessageAsRead(String messageId, String conversationId) async {
    if (currentUser == null) return;
    try {
      await _client.from('message_reads').upsert({
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
      final data = await _client.from('message_reads')
          .select('id')
          .eq('message_id', messageId)
          .maybeSingle();
      return data != null;
    } catch (e) {
      return false;
    }
  }

  // ==========================================
  // YAZIYOR GÖSTERGESİ (TYPING INDICATOR)
  // ==========================================
  
  // Supabase v2 uyumlu Broadcast yapısı
  RealtimeChannel subscribeToTyping(String conversationId, Function(String) onTyping) {
    return _client.channel('typing-$conversationId')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            if (payload['user_id'] != currentUser?.id) {
              onTyping(payload['username'] ?? 'Biri');
            }
          },
        ).subscribe();
  }

  Future<void> sendTypingEvent(String conversationId, String username) async {
    if (currentUser == null) return;
    // BroadcastEventType yerine doğrudan 'broadcast' string'i kullanılıyor
    await _client.channel('typing-$conversationId').send(
      type: RealtimeChannelSendType.broadcast, 
      event: 'typing',
      payload: {'user_id': currentUser!.id, 'username': username},
    );
  }

  // ==========================================
  // REALTIME (ANLIK MESAJ DİNLEME)
  // ==========================================
  
  // chat_room_page.dart'ın beklediği Stream yapısı. 
  // Sizin detaylı PostgresChanges yapınızın daha modern ve Riverpod uyumlu hali.
  Stream<List<Message>> streamMessages(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map((data) => data.map((json) => Message.fromJson(json)).toList());
  }
}
