import 'dart:async';
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
  const ChatRoomPage({super.key, required this.conversationId, required this.otherUser});

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _service = SupabaseService();
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  List<Message> _messages = [];
  late Stream<List<Message>> _messagesStream;
  RealtimeChannel? _typingChannel;
  Timer? _typingTimer;
  bool _isOtherTyping = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _messagesStream = _service.streamMessages(widget.conversationId);
    _messagesStream.listen((msgs) {
      if (mounted) {
        setState(() => _messages = msgs);
        _toBottom();
      }
    });

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

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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
    } catch (e, st) {
      print('MESAJ HATASI: $e');
      print('STACK: $st');

      if (mounted) {
        _controller.text = t;
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Text('Mesaj Gönderilemedi',
                style: TextStyle(color: Colors.redAccent)),
            content: Text('$e',
                style: const TextStyle(color: AppTheme.textPrimary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
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
              radius: 18,
              child: Text(
                widget.otherUser.username.isNotEmpty
                    ? widget.otherUser.username[0].toUpperCase()
                    : '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.otherUser.username,
                      style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary)),
                  Text(
                    _isOtherTyping ? 'yazıyor...' : 'Çevrimiçi',
                    style: TextStyle(
                      fontSize: 12,
                      color: _isOtherTyping ? AppTheme.primary : AppTheme.textSecondary,
                      fontStyle: _isOtherTyping ? FontStyle.italic : FontStyle.normal,
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
            child: _messages.isEmpty
                ? const Center(
                    child: Text('İlk mesajı sen gönder!',
                        style: TextStyle(color: AppTheme.textSecondary)),
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
                              maxWidth: MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            color: mine ? AppTheme.primary : AppTheme.surface,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(mine ? 16 : 4),
                              bottomRight: Radius.circular(mine ? 4 : 16),
                            ),
                            border: mine ? null : Border.all(color: AppTheme.inputBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                m.content ?? '',
                                style: TextStyle(
                                  color: mine ? Colors.white : AppTheme.textPrimary,
                                  fontSize: 15,
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
                                        color: mine ? Colors.white70 : AppTheme.textSecondary),
                                  ),
                                  if (mine) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.done_all,
                                        size: 14, color: Color(0xFF60a5fa)),
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
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yaz...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
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
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
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
