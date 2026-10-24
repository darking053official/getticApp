import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import '../models/message.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _client = Supabase.instance.client;
  final _messageController = TextEditingController();
  List<Message> _messages = [];
  RealtimeChannel? _channel;
  String _conversationId = 'test-room-1';

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _channel = _client
        .channel('messages-$_conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: _conversationId,
          ),
          callback: (payload) {
            setState(() => _messages.add(Message.fromJson(payload.newRecord)));
          },
        )
        .subscribe();
  }

  Future<void> _loadMessages() async {
    final data = await _client
        .from('messages')
        .select()
        .eq('conversation_id', _conversationId)
        .order('created_at', ascending: true)
        .limit(50);
    setState(() => _messages = (data as List).map((e) => Message.fromJson(e)).toList());
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await _client.from('messages').insert({
      'conversation_id': _conversationId,
      'sender_id': _client.auth.currentUser!.id,
      'content': text,
      'type': 'text',
    });
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = _client.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gettic'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _client.auth.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMine = msg.senderId == myId;
                return Align(
                  alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: isMine ? GetticTheme.accent : GetticTheme.bgTertiary,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMine ? 16 : 4),
                        bottomRight: Radius.circular(isMine ? 4 : 16),
                      ),
                    ),
                    child: Text(msg.content ?? '', style: const TextStyle(color: Colors.white, fontSize: 15)),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: GetticTheme.bgSecondary,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(hintText: 'Mesaj yaz...'),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: GetticTheme.accent),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
