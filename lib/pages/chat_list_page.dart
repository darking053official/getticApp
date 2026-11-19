// ============================================================
// lib/pages/chat_list_page.dart
// (.txt olarak verildi. Projeye eklerken adını chat_list_page.dart yapın.)
//
// Performans notları:
//  - Liste bellekte önbelleğe alınır; tekrar açılınca anında gösterilir.
//  - Gelen mesaj yerel olarak uygulanır, her mesajda tüm liste çekilmez.
//  - Tam yenileme en fazla her 2,5 saniyede bir yapılır.
// ============================================================

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/profile.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import 'chat_room_page.dart';
import 'settings_page.dart';

const String _kProfilesTable = 'profiles';
const String _kMessagesTable = 'messages';
const int _kMaxPinned = 5;
const Duration _kMinReloadGap = Duration(milliseconds: 2500);

/// Bellekte tutulan liste önbelleği. Diske yazılmaz.
class ChatListCache {
  ChatListCache._();
  static final ChatListCache instance = ChatListCache._();

  List<Map<String, dynamic>>? conversations;
  String? userId;
}

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _service = SupabaseService();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  late final TabController _tabController;
  late final AnimationController _pulse;

  // Ham veri
  List<Map<String, dynamic>> _all = [];
  Set<String> _pinnedIds = {};
  Set<String> _archivedIds = {};

  // Türetilmiş veri (yalnızca _rebuildView içinde hesaplanır)
  List<Map<String, dynamic>> _view = [];
  int _unreadDirect = 0;
  int _unreadGroups = 0;

  String _query = '';
  bool _loading = true;
  String? _error;
  int _currentIndex = 0; // 0 Sohbetler, 1 Arşiv, 2 Ayarlar
  int _lastTabIndex = 0;

  RealtimeChannel? _channel;
  Timer? _reloadTimer;
  DateTime? _lastReloadAt;
  bool _loadInFlight = false;
  bool _loadQueued = false;

  String? get _uid => _service.currentUser?.id;
  String get _pinKey => 'chatlist_pinned_${_uid ?? 'anon'}';
  String get _archiveKey => 'chatlist_archived_${_uid ?? 'anon'}';

  // ==========================================
  // YAŞAM DÖNGÜSÜ
  // ==========================================
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index != _lastTabIndex) {
        _lastTabIndex = _tabController.index;
        if (mounted) setState(_rebuildView);
      }
    });

    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });

    _service.setPresence(true);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cache = ChatListCache.instance;
    if (cache.conversations != null && cache.userId == _uid) {
      _all = cache.conversations!;
      _loading = false;
      if (mounted) setState(_rebuildView);
    }

    await _loadPrefs();
    _subscribeRealtime();
    await _load(silent: _all.isNotEmpty);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloadTimer?.cancel();
    final ch = _channel;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    _pulse.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _service.setPresence(true);
      _scheduleReload();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _service.setPresence(false);
    }
  }

  // ==========================================
  // KALICI AYARLAR (sabitlenen / arşivlenen)
  // ==========================================
  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pinnedIds = (prefs.getStringList(_pinKey) ?? <String>[]).toSet();
      _archivedIds = (prefs.getStringList(_archiveKey) ?? <String>[]).toSet();
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_pinKey, _pinnedIds.toList());
      await prefs.setStringList(_archiveKey, _archivedIds.toList());
    } catch (_) {}
  }

  // ==========================================
  // CANLI GÜNCELLEME
  // ==========================================
  void _subscribeRealtime() {
    final uid = _uid;
    if (uid == null) return;
    try {
      _channel = Supabase.instance.client
          .channel('chat_list_$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: _kMessagesTable,
            callback: _onMessageChange,
          )
          .subscribe();
    } catch (_) {
      // Canlı dinleme kurulamazsa sayfa çekerek yenilenir
    }
  }

  void _onMessageChange(PostgresChangePayload payload) {
    if (!mounted) return;
    if (payload.eventType == PostgresChangeEvent.insert) {
      if (_applyInsert(payload.newRecord)) return; // bildirim: sunucu push'u gönderir
    }
    _scheduleReload();
  }

  /// Arka planda ve açık olmayan bir sohbetten gelen mesajı bildirir.
  void _notifyIfNeeded(Map<String, dynamic> rec) {
    final convId = rec['conversation_id']?.toString();
    if (convId == null || rec['sender_id']?.toString() == _uid) return;
    if (!AppState().shouldShowNotification(convId)) return;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return; // ön plandayken liste zaten güncelleniyor
    }

    Map<String, dynamic>? conv;
    for (final c in _all) {
      if (_idOf(c) == convId) {
        conv = c;
        break;
      }
    }
    final name = (conv?['other_user']?['username'] ?? 'Yeni mesaj').toString();

    final type = (rec['type'] ?? 'text').toString();
    final String body;
    if (rec['is_deleted'] == true) {
      body = 'Bu mesaj silindi';
    } else {
      switch (type) {
        case 'image':
          body = 'Fotoğraf';
          break;
        case 'video':
          body = 'Video';
          break;
        case 'audio':
        case 'voice':
          body = 'Sesli mesaj';
          break;
        case 'file':
          body = 'Dosya';
          break;
        case 'gif':
          body = 'GIF';
          break;
        default:
          body = (rec['content'] ?? '').toString();
      }
    }

    NotificationService().showMessage(
      key: rec['id'].toString(),
      title: name,
      body: body,
      payload: convId,
    );
  }

  /// Yeni mesajı ağa gitmeden listeye uygular.
  /// Liste dışında kalan (yeni) bir sohbetse false döner, tam yenileme yapılır.
  bool _applyInsert(Map<String, dynamic> rec) {
    final convId = rec['conversation_id']?.toString();
    if (convId == null) return false;

    final idx = _all.indexWhere((c) => _idOf(c) == convId);
    if (idx == -1) return false;

    final old = _all[idx];
    final isMine = rec['sender_id']?.toString() == _uid;
    final isOpen = !AppState().shouldShowNotification(convId);
    final oldUnread = (old['unread_count'] as int?) ?? 0;

    final updated = Map<String, dynamic>.from(old)
      ..['last_message'] = {
        'content': rec['content'],
        'type': rec['type'] ?? 'text',
        'created_at': rec['created_at'],
        'sender_id': rec['sender_id'],
        'is_deleted': rec['is_deleted'] ?? false,
      }
      ..['unread_count'] = (!isMine && !isOpen) ? oldUnread + 1 : oldUnread;

    final next = List<Map<String, dynamic>>.from(_all);
    next[idx] = updated;
    _all = next;
    ChatListCache.instance.conversations = _all;

    if (mounted) setState(_rebuildView);
    return true;
  }

  /// Tam yenilemeyi en fazla [_kMinReloadGap] aralıkla yapar.
  void _scheduleReload() {
    final last = _lastReloadAt;
    final wait = last == null
        ? Duration.zero
        : _kMinReloadGap - DateTime.now().difference(last);
    if (wait <= Duration.zero) {
      _load(silent: true);
      return;
    }
    _reloadTimer ??= Timer(wait, () {
      _reloadTimer = null;
      _load(silent: true);
    });
  }

  // ==========================================
  // VERİ
  // ==========================================
  String _idOf(Map<String, dynamic> c) => c['conversation_id'].toString();

  Future<void> _load({bool silent = false, bool toastOnError = false}) async {
    if (_loadInFlight) {
      _loadQueued = true;
      return;
    }
    _loadInFlight = true;

    if (!silent && mounted && _all.isEmpty) {
      setState(() => _loading = true);
    }

    try {
      final data = await _service.getMyConversationsWithUnread();
      _lastReloadAt = DateTime.now();
      if (!mounted) return;

      _pruneMissingIds(data);
      ChatListCache.instance.conversations = data;
      ChatListCache.instance.userId = _uid;

      setState(() {
        _all = data;
        _loading = false;
        _error = null;
        _rebuildView();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_all.isEmpty) _error = e.toString();
      });
      if (toastOnError) _snack('Yenilenemedi: $e', isError: true);
    } finally {
      _loadInFlight = false;
      if (_loadQueued) {
        _loadQueued = false;
        _scheduleReload();
      }
    }
  }

  /// Silinmiş sohbetlerin kalıntı işaretlerini temizler.
  void _pruneMissingIds(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return;
    final ids = data.map(_idOf).toSet();
    final beforeP = _pinnedIds.length;
    final beforeA = _archivedIds.length;
    _pinnedIds.removeWhere((id) => !ids.contains(id));
    _archivedIds.removeWhere((id) => !ids.contains(id));
    if (beforeP != _pinnedIds.length || beforeA != _archivedIds.length) {
      _savePrefs();
    }
  }

  /// Görünen listeyi ve sayaçları hesaplar. Yalnızca veri değişince çağrılmalı
  /// (setState(_rebuildView) ile). build içinde çağrılmaz.
  void _rebuildView() {
    final q = _query.trim().toLowerCase();
    final showArchive = _currentIndex == 1;
    final groupsTab = _tabController.index == 1;

    var direct = 0;
    var groups = 0;
    final list = <Map<String, dynamic>>[];

    for (final c in _all) {
      final id = _idOf(c);
      final archived = _archivedIds.contains(id);
      final isGroup = c['is_group'] == true;
      final unread = (c['unread_count'] as int?) ?? 0;

      if (!archived) {
        if (isGroup) {
          groups += unread;
        } else {
          direct += unread;
        }
      }

      if (archived != showArchive) continue;
      if (!showArchive && isGroup != groupsTab) continue;

      if (q.isNotEmpty) {
        final name =
            (c['other_user']?['username'] ?? '').toString().toLowerCase();
        final last =
            (c['last_message']?['content'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !last.contains(q)) continue;
      }
      list.add(c);
    }

    list.sort((a, b) {
      final aPinned = _pinnedIds.contains(_idOf(a));
      final bPinned = _pinnedIds.contains(_idOf(b));
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      final aTime = (a['last_message']?['created_at'] ?? '').toString();
      final bTime = (b['last_message']?['created_at'] ?? '').toString();
      return bTime.compareTo(aTime);
    });

    _view = list;
    _unreadDirect = direct;
    _unreadGroups = groups;
  }

  // ==========================================
  // EYLEMLER
  // ==========================================
  Future<void> _newChat() async {
    final user = await showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const UserSearchSheet(),
    );
    if (user == null || !mounted) return;

    try {
      final convId = await _service.createConversation(user.id);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomPage(conversationId: convId, otherUser: user),
        ),
      ).then((_) => _scheduleReload());
    } catch (e) {
      _snack('Sohbet başlatılamadı: $e', isError: true);
    }
  }

  void _openChat(Map<String, dynamic> item, dynamic otherUser) {
    final id = _idOf(item);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomPage(
          conversationId: item['conversation_id'],
          otherUser: Profile.fromJson(Map<String, dynamic>.from(otherUser)),
        ),
      ),
    ).then((_) {
      // Sohbetten dönünce sayacı hemen sıfırla, sonra sunucudan doğrula
      if (!mounted) return;
      setState(() {
        _all = _all.map((c) {
          if (_idOf(c) != id) return c;
          return Map<String, dynamic>.from(c)..['unread_count'] = 0;
        }).toList();
        _rebuildView();
      });
      ChatListCache.instance.conversations = _all;
      _scheduleReload();
    });
  }

  void _togglePin(String id) {
    final pinned = _pinnedIds.contains(id);
    if (!pinned && _pinnedIds.length >= _kMaxPinned) {
      _snack('En fazla $_kMaxPinned sohbet sabitleyebilirsin', isError: true);
      return;
    }
    setState(() {
      if (pinned) {
        _pinnedIds.remove(id);
      } else {
        _pinnedIds.add(id);
      }
      _rebuildView();
    });
    _savePrefs();
    _snack(pinned ? 'Sabitleme kaldırıldı' : 'Sohbet sabitlendi');
  }

  void _toggleArchive(String id) {
    final wasArchived = _archivedIds.contains(id);
    setState(() {
      if (wasArchived) {
        _archivedIds.remove(id);
      } else {
        _archivedIds.add(id);
        _pinnedIds.remove(id);
      }
      _rebuildView();
    });
    _savePrefs();
    _snack(
      wasArchived ? 'Sohbet arşivden çıkarıldı' : 'Sohbet arşivlendi',
      actionLabel: 'Geri al',
      onAction: () => _toggleArchive(id),
    );
  }

  Future<void> _markConversationRead(Map<String, dynamic> conv) async {
    final id = _idOf(conv);
    setState(() {
      final next = Map<String, dynamic>.from(conv)..['unread_count'] = 0;
      _all = _all.map((c) => _idOf(c) == id ? next : c).toList();
      _rebuildView();
    });
    await _service.markConversationRead(id);
    _snack('Okundu olarak işaretlendi');
    _scheduleReload();
  }

  Future<void> _confirmDelete(Map<String, dynamic> conv) async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Sohbeti sil', style: TextStyle(color: c.textPrimary)),
        content: Text(
          'Bu sohbeti silmek istediğine emin misin? Bu işlem geri alınamaz.',
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final id = _idOf(conv);
      await _service.deleteConversation(conv['conversation_id']);
      _pinnedIds.remove(id);
      _archivedIds.remove(id);
      _savePrefs();
      setState(() {
        _all = _all.where((c) => _idOf(c) != id).toList();
        _rebuildView();
      });
      ChatListCache.instance.conversations = _all;
      _snack('Sohbet silindi');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  void _showConversationMenu(Map<String, dynamic> conv) {
    final c = context.appColors;
    final id = _idOf(conv);
    final isPinned = _pinnedIds.contains(id);
    final isArchived = _archivedIds.contains(id);
    final unread = (conv['unread_count'] as int?) ?? 0;
    final name = (conv['other_user']?['username'] ?? '').toString();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (name.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            if (!isArchived)
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: c.primary,
                ),
                title: Text(
                    isPinned ? 'Sabitlemeyi kaldır' : 'Sohbeti sabitle',
                    style: TextStyle(color: c.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePin(id);
                },
              ),
            if (unread > 0)
              ListTile(
                leading: Icon(Icons.done_all, color: c.online),
                title: Text('Okundu olarak işaretle',
                    style: TextStyle(color: c.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _markConversationRead(conv);
                },
              ),
            ListTile(
              leading: Icon(
                isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                color: Colors.orange,
              ),
              title: Text(isArchived ? 'Arşivden çıkar' : 'Arşivle',
                  style: TextStyle(color: c.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _toggleArchive(id);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.danger),
              title: Text('Sohbeti sil', style: TextStyle(color: c.danger)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(conv);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _snack(String msg,
      {bool isError = false, String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    final c = context.appColors;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? c.danger : c.primary,
        behavior: SnackBarBehavior.floating,
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ));
  }

  // ==========================================
  // UI
  // ==========================================
  @override
  Widget build(BuildContext context) {
    if (_currentIndex == 2) {
      return SettingsPage(
        onBack: () => setState(() {
          _currentIndex = 0;
          _rebuildView();
        }),
      );
    }

    final c = context.appColors;
    final archive = _currentIndex == 1;

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvoked: (didPop) {
        if (!didPop && _currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
            _rebuildView();
          });
        }
      },
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(c, archive),
              _buildSearchBar(c),
              if (!archive) _buildTabs(c),
              const SizedBox(height: 8),
              Expanded(child: _buildList(c)),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNav(c),
      ),
    );
  }

  Widget _buildHeader(AppColors c, bool archive) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.surface,
              shape: BoxShape.circle,
              border: Border.all(color: c.border),
            ),
            child: Image.asset(
              'assets/logo.png',
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.message, color: c.primary),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            archive ? 'Arşiv' : 'Gettic',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.8,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Ara',
            icon: Icon(Icons.search, color: c.textSecondary, size: 26),
            onPressed: () => _searchFocus.requestFocus(),
          ),
          IconButton(
            tooltip: 'Yeni sohbet',
            icon: Icon(Icons.edit_square, color: c.textSecondary, size: 26),
            onPressed: _newChat,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _searchFocus.hasFocus ? c.primary : c.border,
            width: 1.5,
          ),
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          style: TextStyle(color: c.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Sohbet veya kişi ara...',
            hintStyle: TextStyle(color: c.textHint, fontSize: 14),
            prefixIcon: Icon(Icons.search, color: c.textSecondary, size: 22),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close, color: c.textSecondary, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _query = '';
                        _rebuildView();
                      });
                    },
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onChanged: (v) => setState(() {
            _query = v;
            _rebuildView();
          }),
        ),
      ),
    );
  }

  Widget _tabLabel(AppColors c, String text, int unread) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        if (unread > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: c.danger,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unread > 99 ? '99+' : '$unread',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTabs(AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: c.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: c.textSecondary,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          tabs: [
            Tab(child: _tabLabel(c, 'Sohbetler', _unreadDirect)),
            Tab(child: _tabLabel(c, 'Gruplar', _unreadGroups)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(AppColors c) {
    if (_loading && _all.isEmpty) return _buildSkeleton(c);

    if (_error != null && _all.isEmpty) {
      return _buildMessageState(
        c,
        icon: Icons.cloud_off_outlined,
        title: 'Sohbetler yüklenemedi',
        subtitle: 'Bağlantını kontrol edip tekrar dene.',
        actionLabel: 'Tekrar dene',
        onAction: () => _load(),
      );
    }

    if (_view.isEmpty) return _buildEmptyState(c);

    return RefreshIndicator(
      onRefresh: () => _load(silent: true, toastOnError: true),
      color: c.primary,
      backgroundColor: c.surface,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _view.length,
        itemBuilder: (_, i) => _buildConversationTile(c, _view[i]),
      ),
    );
  }

  Widget _buildSkeleton(AppColors c) {
    Widget bar(double? width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: c.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
        );

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: 8,
      itemBuilder: (_, __) => FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_pulse),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: c.surfaceVariant,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(140, 14),
                    const SizedBox(height: 10),
                    bar(null, 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageState(
    AppColors c, {
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Icon(icon, size: 44, color: c.primary.withOpacity(0.8)),
                const SizedBox(height: 16),
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textSecondary, fontSize: 14)),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: onAction,
                    child: Text(actionLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(AppColors c) {
    final searching = _query.trim().isNotEmpty;
    final archive = _currentIndex == 1;
    final groups = !archive && _tabController.index == 1;

    if (searching) {
      return _buildMessageState(c,
          icon: Icons.search_off,
          title: 'Sonuç bulunamadı',
          subtitle: '"${_query.trim()}" ile eşleşen sohbet yok.');
    }
    if (archive) {
      return _buildMessageState(c,
          icon: Icons.archive_outlined,
          title: 'Arşiv boş',
          subtitle: 'Bir sohbeti sola kaydırarak arşivleyebilirsin.');
    }
    if (groups) {
      return _buildMessageState(c,
          icon: Icons.groups_outlined,
          title: 'Henüz grup yok',
          subtitle: 'Grup sohbetleri burada görünecek.');
    }
    return _buildMessageState(c,
        icon: Icons.chat_bubble_outline,
        title: 'Henüz sohbetin yok',
        subtitle: 'Birini arayıp ilk mesajı sen gönder.',
        actionLabel: 'Yeni sohbet',
        onAction: _newChat);
  }

  // ---- Son mesaj önizlemesi ----
  IconData? _previewIcon(dynamic lastMsg) {
    if (lastMsg == null || lastMsg['is_deleted'] == true) return null;
    switch (lastMsg['type']) {
      case 'image':
        return Icons.photo_outlined;
      case 'video':
        return Icons.videocam_outlined;
      case 'audio':
      case 'voice':
        return Icons.mic_none;
      case 'file':
        return Icons.insert_drive_file_outlined;
      case 'gif':
        return Icons.gif_box_outlined;
      default:
        return null;
    }
  }

  String _previewText(dynamic lastMsg) {
    if (lastMsg == null) return 'Sohbeti başlatın';
    if (lastMsg['is_deleted'] == true) return 'Bu mesaj silindi';
    switch (lastMsg['type']) {
      case 'image':
        return 'Fotoğraf';
      case 'video':
        return 'Video';
      case 'audio':
      case 'voice':
        return 'Sesli mesaj';
      case 'file':
        return 'Dosya';
      case 'gif':
        return 'GIF';
      default:
        return (lastMsg['content'] ?? '').toString();
    }
  }

  String _timeText(dynamic lastMsg) {
    if (lastMsg == null) return '';
    try {
      return AppUtils.formatChatListTime(
          DateTime.parse(lastMsg['created_at'].toString()));
    } catch (_) {
      return '';
    }
  }

  Widget _swipeBackground(AppColors c,
      {required Color color,
      required IconData icon,
      required Alignment alignment}) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }

  Widget _buildConversationTile(AppColors c, Map<String, dynamic> item) {
    final otherUser = item['other_user'];
    if (otherUser == null) return const SizedBox.shrink();

    final id = _idOf(item);
    final lastMsg = item['last_message'];
    final unread = (item['unread_count'] as int?) ?? 0;
    final isPinned = _pinnedIds.contains(id);
    final isArchiveView = _currentIndex == 1;

    final username = (otherUser['username'] ?? 'Bilinmeyen').toString();
    final avatarUrl = otherUser['avatar_url']?.toString();
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final isOnline = otherUser['status'] == 'online' &&
        (otherUser['show_online_status'] ?? true) == true;
    final timeStr = _timeText(lastMsg);
    final deleted = lastMsg != null && lastMsg['is_deleted'] == true;

    final isMineLast = lastMsg != null &&
        lastMsg['sender_id'] != null &&
        lastMsg['sender_id'] == _uid;
    final previewIcon = _previewIcon(lastMsg);
    final subtitleColor = unread > 0 ? c.textPrimary : c.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey('conv_$id'),
        direction: isArchiveView
            ? DismissDirection.endToStart
            : DismissDirection.horizontal,
        background: _swipeBackground(c,
            color: c.primary,
            icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            alignment: Alignment.centerLeft),
        secondaryBackground: _swipeBackground(c,
            color: Colors.orange,
            icon: isArchiveView
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
            alignment: Alignment.centerRight),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            _togglePin(id);
            return false; // sabitleme sonrası öğe yerinde kalır
          }
          return true;
        },
        onDismissed: (_) => _toggleArchive(id),
        child: Material(
          color: unread > 0 ? c.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: () => _openChat(item, otherUser),
            onLongPress: () => _showConversationMenu(item),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: c.primary,
                  backgroundImage:
                      hasAvatar ? CachedNetworkImageProvider(avatarUrl) : null,
                  child: !hasAvatar
                      ? Text(
                          username.isNotEmpty ? username[0].toUpperCase() : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: c.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.background, width: 2),
                      ),
                    ),
                  ),
                if (isPinned)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: c.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.background, width: 2),
                      ),
                      child: const Icon(Icons.push_pin,
                          size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
            title: Text(
              username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w600,
                fontSize: 16,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (previewIcon != null) ...[
                    Icon(previewIcon, size: 16, color: subtitleColor),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      (isMineLast && !deleted ? 'Sen: ' : '') +
                          _previewText(lastMsg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 14,
                        fontStyle:
                            deleted ? FontStyle.italic : FontStyle.normal,
                        fontWeight:
                            unread > 0 ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (timeStr.isNotEmpty)
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: unread > 0 ? c.primary : c.textSecondary,
                      fontSize: 12,
                      fontWeight:
                          unread > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                if (unread > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav(AppColors c) {
    final total = _unreadDirect + _unreadGroups;
    Widget badge(Widget icon) => Badge(
          isLabelVisible: total > 0,
          label: Text(total > 99 ? '99+' : '$total'),
          child: icon,
        );

    return BottomNavigationBar(
      currentIndex: _currentIndex,
      backgroundColor: c.surface,
      selectedItemColor: c.primary,
      unselectedItemColor: c.textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      onTap: (i) {
        if (i == _currentIndex) return;
        setState(() {
          _currentIndex = i;
          _rebuildView();
        });
      },
      items: [
        BottomNavigationBarItem(
          icon: badge(const Icon(Icons.chat_bubble_outline)),
          activeIcon: badge(const Icon(Icons.chat_bubble)),
          label: 'Sohbetler',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.archive_outlined),
          activeIcon: Icon(Icons.archive),
          label: 'Arşiv',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: 'Ayarlar',
        ),
      ],
    );
  }
}

// ============================================================
// YENİ SOHBET: KULLANICI ARAMA
// ============================================================
class UserSearchSheet extends StatefulWidget {
  const UserSearchSheet({super.key});

  @override
  State<UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<UserSearchSheet> {
  final _service = SupabaseService();
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Profile> _results = [];
  bool _loading = false;
  bool _error = false;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    final id = ++_requestId;

    if (q.length < 2) {
      setState(() {
        _results = [];
        _loading = false;
        _error = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = false;
    });

    try {
      final safe = q.replaceAllMapped(RegExp(r'[%_\\]'), (m) => '\\${m[0]}');
      final myId = _service.currentUser?.id;
      final base = Supabase.instance.client
          .from(_kProfilesTable)
          .select()
          .ilike('username', '%$safe%');
      final rows =
          await (myId != null ? base.neq('id', myId) : base).limit(20);

      final profiles = rows
          .map((e) => Profile.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      if (!mounted || id != _requestId) return;
      setState(() {
        _results = profiles;
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

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final height = MediaQuery.of(context).size.height * 0.75;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Yeni sohbet',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                decoration: const InputDecoration(
                  hintText: 'Kullanıcı adı ara...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(child: _buildBody(c)),
          ],
        ),
      ),
    );
  }

  Widget _hint(AppColors c, String text,
      {IconData icon = Icons.person_search_outlined}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: c.textSecondary),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildBody(AppColors c) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: c.primary));
    }
    if (_error) {
      return Center(
        child: TextButton(
          onPressed: () => _search(_controller.text),
          child: const Text('Arama başarısız. Tekrar dene'),
        ),
      );
    }
    if (_controller.text.trim().length < 2) {
      return _hint(c, 'En az 2 harf yazarak kullanıcı ara');
    }
    if (_results.isEmpty) {
      return _hint(c, 'Kullanıcı bulunamadı', icon: Icons.search_off);
    }

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final u = _results[i];
        final hasAvatar = u.avatarUrl != null && u.avatarUrl!.isNotEmpty;
        return ListTile(
          onTap: () => Navigator.pop(context, u),
          leading: CircleAvatar(
            backgroundColor: c.primary,
            backgroundImage:
                hasAvatar ? CachedNetworkImageProvider(u.avatarUrl!) : null,
            child: !hasAvatar
                ? Text(
                    u.username.isNotEmpty ? u.username[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          title: Text(u.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.textPrimary, fontWeight: FontWeight.w600)),
          trailing: Icon(Icons.chat_bubble_outline, color: c.primary, size: 20),
        );
      },
    );
  }
}
