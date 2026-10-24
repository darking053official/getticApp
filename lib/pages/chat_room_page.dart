import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  
  Stream<List<Message>>? _messagesStream;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Realtime Stream'i başlatıyoruz. 
    // Bu, Supabase üzerinden gelen anlık değişiklikleri otomatik dinler.
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

    // Kullanıcı deneyimi için inputu hemen temizle (Optimistic UI)
    _messageController.clear();
    setState(() => _isSending = true);

    try {
      await _service.sendMessage(widget.conversationId, text);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        // Hata durumunda inputu geri yükle ve kullanıcıyı bilgilendir
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
      // Klavye açıldığında ekranın küçülmesini sağlar
      resizeToAvoidBottomInset: true, 
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.primary,
              radius: 18,
              backgroundImage: widget.otherUser.avatarUrl != null
                  ? NetworkImage(widget.otherUser.avatarUrl!)
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
                  // İleride online durum göstergesi eklenebilir
                  const Text(
                    'Çevrimiçi', 
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
                      'Mesajlar yüklenemedi.',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  );
                }

                final messages = snapshot.data ?? [];
                
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Henüz mesaj yok. İlk mesajı sen gönder!',
                      style: TextStyle(color: AppTheme.textSecondary),
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
                    
                    // Aynı kişiden ardışık gelen mesajlarda zaman damgasını gizlemek için kontrol
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
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
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
                              border: isMine ? null : Border.all(color: AppTheme.border, width: 1),
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
              // Klavye açıksa alt boşluğu ayarla
              bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : MediaQuery.of(context).padding.bottom + 12,
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
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: _isSending ? AppTheme.primary.withOpacity(0.5) : AppTheme.primary, 
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
