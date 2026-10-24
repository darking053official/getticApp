import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';  // RealtimeChannel için
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
  late Stream<List<Message>> _messagesStream;
  
  // TYPING INDICATOR DEĞİŞKENLERİ
  RealtimeChannel? _typingChannel;
  Timer? _typingTimer;
  Timer? _typingDebounce;
  bool _isOtherTyping = false;
  
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    
    // 1. Mesaj stream'i
    _messagesStream = _service.streamMessages(widget.conversationId);
    _messagesStream.listen((msgs) {
      if (mounted) {
        setState(() => _messages = msgs);
        _toBottom();
        for (var m in msgs) {
          if (m.senderId != _service.currentUser?.id) {
            _service.markMessageAsRead(m.id, widget.conversationId);
          }
        }
      }
    });

    // 2. TYPING INDICATOR ABONELİĞİ
    _typingChannel = _service.subscribeToTyping(
      widget.conversationId,
      (username) {
        if (mounted) {
          setState(() => _isOtherTyping = true);
          // 3 saniye sonra otomatik kapat
          _typingTimer?.cancel();
          _typingTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _isOtherTyping = false);
          });
        }
      },
    );
  }

  // KULLANICI YAZARKEN TYPING EVENT GÖNDER (Debounce ile)
  void _onTyping(String text) {
    if (text.isEmpty) return;
    
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 500), () {
      _service.sendTypingEvent(
        widget.conversationId, 
        _service.currentUser?.email?.split('@').first ?? 'Kullanıcı'
      );
    });
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final t = _controller.text.trim();
    if (t.isEmpty || _isSending) return;
    
    _controller.clear();
    setState(() => _isSending = true);
    
    try {
      await _service.sendMessage(widget.conversationId, t);
    } catch (e) {
      if (mounted) {
        _controller.text = t;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gönderilemedi: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    // Temizlik
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    _service.unsubscribeTyping(widget.conversationId);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = _service.currentUser?.id;
    final timeFormat = DateFormat('HH:mm');
    
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.primary,
              radius: 16,
              child: Text(
                widget.otherUser.username.isNotEmpty
                    ? widget.otherUser.username[0].toUpperCase()
                    : '?',
                style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUser.username,
                    style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
                  ),
                  // TYPING GÖSTERGESİ
                  if (_isOtherTyping)
                    const Text(
                      'yazıyor...',
                      style: TextStyle(fontSize: 12, color: AppTheme.primary, fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'İlk mesajı sen gönder!',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : ListView.builder(
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
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78,
                          ),
                          decoration: BoxDecoration(
                            color: mine ? AppTheme.primary : AppTheme.surface,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(mine ? 16 : 4),
                              bottomRight: Radius.circular(mine ? 4 : 16),
                            ),
                            border: mine ? null : Border.all(color: AppTheme.inputBorder, width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                m.content ?? '',
                                style: TextStyle(
                                  color: mine ? Colors.white : AppTheme.textPrimary,
                                  fontSize: 15,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    timeFormat.format(m.createdAt),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: mine ? Colors.white70 : AppTheme.textSecondary,
                                    ),
                                  ),
                                  if (mine) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.done_all, size: 14, color: Color(0xFF60a5fa)),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 12, right: 12, top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom > 0
                  ? 12
                  : MediaQuery.of(context).padding.bottom + 12,
            ),
            decoration: const BoxDecoration(
              color: AppTheme.background,
              border: Border(top: BorderSide(color: AppTheme.inputBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yaz...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: _onTyping,   // TYPING EVENT
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _isSending ? AppTheme.primary.withOpacity(0.5) : AppTheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                    onPressed: _isSending ? null : _send,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
