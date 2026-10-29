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
import 'package:emoji_text_field/emoji_text_field.dart';
import 'package:open_filex/open_filex.dart';
import 'package:chewie/chewie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import 'profile_preview.dart';

// ============================================================
// ⚠️ PROJENE GÖRE KONTROL EDİLECEK 2 AYAR
// ============================================================
/// Chat medyalarının yüklendiği Supabase Storage bucket adı.
const String _kMediaBucket = 'chat-media';

/// GIF arama için kullandığın Supabase Edge Function adı.
const String _kGifFunctionName = 'search-gifs';

/// Yarım kalan mesajlar cihazda saklansın mı?
/// (SharedPreferences kullanılır, şifresizdir. Kapatmak için false yap.)
const bool _kPersistDrafts = true;

/// İmzalı URL önbelleği (süre dolmadan yenilenir).
class _CachedUrl {
  final Future<String?> future;
  final DateTime expiresAt;
  const _CachedUrl(this.future, this.expiresAt);
}

// ============================================================
// MESAJ DÜZENLEME DİYALOĞU
// Controller'ı kendi State'i yönettiği için sızıntı / "used after
// dispose" hatası olmaz.
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
          child: const Text('Kaydet',
              style: TextStyle(color: AppTheme.primary)),
        ),
      ],
    );
  }
}

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

class _ChatRoomPageState extends State<ChatRoomPage>
    with WidgetsBindingObserver {
  // ---- Sabitler (ihtiyaca göre değiştirebilirsin) ----
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

  Timer? _typingTimer;
  Timer? _typingDebounce;
  Timer? _recordTimer;

  // Aynı mesaj için tekrar tekrar "okundu" isteği atmamak için
  final Set<dynamic> _markingRead = {};
  // Storage path -> imzalı URL önbelleği
  final Map<String, _CachedUrl> _urlCache = {};
  // Mesaj id -> GlobalKey (alıntıya tıklayınca o mesaja gitmek için)
  final Map<dynamic, GlobalKey> _messageKeys = {};
  final FocusNode _inputFocus = FocusNode();
  Timer? _draftTimer;
  dynamic _highlightId;
  int _newWhileAway = 0;
  bool _isForeground = true;

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

  @override
  void initState() {
    super.initState();
    AppState().setActiveConversation(widget.conversationId);
    _subscribeToMessages();
    _subscribeToTyping();
    _setupScrollListener();
    WidgetsBinding.instance.addObserver(this);
    _loadDraft();
    _controller.addListener(_onDraftChanged);
  }

  /// Uygulama arka plandayken mesajlar "okundu" işaretlenmesin (gizlilik).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _isForeground) return;
    _isForeground = fg;
    if (fg) _markIncomingAsRead(_messages, _service.currentUser?.id);
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
            _isOtherTyping = false; // mesaj geldi, "yazıyor" bitti
            if (!wasNearBottom) _newWhileAway++;
          }
        });

        if (_firstLoad) {
          _firstLoad = false;
          _scrollToBottom(animated: false);
        } else if (hasNewLast && (wasNearBottom || lastIsMine)) {
          // Kullanıcı eski mesajları okuyorsa onu aşağı zıplatma
          _scrollToBottom();
        }

        _markIncomingAsRead(msgs, myId);
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showSnack('Mesajlar yüklenemedi: $e', isError: true);
      },
    );
  }

  void _markIncomingAsRead(List<Message> msgs, String? myId) {
    if (!_isForeground) return;
    for (final m in msgs) {
      if (m.senderId != myId && !m.isRead && _markingRead.add(m.id)) {
        _markAsRead(m);
      }
    }
  }

  Future<void> _markAsRead(Message m) async {
    try {
      await _service.markMessageAsRead(m.id, widget.conversationId);
    } catch (_) {
      // Başarısız olursa bir sonraki güncellemede tekrar denenebilsin
      _markingRead.remove(m.id);
    }
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
        _typingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _isOtherTyping = false);
        });
      },
    );
  }

  /// Input bar'daki TextField'ın onChanged'ine bağlı.
  void _onTyping(String text) {
    if (text.isEmpty) return;
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 500), () {
      _sendTypingEvent();
    });
  }

  Future<void> _sendTypingEvent() async {
    try {
      await _service.sendTypingEvent(
        widget.conversationId,
        _service.currentUser?.email?.split('@').first ?? 'Biri',
      );
    } catch (_) {
      // Yazıyor bilgisi kritik değil, sessizce geç
    }
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

    BuildContext? target = _messageKeys[id]?.currentContext;
    if (target == null) {
      // Öğe henüz çizilmemiş: yaklaşık konuma git, sonra hassas hizala
      final max = _scroll.position.maxScrollExtent;
      final denom = _messages.length > 1 ? _messages.length - 1 : 1;
      final approx = (max * idx / denom).clamp(0.0, max).toDouble();
      _scroll.jumpTo(approx);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      target = _messageKeys[id]?.currentContext;
    }

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
      if (mounted) {
        // Hem metni hem yanıt bilgisini geri yükle
        _controller.text = text;
        _controller.selection =
            TextSelection.collapsed(offset: text.length);
        setState(() => _replyTo = reply);
        _showSnack('Mesaj gönderilemedi: $e', isError: true);
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
          // TODO: Gerçek engelleme / bildirme servis çağrıları eklenmeli.
          // Şu an sadece snackbar gösteriyor.
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
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 12)),
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

  /// Yanlışlıkla gönderimi önlemek için göndermeden önce önizleme.
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
            child: const Text('Gönder',
                style: TextStyle(color: AppTheme.primary)),
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

      final path = await _storage.uploadChatMedia(
        file: file,
        conversationId: widget.conversationId,
        type: type,
      );

      if (path == null) {
        _showSnack('Medya yüklenemedi', isError: true);
        return;
      }

      await _service.sendMediaMessage(
        conversationId: widget.conversationId,
        type: type,
        mediaPath: path,
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

  // ---- Message modeli alanlarına güvenli erişim ----
  // (Model'inde alan adı farklıysa uygulama çökmez, sadece o özellik boş kalır.)
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
      final v = d.isEdited;
      return v == true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _resolveMediaUrl(String path) {
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

    // İmzalı URL 60 dk geçerli; 50 dk sonra yenilenir.
    _urlCache[path] =
        _CachedUrl(future, DateTime.now().add(const Duration(minutes: 50)));

    // Başarısız olursa 20 sn sonra tekrar denensin (sürekli istek atmasın)
    future.then((url) {
      if (url == null) {
        _urlCache[path] = _CachedUrl(
            future, DateTime.now().add(const Duration(seconds: 20)));
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
              ListTile(
                leading: const Icon(Icons.reply, color: AppTheme.primary),
                title: const Text('Yanıtla',
                    style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _startReply(msg);
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
                    final ok = await _confirmDialog(
                        'Mesajı Sil', 'Bu mesajı silmek istediğine emin misin?');
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
    if (newText == original.trim()) return; // değişiklik yok

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
            child: const Text('Sil',
                style: TextStyle(color: Colors.redAccent)),
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
    unawaited(_persistDraft(_controller.text));
    _inputFocus.dispose();
    AppState().clearActiveConversation();
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    _recordTimer?.cancel();

    // Kayıt sürerken sayfadan çıkılırsa kaydı iptal et, sonra dispose et
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
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
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
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.inputBorder),
                  ),
                  child: const Text(
                    'yazıyor...',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),

          if (_replyTo != null) _buildReplyPreview(),

          _isRecording ? _buildRecordingBar() : _buildInputBar(),
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
            onTap: _openProfilePreview,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  _isOtherTyping
                      ? 'yazıyor...'
                      : (widget.otherUser.showOnlineStatus
                          ? 'Çevrimiçi'
                          : 'Çevrimdışı'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _isOtherTyping
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                    fontStyle:
                        _isOtherTyping ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
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
              _buildQuotedReply(msg, isMine, textColor),
              _buildMessageBody(msg, isMine, textColor),
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
                    if (isMine && !msg.isDeleted) ...[
                      const SizedBox(width: 4),
                      Icon(
                        msg.isRead ? Icons.done_all : Icons.done,
                        size: 14,
                        color: msg.isRead ? Colors.lightBlueAccent : metaColor,
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

    switch (msg.type) {
      case 'image':
      case 'gif':
        return _mediaImage(msg);
      case 'video':
        return _mediaVideo(msg);
      case 'audio':
        return _mediaAudio(msg, textColor);
      case 'file':
        return _mediaFile(msg, textColor);
      default:
        return Text(
          msg.content ?? '',
          style: TextStyle(color: textColor, fontSize: 15),
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
      future: _resolveMediaUrl(path),
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
              child: CachedNetworkImage(
                imageUrl: url,
                width: 220,
                fit: BoxFit.cover,
                placeholder: (_, __) => _mediaPlaceholder(),
                errorWidget: (_, __, ___) => _mediaError(),
              ),
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
      onTap: () => _openVideo(path),
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

  Future<void> _openVideo(String path) async {
    final url = await _resolveMediaUrl(path);
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
  Future<void> _openFile(String path) async {
    final url = await _resolveMediaUrl(path);
    if (!mounted) return;
    if (url == null) {
      _showSnack('Dosya bağlantısı alınamadı', isError: true);
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
      urlLoader: () => _resolveMediaUrl(path),
      color: textColor,
    );
  }

  Widget _mediaFile(Message msg, Color textColor) {
    final path = _mediaPathOf(msg);
    if (path == null) return _mediaError();
    final name = path.split('/').last;

    return InkWell(
      onTap: () => _openFile(path),
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
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent),
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

  /// true ise sola kaydırılır (kendi mesajlarım sağda olduğu için)
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
  const _AudioPlayerTile({
    super.key,
    required this.urlLoader,
    required this.color,
  });

  @override
  State<_AudioPlayerTile> createState() => _AudioPlayerTileState();
}

class _AudioPlayerTileState extends State<_AudioPlayerTile> {
  // Aynı anda sadece tek ses çalsın
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
        await _player.setUrl(url);
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
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: widget.color,
                        inactiveTrackColor: widget.color.withOpacity(0.3),
                        thumbColor: widget.color,
                      ),
                      child: Slider(
                        value: value,
                        onChanged: _loaded && total > 0
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
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) =>
                const CircularProgressIndicator(color: AppTheme.primary),
            errorWidget: (_, __, ___) =>
                const Icon(Icons.broken_image_outlined,
                    color: Colors.white54, size: 48),
          ),
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
  VideoPlayerController? _vc;
  ChewieController? _chewie;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final vc = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _vc = vc;
    try {
      await vc.initialize();
      if (!mounted) return;
      setState(() {
        _chewie = ChewieController(
          videoPlayerController: vc,
          autoPlay: true,
          looping: false,
          allowFullScreen: true,
          allowPlaybackSpeedChanging: true,
          materialProgressColors: ChewieProgressColors(
            playedColor: AppTheme.primary,
            handleColor: AppTheme.primary,
            bufferedColor: Colors.white24,
            backgroundColor: Colors.white12,
          ),
          errorBuilder: (context, message) => const Center(
            child: Text('Video oynatılamadı',
                style: TextStyle(color: Colors.white70)),
          ),
        );
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _vc?.dispose();
    super.dispose();
  }

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
        child: _error
            ? const Text('Video oynatılamadı',
                style: TextStyle(color: Colors.white70))
            : _chewie == null
                ? const CircularProgressIndicator(color: AppTheme.primary)
                : Chewie(controller: _chewie!),
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
      // Eski (geç gelen) cevapları yok say
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

  /// Farklı GIF servislerinin (Giphy, Tenor, özel) cevap biçimlerini tolere eder.
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
      final v = item['images']['fixed_height']['url']; // Giphy
      if (v is String && v.startsWith('http')) return v;
    } catch (_) {}
    try {
      final v = item['media_formats']['gif']['url']; // Tenor v2
      if (v is String && v.startsWith('http')) return v;
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.7;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
