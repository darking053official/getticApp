// ============================================================
// lib/pages/chat_room_page.dart
// (.txt olarak verildi. Projeye eklerken adını chat_room_page.dart yapın.)
// ============================================================

import 'dart:async';
import 'dart:convert';
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
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import 'profile_preview.dart';
import 'group_info_page.dart';
import '../services/chat_outbox.dart';
import '../services/e2ee_media.dart';

// ============================================================
// AYARLAR
// ============================================================
/// Chat medyalarının yüklendiği Supabase Storage bucket adı.
const String _kMediaBucket = 'chat-media';

/// GIF arama için kullanılan Supabase Edge Function adı.
const String _kGifFunctionName = 'search-gifs';

/// Yarım kalan mesajlar cihazda saklansın mı?
const bool _kPersistDrafts = true;

/// Emoji paneli için hazır liste.
const List<String> _kEmojis = [
  '😀',
  '😃',
  '😄',
  '😁',
  '😆',
  '😅',
  '😂',
  '🤣',
  '😊',
  '😇',
  '🙂',
  '🙃',
  '😉',
  '😌',
  '😍',
  '🥰',
  '😘',
  '😗',
  '😙',
  '😚',
  '😋',
  '😛',
  '😜',
  '🤪',
  '😝',
  '🤑',
  '🤗',
  '🤭',
  '🤫',
  '🤔',
  '🤐',
  '🤨',
  '😐',
  '😑',
  '😶',
  '😏',
  '😒',
  '🙄',
  '😬',
  '🤥',
  '😔',
  '😪',
  '🤤',
  '😴',
  '😷',
  '🤒',
  '🤕',
  '🤢',
  '🤮',
  '🤧',
  '🥵',
  '🥶',
  '😵',
  '🤯',
  '🤠',
  '🥳',
  '😎',
  '🤓',
  '🧐',
  '😕',
  '😟',
  '🙁',
  '😮',
  '😯',
  '😲',
  '😳',
  '🥺',
  '😦',
  '😧',
  '😨',
  '😰',
  '😥',
  '😢',
  '😭',
  '😱',
  '😖',
  '😣',
  '😞',
  '😓',
  '😩',
  '😫',
  '🥱',
  '😤',
  '😡',
  '😠',
  '🤬',
  '😈',
  '👿',
  '💀',
  '💩',
  '🤡',
  '👻',
  '👽',
  '🤖',
  '😺',
  '😸',
  '😹',
  '😻',
  '😼',
  '😽',
  '🙀',
  '😿',
  '😾',
  '👍',
  '👎',
  '👌',
  '✌',
  '🤞',
  '🤟',
  '🤘',
  '👏',
  '🙌',
  '👐',
  '🤲',
  '🤝',
  '🙏',
  '💪',
  '❤',
  '🧡',
  '💛',
  '💚',
  '💙',
  '💜',
  '🖤',
  '🤍',
  '💔',
  '💕',
  '💞',
  '💓',
  '💗',
  '💖',
  '💘',
  '💝',
  '🔥',
  '✨',
  '⭐',
  '🌟',
  '💯',
  '✅',
  '❌',
  '⚠',
  '🎉',
  '🎊',
  '🎁',
  '🏆',
];

/// İmzalı URL önbelleği (süre dolmadan yenilenir).
class _CachedUrl {
  final Future<String?> future;
  final DateTime expiresAt;
  const _CachedUrl(this.future, this.expiresAt);
}

// ============================================================
// MESAJ DÜZENLEME DİYALOĞU
// ============================================================
class _EditMessageDialog extends StatefulWidget {
  final String initialText;
  const _EditMessageDialog({super.key, required this.initialText});

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Mesajı Düzenle',
          style: TextStyle(color: AppTheme.textPrimary)),
      content: TextField(
        controller: _c,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: const InputDecoration(hintText: 'Yeni mesaj'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Kaydet', style: TextStyle(color: AppTheme.primary)),
        ),
      ],
    );
  }
}

class ChatRoomPage extends StatefulWidget {
  final String conversationId;
  /// Birebir sohbette karşı kullanıcı. Grupta grup adını taşıyan yer tutucu.
  final Profile otherUser;
  final bool isGroup;
  final String? groupName;
  final String? groupCreatedBy;
  const ChatRoomPage({
    super.key,
    required this.conversationId,
    required this.otherUser,
    this.isGroup = false,
    this.groupName,
    this.groupCreatedBy,
  });

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage>
    with WidgetsBindingObserver {
  // ---- Sabitler ----
  static const int _maxUploadBytes = 25 * 1024 * 1024; // 25 MB
  static const int _maxRecordSeconds = 120;
  static const int _minRecordSeconds = 1;

  final _service = SupabaseService();
  final _storage = StorageService();
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();

  List<Message> _messages = [];
  StreamSubscription<List<Message>>? _messagesSubscription;
  RealtimeChannel? _typingChannel;
  RealtimeChannel? _readChannel;

  Timer? _typingTimer;
  Timer? _typingDebounce;
  Timer? _recordTimer;
  Timer? _markReadDebounce;
  Timer? _readPoll;

  // Storage path -> imzalı URL önbelleği
  final Map<String, _CachedUrl> _urlCache = {};
  // Mesaj id -> GlobalKey (alıntıya tıklayınca o mesaja gitmek için)
  final Map<dynamic, GlobalKey> _messageKeys = {};
  final FocusNode _inputFocus = FocusNode();
  Timer? _draftTimer;
  dynamic _highlightId;
  int _newWhileAway = 0;
  bool _isForeground = true;

  // Karşı tarafın son okuma zamanı (görüldü hesabı için)
  DateTime? _otherReadAt;

  bool _isOtherTyping = false;
  bool _isSending = false;
  bool _showScrollToBottom = false;
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isRecording = false;
  bool _isStoppingRecording = false;
  bool _firstLoad = true;
  int _recordSeconds = 0;

  Message? _replyTo;
  bool _showEmoji = false;
  // Parti 1: tepkiler (mesaj id -> emoji -> kullanıcı id listesi), sabitleme
  Map<String, Map<String, List<String>>> _reactionUsers = {};
  String? _pinnedId;
  RealtimeChannel? _reactChannel;
  RealtimeChannel? _metaChannel;
  // Parti 2: oda ayarları
  bool _muted = false;
  int? _disappear;
  String? _wallpaper;
  Timer? _outboxTimer;
  Map<String, String> _memberNames = {};
  String? _groupNameOverride;

  @override
  void initState() {
    super.initState();
    AppState().setActiveConversation(widget.conversationId);
    _subscribeToMessages();
    _subscribeToTyping();
    _subscribeToReads();
    _refreshOtherReadAt();
    _loadPinned();
    _subscribeReactionsAndPins();
    _loadRoomSettings();
    _flushOutbox();
    _outboxTimer = Timer.periodic(const Duration(seconds: 15), (_) => _flushOutbox());
    if (widget.isGroup) _loadGroupMembers();
    _readPoll = Timer.periodic(
        const Duration(seconds: 15), (_) => _refreshOtherReadAt());
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
    _setupScrollListener();
    WidgetsBinding.instance.addObserver(this);
    _loadDraft();
    _controller.addListener(_onDraftChanged);
  }

  /// Uygulama arka plandayken mesajlar okundu işaretlenmez (gizlilik).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _isForeground) return;
    _isForeground = fg;
    if (fg) _markRead();
  }

  // ==========================================
  // TASLAK (yarım kalan mesaj)
  // ==========================================
  String get _draftKey => 'chat_draft_${widget.conversationId}';

  Future<void> _loadDraft() async {
    if (!_kPersistDrafts) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_draftKey);
      if (!mounted || saved == null || saved.isEmpty) return;
      if (_controller.text.isEmpty) {
        _controller.text = saved;
        _controller.selection = TextSelection.collapsed(offset: saved.length);
      }
    } catch (_) {}
  }

  void _onDraftChanged() {
    _draftTimer?.cancel();
    final text = _controller.text;
    _draftTimer =
        Timer(const Duration(milliseconds: 500), () => _persistDraft(text));
  }

  Future<void> _persistDraft(String text) async {
    if (!_kPersistDrafts) return;
    final key = _draftKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (text.trim().isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, text);
      }
    } catch (_) {}
  }

  void _toggleEmoji() {
    setState(() => _showEmoji = !_showEmoji);
    if (_showEmoji) {
      _inputFocus.unfocus();
    } else {
      _inputFocus.requestFocus();
    }
  }

  /// İmleç konumuna emoji ekler (seçili metin varsa onun yerine).
  void _insertEmoji(String emoji) {
    final v = _controller.value;
    final len = v.text.length;
    var start = v.selection.isValid ? v.selection.start : len;
    var end = v.selection.isValid ? v.selection.end : len;
    if (start < 0) start = len;
    if (end < 0) end = len;
    final text = v.text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Widget _buildEmojiPanel() {
    return Container(
      height: 240,
      color: AppTheme.surface,
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 46,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: _kEmojis.length,
        itemBuilder: (_, i) => InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _insertEmoji(_kEmojis[i]),
          child: Center(
            child: Text(_kEmojis[i], style: const TextStyle(fontSize: 24)),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // PARTİ 2: SOHBET AYARLARI, KUYRUK, ARKA PLAN
  // ==========================================
  String get _wallpaperKey => 'chat_wallpaper_${widget.conversationId}';

  Future<void> _loadRoomSettings() async {
    try {
      final muted = await _service.getMuted(widget.conversationId);
      final secs = await _service.getDisappearing(widget.conversationId);
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _muted = muted;
        _disappear = secs;
        _wallpaper = prefs.getString(_wallpaperKey);
      });
    } catch (_) {}
  }

  Future<void> _flushOutbox() async {
    await ChatOutbox.instance.flush(_service, conversationId: widget.conversationId);
    if (!mounted) return;
    setState(() {});
  }

  BoxDecoration? _wallpaperDecoration() {
    final p = _wallpaper;
    if (p == null || !File(p).existsSync()) return null;
    return BoxDecoration(
      image: DecorationImage(
        image: FileImage(File(p)),
        fit: BoxFit.cover,
        colorFilter:
            ColorFilter.mode(Colors.black.withOpacity(0.35), BlendMode.darken),
      ),
    );
  }

  Future<void> _pickWallpaper() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperKey, picked.path);
    if (mounted) setState(() => _wallpaper = picked.path);
  }

  Future<void> _removeWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_wallpaperKey);
    if (mounted) setState(() => _wallpaper = null);
  }

  String _disappearLabel(int? secs) {
    if (secs == null) return 'Kapalı';
    if (secs == 86400) return '24 saat';
    if (secs == 604800) return '7 gün';
    return '$secs sn';
  }

  void _showRoomSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.inputBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: AppTheme.primary),
                title: const Text('Kaybolan mesajlar',
                    style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: Text(_disappearLabel(_disappear),
                    style: const TextStyle(color: AppTheme.textSecondary)),
                onTap: () async {
                  final picked = await showModalBottomSheet<int?>(
                    context: ctx,
                    backgroundColor: AppTheme.surface,
                    builder: (c2) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final opt in <MapEntry<String, int?>>[
                            const MapEntry('Kapalı', null),
                            const MapEntry('24 saat', 86400),
                            const MapEntry('7 gün', 604800),
                          ])
                            ListTile(
                              title: Text(opt.key,
                                  style: const TextStyle(
                                      color: AppTheme.textPrimary)),
                              trailing: _disappear == opt.value
                                  ? const Icon(Icons.check,
                                      color: AppTheme.primary)
                                  : null,
                              onTap: () => Navigator.pop(c2, opt.value),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (!mounted) return;
                  if (picked != _disappear || picked == null) {
                    try {
                      await _service.setDisappearing(widget.conversationId, picked);
                      if (!mounted) return;
                      setState(() => _disappear = picked);
                      setS(() {});
                      _showSnack('Kaybolan mesaj: ${_disappearLabel(picked)}');
                    } catch (e) {
                      _showSnack('Hata: $e', isError: true);
                    }
                  }
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_off_outlined,
                    color: AppTheme.primary),
                activeColor: AppTheme.primary,
                title: const Text('Sessize al',
                    style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: const Text('Bu sohbetten bildirim gelmez',
                    style: TextStyle(color: AppTheme.textSecondary)),
                value: _muted,
                onChanged: (v) async {
                  try {
                    await _service.setMuted(widget.conversationId, v);
                    if (!mounted) return;
                    setState(() => _muted = v);
                    setS(() {});
                  } catch (e) {
                    _showSnack('Hata: $e', isError: true);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.wallpaper, color: AppTheme.primary),
                title: const Text('Sohbet arka planı',
                    style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickWallpaper();
                },
              ),
              if (_wallpaper != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('Arka planı kaldır',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeWallpaper();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // PARTİ 1: TEPKİLER
  // ==========================================
  void _subscribeReactionsAndPins() {
    _reactChannel = Supabase.instance.client
        .channel('react-${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (_) => _loadReactions(),
        )
        .subscribe();
    _metaChannel = Supabase.instance.client
        .channel('meta-${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.conversationId,
          ),
          callback: (_) => _loadPinned(),
        )
        .subscribe();
  }

  Future<void> _loadReactions() async {
    final ids = _messages.map((m) => m.id.toString()).toList();
    if (ids.isEmpty) return;
    final rows = await _service.getReactions(ids);
    if (!mounted) return;
    final map = <String, Map<String, List<String>>>{};
    for (final r in rows) {
      final mid = r['message_id'].toString();
      final emoji = r['emoji'].toString();
      map.putIfAbsent(mid, () => {}).putIfAbsent(emoji, () => []).add(
          r['user_id'].toString());
    }
    setState(() => _reactionUsers = map);
  }

  Future<void> _toggleReaction(dynamic messageId, String emoji) async {
    try {
      await _service.toggleReaction(messageId.toString(), emoji);
      _loadReactions();
    } catch (e) {
      _showSnack('Tepki eklenemedi: $e', isError: true);
    }
  }

  Widget _buildReactionChips(Message msg) {
    final byEmoji = _reactionUsers[msg.id.toString()];
    if (byEmoji == null || byEmoji.isEmpty || msg.isDeleted) {
      return const SizedBox.shrink();
    }
    final me = _service.currentUser?.id;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: byEmoji.entries.map((e) {
          final mine = e.value.contains(me);
          return GestureDetector(
            onTap: () => _toggleReaction(msg.id, e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: mine
                    ? AppTheme.primary.withOpacity(0.25)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: mine ? AppTheme.primary : AppTheme.inputBorder),
              ),
              child: Text(
                '${e.key} ${e.value.length}',
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 12),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ==========================================
  // PARTİ 1: SABİTLEME
  // ==========================================
  Future<void> _loadPinned() async {
    try {
      final id = await _service.getPinnedMessageId(widget.conversationId);
      if (!mounted) return;
      setState(() => _pinnedId = id);
    } catch (_) {}
  }

  Future<void> _setPinned(String? messageId) async {
    try {
      await _service.setPinnedMessage(widget.conversationId, messageId);
      if (!mounted) return;
      setState(() => _pinnedId = messageId);
      _showSnack(messageId == null ? 'Sabitleme kaldırıldı' : 'Mesaj sabitlendi');
    } catch (e) {
      _showSnack('Hata: $e', isError: true);
    }
  }

  Widget _buildPinnedBanner() {
    final id = _pinnedId;
    if (id == null) return const SizedBox.shrink();
    Message? m;
    for (final x in _messages) {
      if (x.id.toString() == id) {
        m = x;
        break;
      }
    }
    return Material(
      color: AppTheme.surface,
      child: InkWell(
        onTap: m == null ? null : () => _scrollToMessage(m!.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              const Icon(Icons.push_pin, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m == null ? 'Sabitlenen mesaj' : _previewText(m),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 13),
                ),
              ),
              IconButton(
                tooltip: 'Sabitlemeyi kaldır',
                icon: const Icon(Icons.close,
                    size: 18, color: AppTheme.textSecondary),
                onPressed: () => _setPinned(null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // PARTİ 1: İLETME
  // ==========================================
  Future<void> _showForwardSheet(Message m) async {
    List<Map<String, dynamic>> convs;
    try {
      convs = await _service.getMyConversationsWithUnread();
    } catch (_) {
      _showSnack('Sohbetler yüklenemedi', isError: true);
      return;
    }
    convs = convs
        .where((c) => c['conversation_id'].toString() != widget.conversationId)
        .toList();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Şuraya ilet',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            if (convs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('İletilecek başka sohbet yok',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ...convs.map((c) {
              final isGroup = c['is_group'] == true;
              final name = isGroup
                  ? (c['group_name'] ?? 'Grup').toString()
                  : (c['other_user']?['username'] ?? 'Sohbet').toString();
              return ListTile(
                leading: Icon(
                    isGroup ? Icons.groups : Icons.person,
                    color: AppTheme.primary),
                title: Text(name,
                    style: const TextStyle(color: AppTheme.textPrimary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await _service.forwardMessage(
                        c['conversation_id'].toString(), m);
                    _showSnack('Mesaj iletildi');
                  } catch (e) {
                    _showSnack('İletilemedi: $e', isError: true);
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // PARTİ 1: MESAJ ARAMA
  // ==========================================
  void _showSearchSheet() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final q = controller.text.trim().toLowerCase();
          final results = q.isEmpty
              ? <Message>[]
              : _messages
                  .where((m) =>
                      !m.isDeleted &&
                      (m.content ?? '').toLowerCase().contains(q))
                  .toList()
                  .reversed
                  .take(50)
                  .toList();
          return Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.6,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Mesajlarda ara...',
                      prefixIcon:
                          Icon(Icons.search, color: AppTheme.textSecondary),
                    ),
                    onChanged: (_) => setS(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: results.isEmpty
                        ? Center(
                            child: Text(
                              q.isEmpty ? 'Aramak için yazın' : 'Sonuç yok',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              final m = results[i];
                              final when = _createdAtOf(m);
                              return ListTile(
                                title: Text(
                                  m.content ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppTheme.textPrimary),
                                ),
                                subtitle: Text(
                                  when == null
                                      ? ''
                                      : DateFormat('dd.MM.yyyy HH:mm')
                                          .format(when),
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12),
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _scrollToMessage(m.id);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(controller.dispose);
  }

  void _startReply(Message m) {
    if (m.isDeleted) return;
    setState(() => _replyTo = m);
    _inputFocus.requestFocus();
  }

  // ==========================================
  // MESAJLAR
  // ==========================================
  void _subscribeToMessages() {
    _messagesSubscription =
        _service.streamMessages(widget.conversationId).listen(
      (msgs) {
        if (!mounted) return;

        final myId = _service.currentUser?.id;
        final wasNearBottom = _isNearBottom();
        final oldLastId = _messages.isNotEmpty ? _messages.last.id : null;
        final hasNewLast = msgs.isNotEmpty && msgs.last.id != oldLastId;
        final lastIsMine = msgs.isNotEmpty && msgs.last.senderId == myId;
        final lastIsFromOther = msgs.isNotEmpty && !lastIsMine;

        setState(() {
          _messages = msgs;
          _isLoading = false;
          if (hasNewLast && lastIsFromOther) {
            _isOtherTyping = false;
            if (!wasNearBottom) _newWhileAway++;
          }
        });

        if (_firstLoad) {
          _firstLoad = false;
          _scrollToBottom(animated: false);
        } else if (hasNewLast && (wasNearBottom || lastIsMine)) {
          _scrollToBottom();
        }

        _markIncomingAsRead(msgs, myId);
        _loadReactions();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showSnack('Mesajlar yüklenemedi: $e', isError: true);
      },
    );
  }

  /// Gelen mesaj varsa sohbeti okundu olarak işaretler (en fazla 1 sn'de bir).
  void _markIncomingAsRead(List<Message> msgs, String? myId) {
    if (!_isForeground) return;
    final hasIncoming = msgs.any((m) => m.senderId != myId);
    if (!hasIncoming) return;
    _markRead();
  }

  void _markRead() {
    if (!_isForeground) return;
    if (_markReadDebounce?.isActive ?? false) return;
    _markReadDebounce = Timer(const Duration(seconds: 1), () {});
    _service
        .markConversationRead(widget.conversationId)
        .then((_) => _refreshOtherReadAt());
  }

  // ==========================================
  // GÖRÜLDÜ (karşı tarafın okuma zamanı)
  // ==========================================
  void _subscribeToReads() {
    _readChannel = Supabase.instance.client
        .channel('read-${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversation_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (_) => _refreshOtherReadAt(),
        )
        .subscribe();
  }

  String get _title => widget.isGroup
      ? (_groupNameOverride ?? widget.groupName ?? widget.otherUser.username)
      : widget.otherUser.username;

  Future<void> _loadGroupMembers() async {
    final list = await _service.getGroupMembers(widget.conversationId);
    if (!mounted) return;
    setState(() {
      _memberNames = {for (final p in list) p.id: p.username};
    });
  }

  /// Grup bilgilerini açar. Ad değiştiyse başlığı günceller, gruptan ayrılındıysa sohbeti kapatır.
  Future<void> _openGroupInfo() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInfoPage(
          conversationId: widget.conversationId,
          groupName: _title,
          createdBy: widget.groupCreatedBy,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result == kGroupLeft) {
      Navigator.pop(context);
      return;
    }
    setState(() => _groupNameOverride = result);
    _loadGroupMembers();
  }

  Future<void> _refreshOtherReadAt() async {
    if (widget.isGroup) return; // grupta tek bir karşı taraf yok
    final t = await _service.getOtherReadAt(widget.conversationId);
    if (!mounted) return;
    setState(() => _otherReadAt = t);
  }

  /// Karşı taraf bu mesajı okudu mu? (mesaj zamanı <= karşının son okuma zamanı)
  bool _isReadByOther(Message m) {
    final r = _otherReadAt;
    final c = _createdAtOf(m);
    if (r == null || c == null) return false;
    return !c.isAfter(r);
  }

  // ==========================================
  // YAZIYOR... GÖSTERGESİ
  // ==========================================
  void _subscribeToTyping() {
    _typingChannel = _service.subscribeToTyping(
      widget.conversationId,
      (username) {
        if (!mounted) return;
        setState(() => _isOtherTyping = true);
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _isOtherTyping = false);
        });
      },
    );
  }

  /// Input bar'daki TextField'ın onChanged'ine bağlı.
  DateTime? _lastTypingSent;

  /// Yazarken her 2 saniyede bir "yazıyor" olayı gönderir (duraklamayı beklemez).
  void _onTyping(String text) {
    if (text.trim().isEmpty) return;
    final now = DateTime.now();
    if (_lastTypingSent == null ||
        now.difference(_lastTypingSent!) > const Duration(seconds: 2)) {
      _lastTypingSent = now;
      _sendTypingEvent();
    }
  }

  Future<void> _sendTypingEvent() async {
    try {
      await _service.sendTypingEvent(
        widget.conversationId,
        _service.currentUser?.email?.split('@').first ?? 'Biri',
      );
    } catch (_) {}
  }

  // ==========================================
  // SCROLL
  // ==========================================
  bool _isNearBottom() {
    if (!_scroll.hasClients) return true;
    return _scroll.position.pixels >= _scroll.position.maxScrollExtent - 100;
  }

  void _setupScrollListener() {
    _scroll.addListener(() {
      if (!mounted || !_scroll.hasClients) return;
      final near = _isNearBottom();
      final show = !near;
      if (show != _showScrollToBottom || (near && _newWhileAway != 0)) {
        setState(() {
          _showScrollToBottom = show;
          if (near) _newWhileAway = 0;
        });
      }
    });
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(
          max,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(max);
      }
    });
  }

  GlobalKey _keyFor(dynamic id) =>
      _messageKeys.putIfAbsent(id, () => GlobalKey());

  /// Alıntılanan mesaja kaydırır ve kısa süre vurgular.
  Future<void> _scrollToMessage(dynamic id) async {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx < 0 || !_scroll.hasClients) {
      _showSnack('Mesaj bulunamadı');
      return;
    }

    // Liste tembel çizilir: öğe görünene kadar yaklaşık konuma atlayıp tekrar dene
    BuildContext? target;
    for (var attempt = 0; attempt < 8; attempt++) {
      target = _messageKeys[id]?.currentContext;
      if (target != null) break;
      final max = _scroll.position.maxScrollExtent;
      final denom = _messages.length > 1 ? _messages.length - 1 : 1;
      final approx = (max * idx / denom).clamp(0.0, max).toDouble();
      _scroll.jumpTo(approx);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    target ??= _messageKeys[id]?.currentContext;

    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.3,
      );
    }
    if (!mounted) return;

    setState(() => _highlightId = id);
    Timer(const Duration(milliseconds: 1200), () {
      if (mounted && _highlightId == id) setState(() => _highlightId = null);
    });
  }

  // ==========================================
  // MESAJ GÖNDERME
  // ==========================================
  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    _lastTypingSent = null;

    final reply = _replyTo;
    _controller.clear();
    HapticFeedback.lightImpact();

    setState(() {
      _isSending = true;
      _replyTo = null;
    });

    try {
      await _service.sendMessage(widget.conversationId, text,
          replyToId: reply?.id);
    } catch (e) {
      // Çevrimdışıysa mesajı kuyruğa al, bağlantı gelince otomatik gönderilir
      await ChatOutbox.instance.add(widget.conversationId, text, reply?.id);
      if (mounted) {
        setState(() => _replyTo = null);
        _showSnack('Bağlantı yok. Mesaj bağlantı gelince gönderilecek');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _openProfilePreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePreviewPage(
          profile: widget.otherUser,
          onMessageTap: () => Navigator.pop(context),
          onBlockTap: () async {
            Navigator.pop(context);
            _showSnack('${widget.otherUser.username} engellendi');
          },
          onReportTap: () async {
            Navigator.pop(context);
            _showSnack('${widget.otherUser.username} bildirildi');
          },
        ),
      ),
    );
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
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.inputBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 24,
                runSpacing: 16,
                children: [
                  if (Platform.isAndroid || Platform.isIOS)
                    _attachOption(Icons.photo_camera, 'Kamera', Colors.teal,
                        () {
                      Navigator.pop(ctx);
                      _pickImage(fromCamera: true);
                    }),
                  _attachOption(Icons.image, 'Fotoğraf', Colors.purple, () {
                    Navigator.pop(ctx);
                    _pickImage();
                  }),
                  _attachOption(Icons.videocam, 'Video', Colors.blue, () {
                    Navigator.pop(ctx);
                    _pickVideo();
                  }),
                  _attachOption(
                      Icons.insert_drive_file, 'Dosya', Colors.orange, () {
                    Navigator.pop(ctx);
                    _pickFile();
                  }),
                  _attachOption(Icons.audiotrack, 'Ses', Colors.green, () {
                    Navigator.pop(ctx);
                    _pickAudioFile();
                  }),
                  _attachOption(Icons.gif_box, 'GIF', Colors.pink, () {
                    Navigator.pop(ctx);
                    _showGifSearch();
                  }),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachOption(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _pickImage({bool fromCamera = false}) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (picked == null || !mounted) return;
      final file = File(picked.path);
      final ok = await _confirmSendImage(file);
      if (ok != true) return;
      await _uploadMedia(file, 'image');
    } catch (e) {
      _showSnack('Fotoğraf seçilemedi: $e', isError: true);
    }
  }

  Future<bool?> _confirmSendImage(File file) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.surface,
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child:
                const Text('Gönder', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickVideo() async {
    try {
      final picked =
          await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      await _uploadMedia(File(picked.path), 'video');
    } catch (e) {
      _showSnack('Video seçilemedi: $e', isError: true);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      final path = result?.files.single.path;
      if (path == null) return;
      await _uploadMedia(File(path), 'file');
    } catch (e) {
      _showSnack('Dosya seçilemedi: $e', isError: true);
    }
  }

  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      await _uploadMedia(File(path), 'audio');
    } catch (e) {
      _showSnack('Ses dosyası seçilemedi: $e', isError: true);
    }
  }

  Future<void> _uploadMedia(File file, String type,
      {bool deleteAfter = false}) async {
    if (_isUploading) {
      _showSnack('Önceki yükleme devam ediyor');
      return;
    }

    setState(() => _isUploading = true);
    final reply = _replyTo;

    try {
      final size = await file.length();
      if (size > _maxUploadBytes) {
        _showSnack(
          'Dosya çok büyük (en fazla ${_maxUploadBytes ~/ (1024 * 1024)} MB)',
          isError: true,
        );
        return;
      }

      await _service.sendEncryptedMedia(
        conversationId: widget.conversationId,
        type: type,
        file: file,
        replyToId: reply?.id,
      );
      if (mounted) setState(() => _replyTo = null);
    } catch (e) {
      _showSnack('Hata: $e', isError: true);
    } finally {
      if (deleteAfter) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ==========================================
  // GIF ARAMA (Supabase Edge Function)
  // ==========================================
  Future<void> _showGifSearch() async {
    final selectedGifUrl = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _GifSearchSheet(),
    );

    if (selectedGifUrl == null || !mounted) return;

    final reply = _replyTo;
    try {
      await _service.sendMediaMessage(
        conversationId: widget.conversationId,
        type: 'gif',
        mediaPath: selectedGifUrl,
        replyToId: reply?.id,
      );
      if (mounted) setState(() => _replyTo = null);
    } catch (e) {
      _showSnack('GIF gönderilemedi: $e', isError: true);
    }
  }

  // ==========================================
  // SES KAYDI
  // ==========================================
  Future<void> _startRecording() async {
    if (_isRecording || _isStoppingRecording || _isUploading) return;

    try {
      if (!await _audioRecorder.hasPermission()) {
        _showSnack('Mikrofon izni gerekli', isError: true);
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(const RecordConfig(), path: path);

      if (!mounted) {
        await _audioRecorder.cancel();
        return;
      }

      HapticFeedback.mediumImpact();
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _recordSeconds++);
        if (_recordSeconds >= _maxRecordSeconds) _stopRecording();
      });
    } catch (e) {
      _showSnack('Kayıt başlatılamadı: $e', isError: true);
    }
  }

  /// [send] = true  -> kaydı bitirir ve gönderir
  /// [send] = false -> kaydı iptal eder ve dosyayı siler
  Future<void> _stopRecording({bool send = true}) async {
    if (!_isRecording || _isStoppingRecording) return;
    _isStoppingRecording = true;
    _recordTimer?.cancel();

    final seconds = _recordSeconds;
    final tooShort = seconds < _minRecordSeconds;

    try {
      String? path;
      if (send && !tooShort) {
        path = await _audioRecorder.stop();
      } else {
        await _audioRecorder.cancel();
      }

      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordSeconds = 0;
        });
      }

      if (send && tooShort) {
        _showSnack('Kayıt çok kısa');
      } else if (path != null && mounted) {
        await _uploadMedia(File(path), 'audio', deleteAfter: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordSeconds = 0;
        });
      }
      _showSnack('Kayıt hatası: $e', isError: true);
    } finally {
      _isStoppingRecording = false;
    }
  }

  // ==========================================
  // YARDIMCILAR
  // ==========================================
  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isError ? Colors.redAccent : AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
  }

  DateTime? _createdAtOf(Message m) {
    try {
      final dynamic d = m;
      final v = d.createdAt;
      if (v is DateTime) return v.toLocal();
      if (v is String) return DateTime.tryParse(v)?.toLocal();
    } catch (_) {}
    return null;
  }

  String? _mediaPathOf(Message m) {
    final dynamic d = m;
    final getters = <dynamic Function()>[
      () => d.mediaPath,
      () => d.mediaUrl,
    ];
    for (final g in getters) {
      try {
        final v = g();
        if (v is String && v.isNotEmpty) return v;
      } catch (_) {}
    }
    return null;
  }

  dynamic _replyToIdOf(Message m) {
    try {
      final dynamic d = m;
      return d.replyToId;
    } catch (_) {
      return null;
    }
  }

  bool _isEditedOf(Message m) {
    try {
      final dynamic d = m;
      return d.isEdited == true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _resolveMediaUrl(String path, [Message? msg]) {
    final secret = msg?.mediaSecret;
    if (msg != null && secret != null) {
      return E2eeMedia.instance
          .localPath(
            convId: msg.conversationId,
            storagePath: path,
            secret: secret,
            fileName: (secret['name'] ?? '').toString(),
          )
          .then<String?>((p) => p)
          .catchError((_) => null);
    }
    final cached = _urlCache[path];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.future;
    }

    final Future<String?> future = (() async {
      if (path.startsWith('http')) return path;
      try {
        return await Supabase.instance.client.storage
            .from(_kMediaBucket)
            .createSignedUrl(path, 3600);
      } catch (_) {
        return null;
      }
    })();

    _urlCache[path] =
        _CachedUrl(future, DateTime.now().add(const Duration(minutes: 50)));

    future.then((url) {
      if (url == null) {
        _urlCache[path] =
            _CachedUrl(future, DateTime.now().add(const Duration(seconds: 20)));
      }
    });
    return future;
  }

  String _previewText(Message m) {
    if (m.isDeleted) return 'Silinmiş mesaj';
    switch (m.type) {
      case 'image':
        return '📷 Fotoğraf';
      case 'video':
        return '🎥 Video';
      case 'audio':
      case 'voice':
        return '🎤 Ses';
      case 'gif':
        return 'GIF';
      case 'file':
        return '📎 Dosya';
      default:
        return m.content ?? '';
    }
  }

  bool _isSameDay(DateTime a, DateTime? b) {
    if (b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    if (_isSameDay(d, now)) return 'Bugün';
    if (_isSameDay(d, now.subtract(const Duration(days: 1)))) return 'Dün';
    return DateFormat('dd.MM.yyyy').format(d);
  }

  /// Tüm emojilerden tepki seçme paneli.
  void _showAllReactions(Message msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 300,
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 46,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: _kEmojis.length,
            itemBuilder: (_, i) => InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                Navigator.pop(ctx);
                _toggleReaction(msg.id, _kEmojis[i]);
              },
              child: Center(
                child: Text(_kEmojis[i], style: const TextStyle(fontSize: 24)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(Message msg, bool isMine) {
    if (msg.isDeleted) return;
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
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: AppTheme.inputBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              if (!msg.isDeleted)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['👍', '❤️', '😂', '😮', '😢', '🙏']
                      .map<Widget>((e) => InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              Navigator.pop(ctx);
                              _toggleReaction(msg.id, e);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(e,
                                  style: const TextStyle(fontSize: 26)),
                            ),
                          ))
                      .toList()
                    ..add(IconButton(
                      tooltip: 'Tüm tepkiler',
                      icon: const Icon(Icons.add_reaction_outlined,
                          color: AppTheme.primary),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showAllReactions(msg);
                      },
                    )),
                ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.reply, color: AppTheme.primary),
                title: const Text('Yanıtla',
                    style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _startReply(msg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward, color: AppTheme.primary),
                title: const Text('İlet',
                    style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showForwardSheet(msg);
                },
              ),
              ListTile(
                leading: Icon(
                    _pinnedId == msg.id.toString()
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    color: AppTheme.primary),
                title: Text(
                    _pinnedId == msg.id.toString()
                        ? 'Sabitlemeyi kaldır'
                        : 'Sabitle',
                    style: const TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _setPinned(_pinnedId == msg.id.toString()
                      ? null
                      : msg.id.toString());
                },
              ),
              if (msg.type == 'text')
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
                if (msg.type == 'text')
                  ListTile(
                    leading: const Icon(Icons.edit_outlined,
                        color: Colors.orange),
                    title: const Text('Düzenle',
                        style: TextStyle(color: Colors.orange)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _editMessageDialog(msg);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: Colors.redAccent),
                  title: const Text('Sil',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await _confirmDialog('Mesajı Sil',
                        'Bu mesajı silmek istediğine emin misin?');
                    if (ok != true || !mounted) return;
                    try {
                      await _service.deleteMessage(msg.id);
                      _showSnack('Mesaj silindi');
                    } catch (e) {
                      _showSnack('Hata: $e', isError: true);
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

  Future<void> _editMessageDialog(Message msg) async {
    final original = msg.content ?? '';
    final newText = await showDialog<String>(
      context: context,
      builder: (_) => _EditMessageDialog(initialText: original),
    );

    if (newText == null || !mounted) return;
    if (newText == original.trim()) return;

    try {
      await _service.editMessage(msg.id, newText);
      _showSnack('Mesaj düzenlendi');
    } catch (e) {
      _showSnack('Hata: $e', isError: true);
    }
  }

  Future<bool?> _confirmDialog(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
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
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onDraftChanged);
    _draftTimer?.cancel();
    _markReadDebounce?.cancel();
    _readPoll?.cancel();
    // Sohbetten çıkarken okundu yaz (liste sayacı hemen düşsün)
    unawaited(_service.markConversationRead(widget.conversationId));
    unawaited(_persistDraft(_controller.text));
    _inputFocus.dispose();
    AppState().clearActiveConversation();
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    _recordTimer?.cancel();

    if (_isRecording) {
      _audioRecorder
          .cancel()
          .catchError((_) {})
          .whenComplete(_audioRecorder.dispose);
    } else {
      _audioRecorder.dispose();
    }

    _messagesSubscription?.cancel();
    _typingChannel?.unsubscribe();
    _readChannel?.unsubscribe();
    _reactChannel?.unsubscribe();
    _metaChannel?.unsubscribe();
    _outboxTimer?.cancel();
    _service.unsubscribeTyping(widget.conversationId);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ==========================================
  // UI
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                : Container(
                    decoration: _wallpaperDecoration(),
                    child: _buildMessagesList(),
                  ),
          ),

          _buildPinnedBanner(),

          if (_isUploading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: AppTheme.surface,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary),
                  ),
                  SizedBox(width: 12),
                  Text('Medya yükleniyor...',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                ],
              ),
            ),

          if (_isOtherTyping)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const _TypingDots(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.otherUser.username} yazıyor',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),

          if (_replyTo != null) _buildReplyPreview(),

          _isRecording ? _buildRecordingBar() : _buildInputBar(),
          if (_showEmoji && !_isRecording) _buildEmojiPanel(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final title = _title;
    final subtitle = widget.isGroup
        ? '${_memberNames.length} üye'
        : (_isOtherTyping
            ? 'yazıyor...'
            : (widget.otherUser.showOnlineStatus ? 'Çevrimiçi' : 'Çevrimdışı'));
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      titleSpacing: 0,
      actions: [
        IconButton(
          tooltip: 'Sohbet ayarları',
          icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
          onPressed: _showRoomSettings,
        ),
        IconButton(
          tooltip: 'Mesajlarda ara',
          icon: const Icon(Icons.search, color: AppTheme.textSecondary),
          onPressed: _showSearchSheet,
        ),
      ],
      title: Row(
        children: [
          GestureDetector(
            onTap: widget.isGroup ? _openGroupInfo : _openProfilePreview,
            child: widget.isGroup
                ? const CircleAvatar(
                    radius: 20,
                    backgroundColor: AppTheme.primary,
                    child: Icon(Icons.groups, color: Colors.white),
                  )
                : CircleAvatar(
                    backgroundColor: AppTheme.primary,
                    radius: 20,
                    backgroundImage: widget.otherUser.avatarUrl != null
                        ? CachedNetworkImageProvider(widget.otherUser.avatarUrl!)
                        : null,
                    child: widget.otherUser.avatarUrl == null
                        ? Text(
                            widget.otherUser.initial,
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
            child: GestureDetector(
              onTap: widget.isGroup ? _openGroupInfo : null,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: (_isOtherTyping && !widget.isGroup)
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                      fontStyle: (_isOtherTyping && !widget.isGroup)
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MESAJ LİSTESİ
  // ==========================================
  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.waving_hand_outlined,
                size: 56, color: AppTheme.primary.withOpacity(0.6)),
            const SizedBox(height: 16),
            const Text(
              'İlk mesajı sen gönder!',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _messages.length,
          itemBuilder: (context, i) => _buildMessageItem(i),
        ),
        if (_showScrollToBottom)
          Positioned(
            right: 12,
            bottom: 12,
            child: Badge(
              isLabelVisible: _newWhileAway > 0,
              label: Text('$_newWhileAway'),
              child: FloatingActionButton.small(
                heroTag: 'chat_scroll_bottom_${widget.conversationId}',
                backgroundColor: AppTheme.surface,
                onPressed: () => _scrollToBottom(),
                child: const Icon(Icons.keyboard_arrow_down,
                    color: AppTheme.primary),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageItem(int i) {
    final msg = _messages[i];
    final isMine = msg.senderId == _service.currentUser?.id;
    final createdAt = _createdAtOf(msg);
    final prevCreatedAt = i > 0 ? _createdAtOf(_messages[i - 1]) : null;
    final showDate = createdAt != null &&
        (i == 0 || !_isSameDay(createdAt, prevCreatedAt));

    final grouped =
        !showDate && i > 0 && _messages[i - 1].senderId == msg.senderId;
    final highlighted = _highlightId != null && _highlightId == msg.id;

    return KeyedSubtree(
      key: _keyFor(msg.id),
      child: Column(
        children: [
          if (showDate && createdAt != null) _buildDateChip(createdAt),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            color: highlighted
                ? AppTheme.primary.withOpacity(0.15)
                : Colors.transparent,
            child: _SwipeToReply(
              enabled: !msg.isDeleted,
              reverse: isMine,
              onReply: () => _startReply(msg),
              child: _buildBubble(msg, isMine, createdAt, grouped: grouped),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(DateTime d) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _dateLabel(d),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildBubble(Message msg, bool isMine, DateTime? createdAt,
      {bool grouped = false}) {
    final maxW = MediaQuery.of(context).size.width * 0.78;
    final bubbleColor = isMine ? AppTheme.primary : AppTheme.surface;
    final textColor = isMine ? Colors.white : AppTheme.textPrimary;
    final metaColor = isMine ? Colors.white70 : AppTheme.textSecondary;
    final read = isMine && _isReadByOther(msg);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageOptions(msg, isMine),
        child: Container(
          margin: EdgeInsets.only(top: grouped ? 1 : 4, bottom: 1),
          constraints: BoxConstraints(maxWidth: maxW),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isGroup && !isMine && !grouped)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    _memberNames[msg.senderId] ?? 'Üye',
                    style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              _buildQuotedReply(msg, isMine, textColor),
              if (msg.forwarded && !msg.isDeleted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.forward,
                          size: 12,
                          color: isMine ? Colors.white70 : AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text('İletildi',
                          style: TextStyle(
                              color: isMine
                                  ? Colors.white70
                                  : AppTheme.textSecondary,
                              fontSize: 11,
                              fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              _buildMessageBody(msg, isMine, textColor),
              _buildReactionChips(msg),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!msg.isDeleted && _isEditedOf(msg))
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text('düzenlendi',
                            style: TextStyle(color: metaColor, fontSize: 10)),
                      ),
                    if (createdAt != null)
                      Text(DateFormat('HH:mm').format(createdAt),
                          style: TextStyle(color: metaColor, fontSize: 10)),
                    if (isMine && !msg.isDeleted && !widget.isGroup) ...[
                      const SizedBox(width: 4),
                      Icon(
                        read ? Icons.done_all : Icons.done,
                        size: 14,
                        color: read ? Colors.lightBlueAccent : metaColor,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuotedReply(Message msg, bool isMine, Color textColor) {
    final replyId = _replyToIdOf(msg);
    if (replyId == null || msg.isDeleted) return const SizedBox.shrink();

    Message? target;
    for (final m in _messages) {
      if (m.id == replyId) {
        target = m;
        break;
      }
    }

    final targetIsMine = target?.senderId == _service.currentUser?.id;
    final name = target == null
        ? 'Yanıtlanan mesaj'
        : (targetIsMine ? 'Sen' : widget.otherUser.username);

    final quote = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMine ? Colors.white : AppTheme.primary,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          Text(
            target == null ? 'Mesaj bulunamadı' : _previewText(target),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 12),
          ),
        ],
      ),
    );

    if (target == null) return quote;
    return GestureDetector(
      onTap: () => _scrollToMessage(replyId),
      child: quote,
    );
  }

  Widget _buildMessageBody(Message msg, bool isMine, Color textColor) {
    if (msg.isDeleted) {
      return Text(
        'Bu mesaj silindi',
        style: TextStyle(
          color: textColor.withOpacity(0.6),
          fontStyle: FontStyle.italic,
          fontSize: 14,
        ),
      );
    }

    if (msg.decryptFailed) {
      return Text(
        'Şifreli mesaj, bu cihazda çözülemiyor',
        style: TextStyle(
          color: textColor.withOpacity(0.7),
          fontStyle: FontStyle.italic,
          fontSize: 14,
        ),
      );
    }

    switch (msg.type) {
      case 'image':
      case 'gif':
        return _mediaImage(msg);
      case 'video':
        return _mediaVideo(msg);
      case 'audio':
      case 'voice':
        return _mediaAudio(msg, textColor);
      case 'file':
        return _mediaFile(msg, textColor);
      default:
        final text = msg.content ?? '';
        final link = RegExp(r'https?://[^\s]+').firstMatch(text)?.group(0);
        final body = Text(
          text,
          style: TextStyle(color: textColor, fontSize: 15),
        );
        if (link == null) return body;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            body,
            _LinkPreviewCard(url: link, textColor: textColor),
          ],
        );
    }
  }

  // ---- Medya balonları ----
  Widget _mediaPlaceholder({double height = 160}) {
    return Container(
      width: 220,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.primary),
        ),
      ),
    );
  }

  Widget _mediaError() {
    return Container(
      width: 220,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.white54),
            SizedBox(height: 4),
            Text('Medya yüklenemedi',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _mediaImage(Message msg) {
    final path = _mediaPathOf(msg);
    if (path == null) return _mediaError();

    return FutureBuilder<String?>(
      future: _resolveMediaUrl(path, msg),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _mediaPlaceholder();
        }
        final url = snap.data;
        if (url == null) return _mediaError();

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _ImageViewerPage(url: url)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: url.startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: url,
                      width: 220,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _mediaPlaceholder(),
                      errorWidget: (_, __, ___) => _mediaError(),
                    )
                  : Image.file(File(url),
                      width: 220, fit: BoxFit.cover),
            ),
          ),
        );
      },
    );
  }

  Widget _mediaVideo(Message msg) {
    final path = _mediaPathOf(msg);
    if (path == null) return _mediaError();

    return GestureDetector(
      onTap: () => _openVideo(path, msg),
      child: Container(
        width: 220,
        height: 140,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(Icons.play_circle_fill, color: Colors.white, size: 52),
        ),
      ),
    );
  }

  Future<void> _openVideo(String path, Message msg) async {
    final url = await _resolveMediaUrl(path, msg);
    if (!mounted) return;
    if (url == null) {
      _showSnack('Video açılamadı', isError: true);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _VideoPlayerPage(url: url)),
    );
  }

  /// Dosyayı geçici klasöre indirir ve cihazdaki uygun uygulamayla açar.
  Future<void> _openFile(String path, Message msg) async {
    final url = await _resolveMediaUrl(path, msg);
    if (!mounted) return;
    if (url == null) {
      _showSnack('Dosya bağlantısı alınamadı', isError: true);
      return;
    }
    // Şifreli dosya zaten yerel olarak çözüldü
    if (!url.startsWith('http')) {
      await OpenFilex.open(url);
      return;
    }

    _showSnack('Dosya indiriliyor...');
    final client = HttpClient();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${path.split('/').last}');

      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      await res.pipe(file.openWrite());

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        _showSnack('Dosya açılamadı: ${result.message}', isError: true);
      }
    } catch (e) {
      _showSnack('Dosya indirilemedi: $e', isError: true);
    } finally {
      client.close();
    }
  }

  Widget _mediaAudio(Message msg, Color textColor) {
    final path = _mediaPathOf(msg);
    if (path == null) return _mediaError();
    return _AudioPlayerTile(
      key: ValueKey('audio_${msg.id}'),
      urlLoader: () => _resolveMediaUrl(path, msg),
      color: textColor,
      seed: msg.id.toString(),
    );
  }

  Widget _mediaFile(Message msg, Color textColor) {
    final path = _mediaPathOf(msg);
    if (path == null) return _mediaError();
    final name = path.split('/').last;

    return InkWell(
      onTap: () => _openFile(path, msg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file, color: textColor, size: 30),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // YANIT ÖNİZLEME / GİRİŞ / KAYIT ÇUBUKLARI
  // ==========================================
  Widget _buildReplyPreview() {
    final r = _replyTo!;
    final mine = r.senderId == _service.currentUser?.id;

    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Container(width: 3, height: 36, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mine ? 'Sen' : widget.otherUser.username,
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _previewText(r),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppTheme.textSecondary),
            onPressed: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: AppTheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: AppTheme.primary),
                onPressed: _isUploading ? null : _showAttachmentMenu,
              ),
              IconButton(
                tooltip: 'Emoji',
                icon: Icon(
                  _showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined,
                  color: AppTheme.primary,
                ),
                onPressed: _toggleEmoji,
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _inputFocus,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  onChanged: _onTyping,
                  decoration: InputDecoration(
                    hintText: 'Mesaj yaz...',
                    hintStyle: const TextStyle(color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: AppTheme.background,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppTheme.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppTheme.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppTheme.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  return CircleAvatar(
                    backgroundColor: AppTheme.primary,
                    radius: 22,
                    child: IconButton(
                      icon: Icon(hasText ? Icons.send : Icons.mic,
                          color: Colors.white, size: 20),
                      onPressed: hasText
                          ? (_isSending ? null : () => _send())
                          : () => _startRecording(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingBar() {
    final mm = (_recordSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_recordSeconds % 60).toString().padLeft(2, '0');

    return Container(
      color: AppTheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _stopRecording(send: false),
              ),
              const Icon(Icons.fiber_manual_record,
                  color: Colors.redAccent, size: 14),
              const SizedBox(width: 8),
              Text(
                '$mm:$ss',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              CircleAvatar(
                backgroundColor: AppTheme.primary,
                radius: 22,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: () => _stopRecording(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// KAYDIRARAK YANITLA
// ============================================================
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;
  final bool reverse;
  const _SwipeToReply({
    required this.child,
    required this.onReply,
    this.enabled = true,
    this.reverse = false,
  });

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const double _trigger = 56;
  double _dx = 0;
  bool _triggered = false;

  void _reset() {
    if (!mounted) return;
    setState(() {
      _dx = 0;
      _triggered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        final delta = widget.reverse ? -d.delta.dx : d.delta.dx;
        setState(() => _dx = (_dx + delta).clamp(0.0, 72.0).toDouble());
        if (_dx >= _trigger && !_triggered) {
          _triggered = true;
          HapticFeedback.selectionClick();
        }
      },
      onHorizontalDragEnd: (_) {
        if (_triggered) widget.onReply();
        _reset();
      },
      onHorizontalDragCancel: _reset,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: widget.reverse ? null : 8,
            right: widget.reverse ? 8 : null,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: (_dx / _trigger).clamp(0.0, 1.0).toDouble(),
                child: const Icon(Icons.reply, color: AppTheme.primary),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(widget.reverse ? -_dx : _dx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SES OYNATICI
// ============================================================
class _AudioPlayerTile extends StatefulWidget {
  final Future<String?> Function() urlLoader;
  final Color color;
  final String seed;
  const _AudioPlayerTile({
    super.key,
    required this.urlLoader,
    required this.color,
    required this.seed,
  });

  @override
  State<_AudioPlayerTile> createState() => _AudioPlayerTileState();
}

class _AudioPlayerTileState extends State<_AudioPlayerTile> {
  static _AudioPlayerTileState? _current;

  static const List<double> _speeds = [1.0, 1.5, 2.0];
  int _speedIndex = 0;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration?>? _durSub;
  Duration _duration = Duration.zero;
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _durSub = _player.durationStream.listen((d) {
      if (d != null && mounted) setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    if (_current == this) _current = null;
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _cycleSpeed() async {
    _speedIndex = (_speedIndex + 1) % _speeds.length;
    try {
      await _player.setSpeed(_speeds[_speedIndex]);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (_loading) return;
    try {
      if (!_loaded) {
        setState(() {
          _loading = true;
          _failed = false;
        });
        final url = await widget.urlLoader();
        if (url == null) throw Exception('url yok');
        if (url.startsWith('http')) {
          await _player.setUrl(url);
        } else {
          await _player.setFilePath(url);
        }
        _loaded = true;
        if (mounted) setState(() => _loading = false);
      }

      final completed = _player.processingState == ProcessingState.completed;
      if (_player.playing && !completed) {
        await _player.pause();
      } else {
        if (completed) await _player.seek(Duration.zero);
        if (_current != null && _current != this) {
          unawaited(_current!._player.pause());
        }
        _current = this;
        unawaited(_player.play());
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snap) {
              final st = snap.data;
              final showPause = (st?.playing ?? false) &&
                  st?.processingState != ProcessingState.completed;

              if (_loading) {
                return const SizedBox(
                  width: 40,
                  height: 40,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: Icon(
                  _failed
                      ? Icons.error_outline
                      : (showPause ? Icons.pause : Icons.play_arrow),
                  color: widget.color,
                  size: 28,
                ),
                onPressed: _toggle,
              );
            },
          ),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final total = _duration.inMilliseconds;
                final value = total == 0
                    ? 0.0
                    : (pos.inMilliseconds / total).clamp(0.0, 1.0);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: widget.color,
                        inactiveTrackColor: widget.color.withOpacity(0.3),
                        thumbColor: widget.color,
                      ),
                      child: _Waveform(
                        seed: widget.seed,
                        progress: value,
                        color: widget.color,
                        onSeek: _loaded && total > 0
                            ? (v) => _player.seek(
                                Duration(milliseconds: (v * total).round()))
                            : null,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Row(
                        children: [
                          Text(
                            _loaded
                                ? '${_fmt(pos)} / ${_fmt(_duration)}'
                                : 'Ses',
                            style: TextStyle(
                                color: widget.color.withOpacity(0.8),
                                fontSize: 11),
                          ),
                          const Spacer(),
                          if (_loaded)
                            GestureDetector(
                              onTap: _cycleSpeed,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: widget.color.withOpacity(0.6)),
                                ),
                                child: Text(
                                  _speeds[_speedIndex] ==
                                          _speeds[_speedIndex].roundToDouble()
                                      ? '${_speeds[_speedIndex].toInt()}x'
                                      : '${_speeds[_speedIndex]}x',
                                  style: TextStyle(
                                      color: widget.color, fontSize: 10),
                                ),
                              ),
                            ),
                        ],
                      ),
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
}

// ============================================================
// TAM EKRAN RESİM
// ============================================================
class _ImageViewerPage extends StatelessWidget {
  final String url;
  const _ImageViewerPage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: url.startsWith('http')
              ? CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) =>
                      const CircularProgressIndicator(color: AppTheme.primary),
                  errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48),
                )
              : Image.file(File(url), fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ============================================================
// TAM EKRAN VİDEO
// ============================================================
class _VideoPlayerPage extends StatefulWidget {
  final String url;
  const _VideoPlayerPage({required this.url});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  static const List<double> _speeds = [1.0, 1.5, 2.0];

  VideoPlayerController? _vc;
  Timer? _hideTimer;
  bool _error = false;
  bool _controlsVisible = true;
  int _speedIndex = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final vc = widget.url.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(widget.url))
        : VideoPlayerController.file(File(widget.url));
    _vc = vc;
    try {
      await vc.initialize();
      if (!mounted) return;
      await vc.play();
      if (!mounted) return;
      setState(() {});
      _scheduleHide();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _vc?.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      final vc = _vc;
      if (mounted && vc != null && vc.value.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    final vc = _vc;
    if (vc == null) return;
    try {
      final v = vc.value;
      final ended = v.duration > Duration.zero && v.position >= v.duration;
      if (v.isPlaying && !ended) {
        await vc.pause();
        _hideTimer?.cancel();
      } else {
        if (ended) await vc.seekTo(Duration.zero);
        await vc.play();
        _scheduleHide();
      }
    } catch (_) {}
  }

  Future<void> _cycleSpeed() async {
    final vc = _vc;
    if (vc == null) return;
    _speedIndex = (_speedIndex + 1) % _speeds.length;
    try {
      await vc.setPlaybackSpeed(_speeds[_speedIndex]);
    } catch (_) {}
    if (mounted) setState(() {});
    _scheduleHide();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildControls(VideoPlayerController vc) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: vc,
      builder: (context, v, _) {
        final pos = v.position;
        final dur = v.duration;
        final ended = dur > Duration.zero && pos >= dur;
        final showPause = v.isPlaying && !ended;
        final speed = _speeds[_speedIndex];

        return Container(
          color: Colors.black26,
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(),
                IconButton(
                  iconSize: 64,
                  color: Colors.white,
                  icon: Icon(showPause
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled),
                  onPressed: _togglePlay,
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VideoProgressIndicator(
                        vc,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: AppTheme.primary,
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '${_fmt(pos)} / ${_fmt(dur)}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: _cycleSpeed,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white70),
                              ),
                              child: Text(
                                speed == speed.roundToDouble()
                                    ? '${speed.toInt()}x'
                                    : '${speed}x',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vc = _vc;
    final ready = vc != null && vc.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _error
          ? const Center(
              child: Text('Video oynatılamadı',
                  style: TextStyle(color: Colors.white70)),
            )
          : !ready
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary))
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  child: Stack(
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: vc.value.aspectRatio > 0
                              ? vc.value.aspectRatio
                              : 16 / 9,
                          child: VideoPlayer(vc),
                        ),
                      ),
                      Positioned.fill(
                        child: AnimatedOpacity(
                          opacity: _controlsVisible ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: IgnorePointer(
                            ignoring: !_controlsVisible,
                            child: _buildControls(vc),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ============================================================
// GIF ARAMA SAYFASI (Supabase Edge Function)
// ============================================================
class _GifSearchSheet extends StatefulWidget {
  const _GifSearchSheet();

  @override
  State<_GifSearchSheet> createState() => _GifSearchSheetState();
}

class _GifSearchSheetState extends State<_GifSearchSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<String> _gifs = [];
  bool _loading = false;
  bool _error = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _search(q.trim());
    });
  }

  Future<void> _search(String query) async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = false;
    });

    try {
      final res = await Supabase.instance.client.functions.invoke(
        _kGifFunctionName,
        body: {'query': query, 'q': query, 'limit': 30},
      );
      final urls = _parseGifs(res.data);
      if (!mounted || id != _requestId) return;
      setState(() {
        _gifs = urls;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  /// Farklı GIF servislerinin cevap biçimlerini tolere eder.
  static List<String> _parseGifs(dynamic data) {
    dynamic d = data;
    if (d is String) {
      try {
        d = jsonDecode(d);
      } catch (_) {}
    }
    if (d is Map) {
      d = d['results'] ?? d['gifs'] ?? d['data'] ?? d['items'] ?? [];
    }
    if (d is! List) return [];

    final out = <String>[];
    for (final item in d) {
      final url = _extractUrl(item);
      if (url != null) out.add(url);
    }
    return out;
  }

  static String? _extractUrl(dynamic item) {
    if (item is String) return item.startsWith('http') ? item : null;
    if (item is! Map) return null;

    for (final k in ['url', 'gif', 'gif_url', 'media_url', 'src']) {
      final v = item[k];
      if (v is String && v.startsWith('http')) return v;
    }
    try {
      final v = item['images']['fixed_height']['url'];
      if (v is String && v.startsWith('http')) return v;
    } catch (_) {}
    try {
      final v = item['media_formats']['gif']['url'];
      if (v is String && v.startsWith('http')) return v;
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.7;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.inputBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                onChanged: _onChanged,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'GIF ara...',
                  hintStyle: const TextStyle(color: AppTheme.textSecondary),
                  prefixIcon:
                      const Icon(Icons.search, color: AppTheme.textSecondary),
                  filled: true,
                  fillColor: AppTheme.background,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppTheme.inputBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppTheme.inputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppTheme.primary),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('GIF\'ler yüklenemedi',
                style: TextStyle(color: AppTheme.textSecondary)),
            TextButton(
              onPressed: () => _search(_searchController.text.trim()),
              child: const Text('Tekrar dene',
                  style: TextStyle(color: AppTheme.primary)),
            ),
          ],
        ),
      );
    }
    if (_gifs.isEmpty) {
      return const Center(
        child: Text('Sonuç bulunamadı',
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _gifs.length,
      itemBuilder: (context, i) {
        final url = _gifs[i];
        return GestureDetector(
          onTap: () => Navigator.pop(context, url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(color: Colors.black.withOpacity(0.2)),
              errorWidget: (_, __, ___) => Container(
                color: Colors.black.withOpacity(0.2),
                child: const Icon(Icons.broken_image_outlined,
                    color: Colors.white54),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// "YAZIYOR" ANİMASYONU (üç nokta)
// ============================================================
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        Widget dot(int i) {
          final t = (_c.value - i * 0.2) % 1.0;
          final lift = (t < 0.5 ? t : 1 - t) * 2;
          return Transform.translate(
            offset: Offset(0, -4 * lift),
            child: Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.4 + 0.6 * lift),
                shape: BoxShape.circle,
              ),
            ),
          );
        }

        return SizedBox(
          height: 14,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [dot(0), dot(1), dot(2)],
          ),
        );
      },
    );
  }
}


// ============================================================
// SES DALGA FORMU (görsel; mesaja özgü, dokunarak ileri sarma)
// ============================================================
class _Waveform extends StatelessWidget {
  final String seed;
  final double progress;
  final Color color;
  final void Function(double)? onSeek;

  const _Waveform({
    required this.seed,
    required this.progress,
    required this.color,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      void seekAt(double dx) {
        if (onSeek == null || c.maxWidth <= 0) return;
        onSeek!((dx / c.maxWidth).clamp(0.0, 1.0));
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => seekAt(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
        child: SizedBox(
          height: 28,
          width: double.infinity,
          child: CustomPaint(
            painter: _WavePainter(seed: seed, progress: progress, color: color),
          ),
        ),
      );
    });
  }
}

class _WavePainter extends CustomPainter {
  final String seed;
  final double progress;
  final Color color;

  _WavePainter({required this.seed, required this.progress, required this.color});

  static const int _bars = 36;

  @override
  void paint(Canvas canvas, Size size) {
    final barW = size.width / _bars;
    final played = Paint()..color = color;
    final idle = Paint()..color = color.withOpacity(0.35);
    final h = seed.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);
    for (var i = 0; i < _bars; i++) {
      // Mesaja özgü, sabit ama doğal görünen yükseklikler
      final v = ((h ^ (i * 2654435761 & 0x7fffffff)) % 70 + 30) / 100.0;
      final barH = size.height * v;
      final x = i * barW + barW * 0.2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, (size.height - barH) / 2, barW * 0.6, barH),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, (i / _bars) <= progress ? played : idle);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.progress != progress || old.seed != seed || old.color != color;
}

// ============================================================
// BAĞLANTI ÖNİZLEME KARTI
// ============================================================
class _LinkPreviewCard extends StatefulWidget {
  final String url;
  final Color textColor;
  const _LinkPreviewCard({required this.url, required this.textColor});

  @override
  State<_LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<_LinkPreviewCard> {
  late final Future<Map<String, dynamic>?> _future =
      SupabaseService().linkPreview(widget.url);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        if (d == null) return const SizedBox.shrink();
        final title = (d['title'] ?? '').toString();
        final desc = (d['description'] ?? '').toString();
        final image = d['image']?.toString();
        if (title.isEmpty && image == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.url));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Bağlantı kopyalandı'),
                behavior: SnackBarBehavior.floating,
              ));
            },
            child: Container(
              width: 220,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (image != null && image.isNotEmpty)
                    Image.network(image,
                        height: 110,
                        width: 220,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title.isNotEmpty)
                          Text(title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: widget.textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        if (desc.isNotEmpty)
                          Text(desc,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: widget.textColor.withOpacity(0.8),
                                  fontSize: 12)),
                        Text((d['site'] ?? '').toString(),
                            style: TextStyle(
                                color: widget.textColor.withOpacity(0.6),
                                fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
