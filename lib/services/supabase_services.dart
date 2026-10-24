import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // Auth
  User? get currentUser => _client.auth.currentUser;
  
  Future<AuthResponse> signIn(String email, String password) async {
    return await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp(String email, String password, String username) async {
    return await _client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // Messages
  Future<List<Message>> getMessages(String conversationId) async {
    final data = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(50);

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

  // Realtime
  RealtimeChannel subscribeToMessages(String conversationId, Function(Message) onNew) {
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
            onNew(Message.fromJson(payload.newRecord));
          },
        )
        .subscribe();
  }
}
