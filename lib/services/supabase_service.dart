import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import '../models/message.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  // ==========================================
  // AUTH (KİMLİK DOĞRULAMA)
  // ==========================================
  Future<AuthResponse> signIn(String email, String password) async {
    return await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp(String email, String password, String username) async {
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
    await _client.rpc('delete_own_account');
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
  Future<List<Map<String, dynamic>>> getMyConversations() async {
    if (currentUser == null) return [];
    
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

    return List<Map<String, dynamic>>.from(data);
  }

  Future<String> createOrGetDirectConversation(String otherUserId) async {
    final myId = currentUser!.id;
    final newConv = await _client.from('conversations').insert({'type': 'direct', 'created_by': myId}).select('id').single();
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
    await _client.channel('typing-$conversationId').send(
      type: BroadcastEventType.broadcast,
      event: 'typing',
      payload: {'user_id': currentUser!.id, 'username': username},
    );
  }

  // ==========================================
  // REALTIME (ANLIK MESAJ DİNLEME)
  // ==========================================
  RealtimeChannel subscribeToMessages(String conversationId, Function(Message) onNewMessage) {
    return _client.channel('messages-$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: conversationId),
          callback: (payload) => onNewMessage(Message.fromJson(payload.newRecord)),
        ).subscribe();
  }
}
