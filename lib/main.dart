import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import '../models/message.dart';
import '../models/conversation.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  // AUTH İŞLEMLERİ
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

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // PROFİL İŞLEMLERİ
  Future<Profile?> getMyProfile() async {
    if (currentUser == null) return null;
    try {
      final data = await _client.from('profiles').select().eq('id', currentUser!.id).single();
      return Profile.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  Future<List<Profile>> searchUsers(String query) async {
    if (query.trim().length < 2) return [];
    try {
      final data = await _client
          .from('profiles')
          .select()
          .ilike('username', '%${query.trim()}%')
          .neq('id', currentUser!.id)
          .limit(20);
      return (data as List).map((e) => Profile.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  // SOHBET İŞLEMLERİ
  Future<List<Conversation>> getMyConversations() async {
    if (currentUser == null) return [];
    try {
      final data = await _client
          .from('conversation_members')
          .select('''
            conversation_id,
            conversations(
              id, type, name, updated_at,
              conversation_members(
                user_id,
                profiles(id, username, full_name, avatar_url, status)
              )
            )
          ''')
          .eq('user_id', currentUser!.id);

      final list = (data as List).map((e) {
        final conv = e['conversations'];
        return Conversation.fromJson(conv, currentUserId: currentUser!.id);
      }).toList();

      // En son güncelleneni en üste al
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (e) {
      return [];
    }
  }

  Future<String> createOrGetDirectConversation(String otherUserId) async {
    // Basitleştirilmiş sohbet oluşturma (Web projesindeki mantığın mobil karşılığı)
    final myId = currentUser!.id;
    
    // 1. Yeni sohbet oluştur
    final newConv = await _client.from('conversations').insert({
      'type': 'direct',
      'created_by': myId,
    }).select('id').single();
    
    final convId = newConv['id'];

    // 2. Üyeleri ekle
    await _client.from('conversation_members').insert([
      {'conversation_id': convId, 'user_id': myId},
      {'conversation_id': convId, 'user_id': otherUserId},
    ]);

    return convId;
  }

  // MESAJ İŞLEMLERİ
  Future<List<Message>> getMessages(String conversationId) async {
    try {
      final data = await _client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true)
          .limit(100);

      return (data as List).map((e) => Message.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> sendMessage(String conversationId, String content) async {
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': currentUser!.id,
      'content': content,
      'type': 'text',
    });
  }

  // REALTIME
  RealtimeChannel subscribeToMessages(String conversationId, Function(Message) onNewMessage) {
    return _client
        .channel('messages-$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            onNewMessage(Message.fromJson(payload.newRecord));
          },
        )
        .subscribe();
  }
}
