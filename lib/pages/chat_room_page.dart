import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';

class ChatRoomPage extends StatefulWidget {
  final String conversationId;
  final Profile otherUser;

  const ChatRoomPage({
    super.key,
    required this.conversationId,
    required this.otherUser,
  });

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _service = SupabaseService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  
  late final Stream<List<Message>> _messagesStream;
  bool _isSending = false;
  bool _isTyping = false; // İleride typing indicator için

  @override
  void initState() {
    super.initState();
    // Realtime Stream (Supabase v2 .stream() ile)
    _messagesStream = _service.streamMessages(widget.conversationId);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    // Optimistic UI - Mesaj gitmese bile input temizlenir
    _messageController.clear();
    setState(() => _isSending = true);

    try {
      await _service.sendMessage(widget.conversationId, text);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        // Hata olursa mesajı geri koy
        _messageController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mesaj gönderilemedi: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = _service.currentUser?.id;
    final timeFormat = DateFormat('HH:mm');

    return Scaffold(
      resizeToAvoidBottomInset: true, 
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.primary,
              radius: 18,
              backgroundImage: widget.otherUser.avatarUrl != null
                  ? CachedNetworkImageProvider(widget.otherUser.avatarUrl!)
                  : null,
              child: widget.otherUser.avatarUrl == null
                  ? Text(
                      widget.otherUser.username.isNotEmpty 
                          ? widget.otherUser.username[0].toUpperCase() 
                          : '?',
                      style: const TextStyle(
                        fontSize: 16, 
                        color: Colors.white,
                        fontWeight: FontWeight.bold
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUser.username,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    // İleride show_online_status ve status ile dinamik yapılabilir
                    _isTyping ? 'yazıyor...' : 'Çevrimiçi', 
                    style: TextStyle(
                      fontSize: 12, 
                      color: _isTyping ? AppTheme.primary : AppTheme.textSecondary,
                      fontStyle: _isTyping ? FontStyle.italic : FontStyle.normal,
                    ),
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
            child: StreamBuilder<List<Message>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  );
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Mesajlar yüklenemedi.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  );
                }

                final messages = snapshot.data ?? [];
                
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.waving_hand_outlined, size: 48, color: AppTheme.surface),
                        const SizedBox(height: 12),
                        const Text(
                          'İlk mesajı sen gönder!',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                // Yeni mesaj geldiğinde otomatik aşağı kaydır
                _scrollToBottom();

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMine = msg.senderId == myId;
                    
                    // Aynı kişiden 5 dk içinde gelen mesajlarda zaman damgasını gizle
                    final showTimestamp = index == 0 || 
                        messages[index - 1].senderId != msg.senderId ||
                        msg.createdAt.difference(messages[index - 1].createdAt).inMinutes > 5;

                    return Column(
                      crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        if (showTimestamp)
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 6, left: 8, right: 8),
                            child: Text(
                              timeFormat.format(msg.createdAt),
                              style: const TextStyle(
                                fontSize: 11, 
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        Align(
                          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.78,
                            ),
                            decoration: BoxDecoration(
                              color: isMine ? AppTheme.primary : AppTheme.surface,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMine ? 16 : 4),
                                bottomRight: Radius.circular(isMine ? 4 : 16),
                              ),
                              // ⚠️ DÜZELTME: AppTheme.border -> AppTheme.inputBorder
                              border: isMine ? null : Border.all(color: AppTheme.inputBorder, width: 1),
                            ),
                            child: Text(
                              msg.content,
                              style: TextStyle(
                                color: isMine ? Colors.white : AppTheme.textPrimary, 
                                fontSize: 15,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          
          // Mesaj Gönderme Alanı
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom > 0 
                  ? 12 
                  : MediaQuery.of(context).padding.bottom + 12,
            ),
            decoration: const BoxDecoration(
              color: AppTheme.background,
              border: Border(top: BorderSide(color: AppTheme.inputBorder)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 4,
                    minLines: 1,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yaz...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onSubmitted: (_) => _send(),
                    onChanged: (val) {
                      // İleride typing event gönderilebilir
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: _isSending 
                          ? AppTheme.primary.withOpacity(0.5) 
                          : AppTheme.primary, 
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: _isSending 
                          ? const SizedBox(
                              width: 20, 
                              height: 20, 
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white),
                      onPressed: _isSending ? null : _send,
                    ),
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
