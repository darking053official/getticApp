import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:emoji_mart_flutter/emoji_mart_flutter.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';

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
  final _storage = StorageService();
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();

  List<Message> _messages = [];
  StreamSubscription<List<Message>>? _messagesSubscription;
  RealtimeChannel? _typingChannel;

  Timer? _typingTimer;
  Timer? _typingDebounce;
  Timer? _recordTimer;

  bool _isOtherTyping = false;
  bool _isSending = false;
  bool _showScrollToBottom = false;
  bool _showEmoji = false;
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isRecording = false;
  int _recordSeconds = 0;

  Message? _replyTo;

  @override
  void initState() {
    super.initState();
    AppState().setActiveConversation(widget.conversationId);
    _subscribeToMessages();
    _subscribeToTyping();
    _setupScrollListener();
  }

  void _subscribeToMessages() {
    final stream = _service.streamMessages(widget.conversationId);
    _messagesSubscription = stream.listen(
      (msgs) {
        if (mounted) {
          setState(() {
            _messages = msgs;
            _isLoading = false;
          });
          _scrollToBottom();
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
      final atBottom = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 100;
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
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    final replyId = _replyTo?.id;
    _controller.clear();
    
    setState(() {
      _isSending = true;
      _replyTo = null;
      _showEmoji = false;
    });

    try {
      await _service.sendMessage(widget.conversationId, text, replyToId: replyId);
    } catch (e) {
      if (mounted) {
        _controller.text = text;
        _showSnack('Mesaj gönderilemedi: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ==========================================
  // MEDYA İŞLEMLERİ
  // ==========================================
  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.inputBorder, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _attachOption(Icons.image, 'Fotoğraf', Colors.purple, () { Navigator.pop(ctx); _pickImage(); }),
                  _attachOption(Icons.videocam, 'Video', Colors.blue, () { Navigator.pop(ctx); _pickVideo(); }),
                  _attachOption(Icons.insert_drive_file, 'Dosya', Colors.orange, () { Navigator.pop(ctx); _pickFile(); }),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachOption(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    await _uploadMedia(File(picked.path), 'image');
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    await _uploadMedia(File(picked.path), 'video');
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;
    await _uploadMedia(File(result.files.single.path!), 'file');
  }

  Future<void> _uploadMedia(File file, String type) async {
    setState(() => _isUploading = true);
    final replyId = _replyTo?.id;
    try {
      final path = await _storage.uploadChatMedia(
        file: file,
        conversationId: widget.conversationId,
        type: type,
      );

      if (path != null) {
        await _service.sendMediaMessage(
          conversationId: widget.conversationId,
          type: type,
          mediaPath: path,
          replyToId: replyId,
        );
        if (mounted) setState(() => _replyTo = null);
      } else {
        _showSnack('Medya yüklenemedi', isError: true);
      }
    } catch (e) {
      _showSnack('Hata: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ==========================================
  // SES KAYDI
  // ==========================================
  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      await _audioRecorder.start(const RecordConfig(), path: path);
      
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) setState(() => _recordSeconds++);
        if (_recordSeconds >= 120) _stopRecording();
      });
    } else {
      _showSnack('Mikrofon izni gerekli', isError: true);
    }
  }

  Future<void> _stopRecording({bool send = true}) async {
    _recordTimer?.cancel();
    final path = await _audioRecorder.stop();
    
    setState(() {
      _isRecording = false;
      _recordSeconds = 0;
    });

    if (send && path != null && mounted) {
      await _uploadMedia(File(path), 'audio');
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
    if (msg.isDeleted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12), decoration: BoxDecoration(color: AppTheme.inputBorder, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.reply, color: AppTheme.primary),
                title: const Text('Yanıtla', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () { Navigator.pop(ctx); setState(() => _replyTo = msg); },
              ),
              if (msg.type == 'text')
                ListTile(
                  leading: const Icon(Icons.copy, color: AppTheme.primary),
                  title: const Text('Kopyala', style: TextStyle(color: AppTheme.textPrimary)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: msg.content ?? ''));
                    Navigator.pop(ctx);
                    _showSnack('Kopyalandı');
                  },
                ),
              if (isMine) ...[
                if (msg.type == 'text')
                  ListTile(
                    leading: const Icon(Icons.edit_outlined, color: Colors.orange),
                    title: const Text('Düzenle', style: TextStyle(color: Colors.orange)),
                    onTap: () { Navigator.pop(ctx); _editMessageDialog(msg); },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('Sil', style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await _confirmDialog('Mesajı Sil', 'Bu mesajı silmek istediğine emin misin?');
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
        title: const Text('Mesajı Düzenle', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Yeni mesaj'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal', style: TextStyle(color: AppTheme.textSecondary))),
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
            child: const Text('Kaydet', style: TextStyle(color: AppTheme.primary)),
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
        title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
        content: Text(content, style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal', style: TextStyle(color: AppTheme.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    AppState().clearActiveConversation();
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _messagesSubscription?.cancel();
    _typingChannel?.unsubscribe();
    _service.unsubscribeTyping(widget.conversationId);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _buildMessagesList(),
          ),
          
          if (_isUploading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: AppTheme.surface,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                  SizedBox(width: 12),
                  Text('Medya yükleniyor...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                ],
              ),
            ),

          if (_isOtherTyping)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.inputBorder)),
                  child: const Text('yazıyor...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontStyle: FontStyle.italic)),
                ),
              ),
            ),

          if (_replyTo != null) _buildReplyPreview(),
          
          _isRecording ? _buildRecordingBar() : _buildInputBar(),
          
          if (_showEmoji)
            SizedBox(
              height: 280,
              child: Theme(
                data: Theme.of(context).copyWith(
                  extensions: [
                    const EmojiPickerTheme(
                      backgroundColor: AppTheme.background,
                      searchFieldColor: AppTheme.surface,
                      selectedTabColor: AppTheme.primary,
                      unselectedTabColor: AppTheme.textSecondary,
                    ),
                  ],
                ),
                child: EmojiPicker(
                  set: EmojiPreset.apple.preset,
                  onEmojiSelected: (Emoji emoji) {
                    _controller.text += emoji.char;
                    _controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: _controller.text.length),
                    );
                    setState(() {});
                  },
                  size: 24,
                  columns: 8,
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
              backgroundImage: widget.otherUser.avatarUrl != null ? CachedNetworkImageProvider(widget.otherUser.avatarUrl!) : null,
              child: widget.otherUser.avatarUrl == null
                  ? Text(widget.otherUser.username.isNotEmpty ? widget.otherUser.username[0].toUpperCase() : '?', style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold))
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.otherUser.username, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                Text(
                  _isOtherTyping ? 'yazıyor...' : (widget.otherUser.showOnlineStatus ? 'Çevrimiçi' : 'Çevrimdışı'),
                  style: TextStyle(fontSize: 12, color: _isOtherTyping ? AppTheme.primary : AppTheme.textSecondary, fontStyle: _isOtherTyping ? FontStyle.italic : FontStyle.normal),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.waving_hand_outlined, size: 56, color: AppTheme.primary.withOpacity(0.6)),
            const SizedBox(height: 16),
            const Text('İlk mesajı sen gönder!', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Merhaba de ve sohbeti başlat', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
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
            final showDateDivider = i == 0 || !_isSameDay(_messages[i - 1].createdAt, m.createdAt);

            return Column(
              children: [
                if (showDateDivider)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _formatDateDivider(m.createdAt, dateFormat),
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
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
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    margin: const EdgeInsets.only(bottom: 4),
                    child: const Icon(Icons.reply, color: AppTheme.primary, size: 28),
                  ),
                  secondaryBackground: Container(
                    alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    margin: const EdgeInsets.only(bottom: 4),
                    child: const Icon(Icons.reply, color: AppTheme.primary, size: 28),
                  ),
                  child: GestureDetector(
                    onLongPress: () => _showMessageOptions(m, mine),
                    child: Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
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
                decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.4), blurRadius: 12, spreadRadius: 2)]),
                child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 26),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBubble(Message m, bool mine, DateFormat timeFormat) {
    Widget contentWidget;
    
    if (m.isDeleted) {
      contentWidget = const Text('Bu mesaj silindi', style: TextStyle(color: AppTheme.textSecondary, fontStyle: FontStyle.italic));
    } else if (m.type == 'image' && m.mediaUrl != null) {
      contentWidget = _buildImageBubble(m.mediaUrl!);
    } else if (m.type == 'video' && m.mediaUrl != null) {
      contentWidget = _buildVideoBubble(m.mediaUrl!);
    } else if (m.type == 'audio' && m.mediaUrl != null) {
      contentWidget = _AudioPlayerWidget(path: m.mediaUrl!, storage: _storage);
    } else if (m.type == 'file' && m.mediaUrl != null) {
      contentWidget = _buildFileBubble(m.mediaUrl!, m.content ?? 'Dosya');
    } else {
      contentWidget = Text(
        m.content ?? '',
        style: TextStyle(color: mine ? Colors.white : AppTheme.textPrimary, fontSize: 15, height: 1.35),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: m.type == 'text' || m.isDeleted ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10) : const EdgeInsets.all(4),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
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
                color: (mine ? Colors.white : AppTheme.primary).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: mine ? Colors.white : AppTheme.primary, width: 3)),
              ),
              child: const Text('Yanıtlanan mesaj', style: TextStyle(color: Colors.white70, fontSize: 11)),
            ),
          contentWidget,
          if (m.type == 'text' || m.isDeleted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.editedAt != null && !m.isDeleted)
                    Text('düzenlendi • ', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: mine ? Colors.white70 : AppTheme.textSecondary)),
                  Text(timeFormat.format(m.createdAt), style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : AppTheme.textSecondary)),
                  const SizedBox(width: 4),
                  if (mine && !m.isDeleted)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(m.isRead ? Icons.done_all : Icons.done, size: 14, color: m.isRead ? const Color(0xFF60a5fa) : Colors.white70),
                        const SizedBox(width: 2),
                        Text(m.isRead ? 'Okundu' : 'İletildi', style: TextStyle(fontSize: 10, color: m.isRead ? const Color(0xFF60a5fa) : Colors.white70, fontWeight: FontWeight.w500)),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================
  // MEDYA BALONCUKLARI
  // ==========================================
  Widget _buildImageBubble(String path) {
    return GestureDetector(
      onTap: () => _viewFullImage(path),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<String?>(
          future: _storage.getSignedUrl(path),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container(width: 200, height: 200, color: AppTheme.bgTertiary, child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)));
            }
            return CachedNetworkImage(
              imageUrl: snapshot.data!,
              width: 200,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(width: 200, height: 200, color: AppTheme.bgTertiary, child: const Center(child: CircularProgressIndicator(color: AppTheme.primary))),
              errorWidget: (_, __, ___) => Container(width: 200, height: 200, color: AppTheme.bgTertiary, child: const Icon(Icons.broken_image, color: AppTheme.textSecondary)),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoBubble(String path) {
    return GestureDetector(
      onTap: () => _viewFullVideo(path),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 200, height: 140,
          color: Colors.black,
          child: const Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.videocam, size: 40, color: Colors.white70),
              Icon(Icons.play_circle_fill, size: 50, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileBubble(String path, String fileName) {
    return InkWell(
      onTap: () async {
        final url = await _storage.getSignedUrl(path);
        if (url != null) {
          _showSnack('Dosya indirme: $fileName');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 240),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, color: Colors.white70, size: 32),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  const Text('Dosyayı açmak için tıkla', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _viewFullImage(String path) async {
    final url = await _storage.getSignedUrl(path);
    if (url == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _FullImageViewer(imageUrl: url)));
  }

  void _viewFullVideo(String path) async {
    final url = await _storage.getSignedUrl(path);
    if (url == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _VideoViewer(videoUrl: url)));
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

  // ==========================================
  // YANIT ÖNİZLEME
  // ==========================================
  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.inputBorder, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 4, height: 40,
            decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2)),
            margin: const EdgeInsets.only(right: 12),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _replyTo!.senderId == _service.currentUser?.id
                      ? 'Kendine Yanıt Veriyorsun'
                      : '${widget.otherUser.username} kişisine yanıt veriyorsun',
                  style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyTo!.content ?? '[Medya]',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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

  // ==========================================
  // SES KAYIT ÇUBUĞU
  // ==========================================
  Widget _buildRecordingBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: AppTheme.surface, border: Border(top: BorderSide(color: AppTheme.inputBorder))),
      child: Row(
        children: [
          const Icon(Icons.mic, color: Colors.redAccent, size: 24),
          const SizedBox(width: 12),
          const Text('Kayıt yapılıyor...', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
          const Spacer(),
          Text('${_recordSeconds}s', style: const TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          IconButton(icon: const Icon(Icons.close, color: Colors.redAccent, size: 24), onPressed: () => _stopRecording(send: false)),
          Container(
            decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
            child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 22), onPressed: () => _stopRecording(send: true)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // YAZMA ALANI
  // ==========================================
  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12, right: 12, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: AppTheme.inputBorder, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(color: AppTheme.surface, shape: BoxShape.circle, border: Border.all(color: AppTheme.inputBorder)),
            child: IconButton(
              icon: const Icon(Icons.add, color: AppTheme.primary, size: 24),
              onPressed: _showAttachmentMenu,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppTheme.inputBorder)),
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 5,
                minLines: 1,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Mesaj yaz...',
                  hintStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  isDense: true,
                ),
                onChanged: (v) {
                  _onTyping(v);
                  setState(() {});
                },
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _controller.text.trim().isEmpty
                ? GestureDetector(
                    onLongPress: _startRecording,
                    onLongPressUp: () => _stopRecording(send: true),
                    child: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(color: AppTheme.surface, shape: BoxShape.circle, border: Border.all(color: AppTheme.inputBorder)),
                      child: const Icon(Icons.mic, color: AppTheme.textSecondary, size: 24),
                    ),
                  )
                : GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]),
                      child: _isSending
                          ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TAM EKRAN FOTOĞRAF GÖRÜNTÜLEYİCİ
// ==========================================
class _FullImageViewer extends StatelessWidget {
  final String imageUrl;
  const _FullImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (_, __) => const CircularProgressIndicator(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// VİDEO OYNATICI
// ==========================================
class _VideoViewer extends StatefulWidget {
  final String videoUrl;
  const _VideoViewer({required this.videoUrl});

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    VideoPlayer(_controller),
                    VideoProgressIndicator(_controller, allowScrubbing: true, colors: const VideoProgressColors(playedColor: AppTheme.primary)),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _controller.value.isPlaying ? _controller.pause() : _controller.play();
                        });
                      },
                      child: Center(
                        child: Icon(_controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 64, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

// ==========================================
// SES OYNATICI
// ==========================================
class _AudioPlayerWidget extends StatefulWidget {
  final String path;
  final dynamic storage;

  const _AudioPlayerWidget({required this.path, required this.storage});

  @override
  State<_AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<_AudioPlayerWidget> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = true;
  String? _signedUrl;

  @override
  void initState() {
    super.initState();
    _loadAudio();
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _player.seek(Duration.zero);
            _player.pause();
          }
        });
      }
    });
  }

  Future<void> _loadAudio() async {
    final url = await widget.storage.getSignedUrl(widget.path);
    if (mounted) {
      setState(() {
        _signedUrl = url;
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePlay() async {
    if (_signedUrl == null) return;
    if (_player.audioSource == null) {
      await _player.setUrl(_signedUrl!);
    }
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          else
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 28),
              onPressed: _togglePlay,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final total = _player.duration ?? const Duration(seconds: 1);
                final progress = total.inMilliseconds > 0 ? position.inMilliseconds / total.inMilliseconds : 0.0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(position), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                        Text(_formatDuration(total), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
