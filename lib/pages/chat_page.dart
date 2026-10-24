import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final Profile otherUser;
  const ChatPage({super.key, required this.conversationId, required this.otherUser});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _service = SupabaseService();
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  
  List<Message> _messages = [];
  RealtimeChannel? _messageChannel;
  RealtimeChannel? _typingChannel;
  
  bool _isOtherTyping = false;
  Timer? _typingTimer;
  Timer? _typingDebounce;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    
    // 1. Yeni mesajları gerçek zamanlı dinle
    _messageChannel = _service.subscribeToMessages(widget.conversationId, (m) {
      if (mounted) { 
        setState(() => _messages.add(m)); 
        _toBottom(); 
        // Karşıdan mesaj geldiyse anında okundu işaretle
        if (m.senderId != _service.currentUser?.id) {
          _service.markMessageAsRead(m.id, widget.conversationId);
        }
      }
    });

    // 2. Yazıyor göstergesini dinle
    _typingChannel = _service.subscribeToTyping(widget.conversationId, (username) {
      if (mounted) {
        setState(() => _isOtherTyping = true);
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _isOtherTyping = false);
        });
      }
    });
  }

  Future<void> _loadMessages() async {
    final msgs = await _service.getMessages(widget.conversationId);
    if (mounted) { 
      setState(() => _messages = msgs); 
      _toBottom(); 
      // Ekran açıldığında tüm karşı mesajları okundu yap
      for (var m in msgs) {
        if (m.senderId != _service.currentUser?.id) {
          _service.markMessageAsRead(m.id, widget.conversationId);
        }
      }
    }
  }

  // Kullanıcı yazmaya başladığında tetiklenir (Throttle)
  void _onTyping(String text) {
    if (text.isNotEmpty) {
      _typingDebounce?.cancel();
      _typingDebounce = Timer(const Duration(milliseconds: 500), () {
        _service.sendTypingEvent(widget.conversationId, widget.otherUser.username);
      });
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    _controller.clear();
    await _service.sendMessage(widget.conversationId, t);
  }

  @override
  void dispose() {
    _messageChannel?.unsubscribe(); 
    _typingChannel?.unsubscribe(); 
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    _controller.dispose(); 
    _scroll.dispose(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = _service.currentUser?.id;
    
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: GetticTheme.accent, 
                  radius: 16, 
                  child: Text(
                    widget.otherUser.username.isNotEmpty ? widget.otherUser.username[0].toUpperCase() : '?', 
                    style: const TextStyle(fontSize: 14, color: Colors.white)
                  )
                ),
                const SizedBox(width: 10),
                Text(widget.otherUser.username),
              ]
            ),
            if (_isOtherTyping)
              const Text('yazıyor...', style: TextStyle(fontSize: 12, color: GetticTheme.accent, fontWeight: FontWeight.w500))
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                final mine = m.senderId == myId;
                
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: mine ? GetticTheme.accent : GetticTheme.bgTertiary,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16), 
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(mine ? 16 : 4), 
                        bottomRight: Radius.circular(mine ? 4 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          m.content ?? '', 
                          style: const TextStyle(color: Colors.white, fontSize: 15)
                        ),
                        if (mine) ...[
                          const SizedBox(height: 2),
                          // OKUNDU BİLGİSİ (Mavi Çift Tik)
                          const Icon(
                            Icons.done_all, 
                            size: 15, 
                            color: Color(0xFF60a5fa) // Mavi tik rengi
                          ),
                        ]
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: GetticTheme.bgSecondary, 
              border: Border(top: BorderSide(color: GetticTheme.border))
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller, 
                    decoration: const InputDecoration(hintText: 'Mesaj yaz...'), 
                    onChanged: _onTyping, 
                    onSubmitted: (_) => _send()
                  )
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: GetticTheme.accent, 
                    borderRadius: BorderRadius.circular(12)
                  ), 
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white), 
                    onPressed: _send
                  )
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
