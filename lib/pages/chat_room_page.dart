import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
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
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _searchController = TextEditingController();

  List<Message> _messages = [];
  List<Message> _searchResults = [];
  late Stream<List<Message>> _messagesStream;
  StreamSubscription<List<Message>>? _messagesSubscription;
  RealtimeChannel? _typingChannel;

  Timer? _typingTimer;
  Timer? _typingDebounce;

  bool _isOtherTyping = false;
  bool _isSending = false;
  bool _showScrollToBottom = false;
  bool _showEmoji = false;
  bool _isSearching = false;
  bool _isLoading = true;

  Message? _replyTo;

  @override
  void initState() {
    super.initState();
    _messagesStream = _service.streamMessages(widget.conversationId);
    _subscribeToMessages();
    _subscribeToTyping();
    _setupScrollListener();
  }

  void _subscribeToMessages() {
    _messagesSubscription = _messagesStream.listen(
      (msgs) {
        if (mounted) {
          setState(() {
            _messages = msgs;
            _isLoading = false;
          });
          _scrollToBottom();
          // Karşıdan gelen mesajları okundu olarak işaretle
          for (var m in msgs) {
            if (m.senderId != _service.currentUser?.id && !m.isRead) {
              _service.markMessageAsRead(m.id, widget.conversationId);
            }
          }
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showSnack('Mesajlar yüklenemedi: $e', isError: true);
        }
      },
    );
  }

  void _subscribeToTyping() {
    _typingChannel = _service.subscribeToTyping(
      widget.conversationId,
      (username) {
        if (mounted) {
          setState(() => _isOtherTyping = true);
          _typingTimer?.cancel();
          _typingTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _isOtherTyping = false);
          });
        }
      },
    );
  }

  void _setupScrollListener() {
    _scroll.addListener(() {
      final atBottom = _scroll.position.pixels >=
          _scroll.position.maxScrollExtent - 100;
      if (_showScrollToBottom == atBottom) {
        setState(() => _showScrollToBottom = !atBottom);
      }
    });
  }

  void _onTyping(String text) {
    if (text.isEmpty) return;
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 500), () {
      _service.sendTypingEvent(
        widget.conversationId,
        _service.currentUser?.email?.split('@').first ?? 'Biri',
      );
    });
  }

  void _scrollToBottom() {
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

    final replyId = _replyTo?.id;

    _controller.clear();
    setState(() {
      _isSending = true;
      _replyTo = null;
      _showEmoji = false;
    });

    try {
      await _service.sendMessage(
        widget.conversationId,
        t,
        replyToId: replyId,
      );
    } catch (e) {
      if (mounted) {
        _controller.text = t;
        _showSnack('Mesaj gönderilemedi: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showMessageOptions(Message msg, bool isMine) {
    if (msg.isDeleted) return; // Silinen mesaja işlem yapma

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: AppTheme.inputBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.reply, color: AppTheme.primary),
                title: const Text('Yanıtla',
                    style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _replyTo = msg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: AppTheme.primary),
                title: const Text('Kopyala',
                    style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.content ?? ''));
                  Navigator.pop(ctx);
                  _showSnack('Kopyalandı');
                },
              ),
              if (isMine) ...[
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: Colors.orange),
                  title: const Text('Düzenle',
                      style: TextStyle(color: Colors.orange)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editMessageDialog(msg);
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('Sil',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await _confirmDialog(
                      'Mesajı Sil',
                      'Bu mesajı silmek istediğine emin misin?',
                    );
                    if (ok == true) {
                      try {
                        await _service.deleteMessage(msg.id);
                        _showSnack('Mesaj silindi');
                      } catch (e) {
                        _showSnack('Hata: $e', isError: true);
                      }
                    }
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _editMessageDialog(Message msg) {
    final controller = TextEditingController(text: msg.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Mesajı Düzenle',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Yeni mesaj'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final newText = controller.text.trim();
              if (newText.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _service.editMessage(msg.id, newText);
                _showSnack('Mesaj düzenlendi');
              } catch (e) {
                _showSnack('Hata: $e', isError: true);
              }
            },
            child: const Text('Kaydet',
                style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDialog(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title,
            style: const TextStyle(color: AppTheme.textPrimary)),
        content: Text(content,
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    _messagesSubscription?.cancel();
    _typingChannel?.unsubscribe();
    _service.unsubscribeTyping(widget.conversationId);
    _controller.dispose();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _isSearching ? _buildSearchAppBar() : _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _isSearching
                    ? _buildSearchResults()
                    : _buildMessagesList(),
          ),
          if (_replyTo != null && !_isSearching) _buildReplyPreview(),
          if (!_isSearching) _buildInputBar(),
          if (_showEmoji && !_isSearching)
            SizedBox(
              height: 280,
              child: EmojiPicker(
                onEmojiSelected: (cat, emoji) {
                  _controller.text += emoji.emoji;
                  _controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: _controller.text.length),
                  );
                },
                config: Config(
                  height: 256,
                  checkPlatformCompatibility: true,
                  emojiViewConfig: EmojiViewConfig(
                    backgroundColor: AppTheme.background,
                    columns: 8,
                    emojiSizeMax: 28,
                  ),
                  categoryViewConfig: const CategoryViewConfig(
                    backgroundColor: AppTheme.background,
                    iconColor: AppTheme.textSecondary,
                    iconColorSelected: AppTheme.primary,
                  ),
                  bottomActionBarConfig: const BottomActionBarConfig(
                    backgroundColor: AppTheme.surface,
                  ),
                  searchViewConfig: const SearchViewConfig(
                    backgroundColor: AppTheme.surface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          GestureDetector(
            onTap: () => _showSnack('Profil görüntüleme yakında'),
            child: CircleAvatar(
              backgroundColor: AppTheme.primary,
              radius: 20,
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
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
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
                _isOtherTyping
                    ? const _TypingIndicator()
                    : Text(
                        widget.otherUser.showOnlineStatus
                            ? 'Çevrimiçi'
                            : 'Çevrimdışı',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: AppTheme.textSecondary),
          onPressed: () => setState(() => _isSearching = true),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSearchAppBar() {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
        onPressed: () => setState(() {
          _isSearching = false;
          _searchController.clear();
          _searchResults.clear();
        }),
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: const InputDecoration(
          hintText: 'Sohbette ara...',
          hintStyle: TextStyle(color: AppTheme.textSecondary),
          border: InputBorder.none,
        ),
        onChanged: (v) {
          if (v.trim().isEmpty) {
            setState(() => _searchResults = []);
          } else {
            setState(() {
              _searchResults = _messages
                  .where((m) =>
                      (m.content ?? '').toLowerCase().contains(v.toLowerCase()))
                  .toList();
            });
          }
        },
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          _searchController.text.isEmpty ? 'Aramak için yaz' : 'Sonuç bulunamadı',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _searchResults.length,
      itemBuilder: (context, i) {
        final m = _searchResults[i];
        return ListTile(
          title: Text(m.content ?? '',
              style: const TextStyle(color: AppTheme.textPrimary)),
          subtitle: Text(
            DateFormat('d MMM, HH:mm', 'tr_TR').format(m.createdAt),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        );
      },
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.waving_hand_outlined,
                size: 56, color: AppTheme.primary.withOpacity(0.6)),
            const SizedBox(height: 16),
            const Text('İlk mesajı sen gönder!',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Merhaba de ve sohbeti başlat',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    final myId = _service.currentUser?.id;
    final timeFormat = DateFormat('HH:mm');
    final dateFormat = DateFormat('d MMMM yyyy', 'tr_TR');

    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          itemCount: _messages.length,
          itemBuilder: (context, i) {
            final m = _messages[i];
            final mine = m.senderId == myId;
            final showDateDivider = i == 0 ||
                !_isSameDay(_messages[i - 1].createdAt, m.createdAt);

            return Column(
              children: [
                if (showDateDivider)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _formatDateDivider(m.createdAt, dateFormat),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Dismissible(
                  key: ValueKey(m.id),
                  direction: DismissDirection.horizontal,
                  confirmDismiss: (direction) async {
                    if (!m.isDeleted) setState(() => _replyTo = m);
                    return false;
                  },
                  background: Container(
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    margin: const EdgeInsets.only(bottom: 4),
                    child: const Icon(Icons.reply,
                        color: AppTheme.primary, size: 28),
                  ),
                  secondaryBackground: Container(
                    alignment:
                        mine ? Alignment.centerLeft : Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    margin: const EdgeInsets.only(bottom: 4),
                    child: const Icon(Icons.reply,
                        color: AppTheme.primary, size: 28),
                  ),
                  child: GestureDetector(
                    onLongPress: () => _showMessageOptions(m, mine),
                    child: Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: _buildBubble(m, mine, timeFormat),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (_showScrollToBottom)
          Positioned(
            bottom: 16,
            right: 16,
            child: GestureDetector(
              onTap: _scrollToBottom,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.keyboard_arrow_down,
                    color: Colors.white, size: 26),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBubble(Message m, bool mine, DateFormat timeFormat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
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
          if (m.replyToId != null && !m.isDeleted)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (mine ? Colors.white : AppTheme.primary)
                    .withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: mine ? Colors.white : AppTheme.primary,
                    width: 3,
                  ),
                ),
              ),
              child: const Text(
                'Yanıtlanan mesaj',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          Text(
            m.isDeleted ? '🚫 Bu mesaj silindi' : (m.content ?? ''),
            style: TextStyle(
              color: mine ? Colors.white : AppTheme.textPrimary,
              fontSize: 15,
              height: 1.35,
              fontStyle: m.isDeleted ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.editedAt != null && !m.isDeleted)
                Text(
                  'düzenlendi • ',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: mine ? Colors.white70 : AppTheme.textSecondary,
                  ),
                ),
              Text(
                timeFormat.format(m.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: mine ? Colors.white70 : AppTheme.textSecondary,
                ),
              ),
              if (mine && !m.isDeleted) ...[
                const SizedBox(width: 4),
                Icon(
                  m.isRead ? Icons.done_all : Icons.done,
                  size: 14,
                  color: m.isRead ? const Color(0xFF60a5fa) : Colors.white70,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateDivider(DateTime date, DateFormat fmt) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) return 'Bugün';
    if (_isSameDay(date, now.subtract(const Duration(days: 1)))) return 'Dün';
    return fmt.format(date);
  }

  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.inputBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            color: AppTheme.primary,
            margin: const EdgeInsets.only(right: 8),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Yanıtlanıyor',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _replyTo?.content ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
            onPressed: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0
            ? 8
            : MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: AppTheme.inputBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: Icon(
              _showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined,
              color: AppTheme.textSecondary,
            ),
            onPressed: () {
              if (_showEmoji) {
                setState(() => _showEmoji = false);
                FocusScope.of(context).requestFocus();
              } else {
                FocusScope.of(context).unfocus();
                setState(() => _showEmoji = true);
              }
            },
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.inputBorder),
              ),
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 5,
                minLines: 1,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Mesaj yaz...',
                  hintStyle:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  isDense: true,
                ),
                onChanged: _onTyping,
                onTap: () {
                  if (_showEmoji) setState(() => _showEmoji = false);
                },
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              decoration: BoxDecoration(
                color: _isSending
                    ? AppTheme.primary.withOpacity(0.5)
                    : AppTheme.primary,
                borderRadius: BorderRadius.circular(50),
              ),
              child: IconButton(
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 22),
                onPressed: _isSending ? null : _send,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TYPING INDICATOR (Animasyonlu 3 nokta)
// ==========================================
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('yazıyor',
            style: TextStyle(
                fontSize: 12,
                color: AppTheme.primary,
                fontStyle: FontStyle.italic)),
        const SizedBox(width: 4),
        AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            final dots = (_controller.value * 3).floor();
            return Text('.' * (dots + 1),
                style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold));
          },
        ),
      ],
    );
  }
}
