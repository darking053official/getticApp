import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import 'chat_room_page.dart';
import 'settings_page.dart';

// ============================================================
// ⚠️ PROJENE GÖRE KONTROL EDİLECEK AYARLAR
// ============================================================
/// Kullanıcıların tutulduğu tablo (yeni sohbet aramasında kullanılır).
const String _kProfilesTable = 'profiles';

/// Mesajların tutulduğu tablo (liste anlık güncellensin diye dinlenir).
const String _kMessagesTable = 'messages';

/// En fazla kaç sohbet sabitlenebilir.
const int _kMaxPinned = 5;

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

  late TabController _tabController;
  late AnimationController _pulse; // yükleniyor iskeleti için

  List<Map<String, dynamic>> _allConversations = [];
  List<Map<String, dynamic>> _filteredConversations = [];
  Set<String> _pinnedIds = {};
  Set<String> _archivedIds = {};

  RealtimeChannel? _channel;
  Timer? _reloadDebounce;

  bool _loading = true;
  String? _error;
  int _currentIndex = 0; // 0: Sohbetler, 1: Arşiv, 2: Ayarlar
  int _lastTabIndex = 0;

  String get _uid => _service.currentUser?.id ?? 'anon';
  String get _pinKey => 'chatlist_pinned_$_uid';
  String get _archiveKey => 'chatlist_archived_$_uid';

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
        _filterConversations(_searchController.text);
      }
    });

    // Arama kutusunun kenarlığı odağa göre güncellensin
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });

    _init();
  }

  Future<void> _init() async {
    await _loadPrefs();
    _subscribeRealtime();
    await _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloadDebounce?.cancel();
    _channel?.unsubscribe();
    _pulse.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Uygulama öne gelince listeyi tazele.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(silent: true);
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
  // ANLIK GÜNCELLEME
  // ==========================================
  void _subscribeRealtime() {
    try {
      _channel = Supabase.instance.client
          .channel('chat_list_$_uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: _kMessagesTable,
            callback: (payload) => _scheduleReload(),
          )
          .subscribe();
    } catch (_) {
      // Realtime kurulamazsa liste yine de çekerek yenilemeyle çalışır
    }
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _load(silent: true);
    });
  }

  // ==========================================
  // VERİ
  // ==========================================
  String _idOf(Map<String, dynamic> c) => c['conversation_id'].toString();

  Future<void> _load({bool silent = false, bool toastOnError = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    }

    try {
      final data = await _service.getMyConversationsWithUnread();
      if (!mounted) return;

      // Silinmiş sohbetlerin kalıntılarını temizle
      if (data.isNotEmpty) {
        final ids = data.map((c) => _idOf(c)).toSet();
        final beforeP = _pinnedIds.length;
        final beforeA = _archivedIds.length;
        _pinnedIds.removeWhere((id) => !ids.contains(id));
        _archivedIds.removeWhere((id) => !ids.contains(id));
        if (beforeP != _pinnedIds.length || beforeA != _archivedIds.length) {
          _savePrefs();
        }
      }

      setState(() {
        _allConversations = data;
        _filteredConversations = _computeFiltered(_searchController.text);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.toString();
      });
      if (toastOnError) _snack('Yenilenemedi: $e', isError: true);
    } finally {
      if (mounted && !_loading) _pulse.stop();
    }
  }

  List<Map<String, dynamic>> _computeFiltered(String query) {
    final showArchive = _currentIndex == 1;
    final isGroupsTab = _tabController.index == 1;
    final q = query.trim().toLowerCase();

    final list = _allConversations.where((c) {
      final archived = _archivedIds.contains(_idOf(c));
      if (showArchive != archived) return false;

      if (!showArchive) {
        final isGroup = c['is_group'] == true;
        if (isGroupsTab != isGroup) return false;
      }

      if (q.isNotEmpty) {
        final user = c['other_user'];
        final username = (user?['username'] ?? '').toString().toLowerCase();
        final lastMsg =
            (c['last_message']?['content'] ?? '').toString().toLowerCase();
        return username.contains(q) || lastMsg.contains(q);
      }
      return true;
    }).toList();

    list.sort((a, b) {
      final aPinned = _pinnedIds.contains(_idOf(a));
      final bPinned = _pinnedIds.contains(_idOf(b));
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;

      final aTime = a['last_message']?['created_at'] ?? '';
      final bTime = b['last_message']?['created_at'] ?? '';
      return bTime.toString().compareTo(aTime.toString());
    });

    return list;
  }

  void _filterConversations(String query) {
    if (!mounted) return;
    setState(() => _filteredConversations = _computeFiltered(query));
  }

  int _unreadFor({required bool groups}) {
    var total = 0;
    for (final c in _allConversations) {
      if (_archivedIds.contains(_idOf(c))) continue;
      if ((c['is_group'] == true) != groups) continue;
      total += (c['unread_count'] as int?) ?? 0;
    }
    return total;
  }

  // ==========================================
  // EYLEMLER
  // ==========================================
  Future<void> _newChat() async {
    final user = await showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UserSearchSheet(),
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
      ).then((_) => _load(silent: true));
    } catch (e) {
      _snack('Sohbet başlatılamadı: $e', isError: true);
    }
  }

  void _openChat(Map<String, dynamic> item, dynamic otherUser) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomPage(
          conversationId: item['conversation_id'],
          otherUser: Profile.fromJson(otherUser),
        ),
      ),
    ).then((_) => _load(silent: true));
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
      _filteredConversations = _computeFiltered(_searchController.text);
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
        _pinnedIds.remove(id); // arşivlenen sohbet sabit kalmasın
      }
      _filteredConversations = _computeFiltered(_searchController.text);
    });
    _savePrefs();
    _snack(
      wasArchived ? 'Sohbet arşivden çıkarıldı' : 'Sohbet arşivlendi',
      actionLabel: 'Geri Al',
      onAction: () => _toggleArchive(id),
    );
  }

  Future<void> _markConversationRead(Map<String, dynamic> conv) async {
    final id = conv['conversation_id'];

    // Önce ekranda hemen güncelle
    setState(() => conv['unread_count'] = 0);

    try {
      final myId = _service.currentUser?.id;
      final msgs = await _service
          .streamMessages(id)
          .first
          .timeout(const Duration(seconds: 8));
      for (final m in msgs) {
        if (m.senderId != myId && !m.isRead) {
          await _service.markMessageAsRead(m.id, id);
        }
      }
      _snack('Okundu olarak işaretlendi');
      await _load(silent: true);
    } catch (e) {
      _snack('Hata: $e', isError: true);
      await _load(silent: true);
    }
  }

  void _showConversationMenu(Map<String, dynamic> conv) {
    final id = _idOf(conv);
    final isPinned = _pinnedIds.contains(id);
    final isArchived = _archivedIds.contains(id);
    final unread = (conv['unread_count'] as int?) ?? 0;
    final name = (conv['other_user']?['username'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
              if (name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (!isArchived)
                ListTile(
                  leading: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: AppTheme.primary,
                  ),
                  title: Text(
                    isPinned ? 'Sabitlemeyi Kaldır' : 'Sohbeti Sabitle',
                    style: const TextStyle(color: AppTheme.textPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _togglePin(id);
                  },
                ),
              if (unread > 0)
                ListTile(
                  leading: const Icon(Icons.done_all, color: AppTheme.online),
                  title: const Text('Okundu Olarak İşaretle',
                      style: TextStyle(color: AppTheme.textPrimary)),
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
                title: Text(
                  isArchived ? 'Arşivden Çıkar' : 'Arşivle',
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleArchive(id);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Sohbeti Sil',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(conv);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> conv) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Sohbeti Sil',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'Bu sohbeti silmek istediğine emin misin? Bu işlem geri alınamaz.',
          style: TextStyle(color: AppTheme.textSecondary),
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
                const Text('Sil', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        final id = _idOf(conv);
        await _service.deleteConversation(conv['conversation_id']);
        _pinnedIds.remove(id);
        _archivedIds.remove(id);
        _savePrefs();
        await _load(silent: true);
        _snack('Sohbet silindi');
      } catch (e) {
        _snack('Hata: $e', isError: true);
      }
    }
  }

  void _snack(
    String msg, {
    bool isError = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
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
          action: (actionLabel != null && onAction != null)
              ? SnackBarAction(
                  label: actionLabel,
                  textColor: Colors.white,
                  onPressed: onAction,
                )
              : null,
        ),
      );
  }

  // ==========================================
  // UI
  // ==========================================
  @override
  Widget build(BuildContext context) {
    if (_currentIndex == 2) {
      return const SettingsPage();
    }

    final archive = _currentIndex == 1;

    return PopScope(
      // Arşivdeyken geri tuşu önce sohbetlere döner
      canPop: _currentIndex == 0,
      onPopInvoked: (didPop) {
        if (!didPop && _currentIndex != 0) {
          setState(() => _currentIndex = 0);
          _filterConversations(_searchController.text);
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildSearchBar(),
              if (!archive) _buildTabs(),
              const SizedBox(height: 8),
              Expanded(child: _buildList()),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  // ============ HEADER ============
  Widget _buildHeader() {
    final archive = _currentIndex == 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Image.asset(
                'assets/logo.png',
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.message, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            archive ? 'Arşiv' : 'Gettic',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.8,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search,
                color: AppTheme.textSecondary, size: 26),
            onPressed: () => _searchFocus.requestFocus(),
          ),
          IconButton(
            icon: const Icon(Icons.edit_square,
                color: AppTheme.textSecondary, size: 26),
            onPressed: _newChat,
          ),
        ],
      ),
    );
  }

  // ============ SEARCH BAR ============
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                _searchFocus.hasFocus ? AppTheme.primary : AppTheme.inputBorder,
            width: 1.5,
          ),
          boxShadow: [
            if (_searchFocus.hasFocus)
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.1),
                blurRadius: 8,
                spreadRadius: 1,
              ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Bir sohbet veya kişi arayın...',
            hintStyle:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            prefixIcon: const Icon(Icons.search,
                color: AppTheme.textSecondary, size: 22),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close,
                        color: AppTheme.textSecondary, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      _filterConversations('');
                    },
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onChanged: (v) => _filterConversations(v),
        ),
      ),
    );
  }

  // ============ TABS ============
  Widget _tabLabel(String text, int unread) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        if (unread > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.redAccent,
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

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: AppTheme.textSecondary,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          tabs: [
            Tab(child: _tabLabel('Sohbetler', _unreadFor(groups: false))),
            Tab(child: _tabLabel('Gruplar', _unreadFor(groups: true))),
          ],
        ),
      ),
    );
  }

  // ============ LİSTE ============
  Widget _buildList() {
    if (_loading) return _buildSkeleton();

    if (_error != null && _allConversations.isEmpty) {
      return _buildMessageState(
        icon: Icons.cloud_off_outlined,
        title: 'Sohbetler yüklenemedi',
        subtitle: 'Bağlantını kontrol edip tekrar dene.',
        actionLabel: 'Tekrar Dene',
        onAction: () => _load(),
      );
    }

    if (_filteredConversations.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      onRefresh: () => _load(silent: true, toastOnError: true),
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _filteredConversations.length,
        itemBuilder: (context, index) =>
            _buildConversationTile(_filteredConversations[index]),
      ),
    );
  }

  Widget _buildSkeleton() {
    Widget bar(double? width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppTheme.surface,
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
                  color: AppTheme.surface,
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

  Widget _buildMessageState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return RefreshIndicator(
      onRefresh: () => _load(silent: true, toastOnError: true),
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon,
                        size: 44, color: AppTheme.primary.withOpacity(0.8)),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 14),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(actionLabel),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final searching = _searchController.text.trim().isNotEmpty;
    final archive = _currentIndex == 1;
    final groups = !archive && _tabController.index == 1;

    if (searching) {
      return _buildMessageState(
        icon: Icons.search_off,
        title: 'Sonuç bulunamadı',
        subtitle: '"${_searchController.text.trim()}" ile eşleşen sohbet yok.',
      );
    }
    if (archive) {
      return _buildMessageState(
        icon: Icons.archive_outlined,
        title: 'Arşiv boş',
        subtitle:
            'Bir sohbeti sola kaydırarak veya basılı tutarak arşivleyebilirsin.',
      );
    }
    if (groups) {
      return _buildMessageState(
        icon: Icons.groups_outlined,
        title: 'Henüz grup yok',
        subtitle: 'Grup sohbetleri burada görünecek.',
      );
    }
    return _buildMessageState(
      icon: Icons.chat_bubble_outline,
      title: 'Henüz sohbetin yok',
      subtitle: 'Birini arayıp ilk mesajı sen gönder.',
      actionLabel: 'Yeni Sohbet',
      onAction: _newChat,
    );
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
        return 'Sesli Mesaj';
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
          DateTime.parse(lastMsg['created_at']));
    } catch (_) {
      return '';
    }
  }

  Widget _swipeBackground({
    required Color color,
    required IconData icon,
    required Alignment alignment,
  }) {
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

  Widget _buildConversationTile(Map<String, dynamic> item) {
    final otherUser = item['other_user'];
    if (otherUser == null) return const SizedBox.shrink();

    final id = _idOf(item);
    final lastMsg = item['last_message'];
    final unreadCount = (item['unread_count'] as int?) ?? 0;
    final isPinned = _pinnedIds.contains(id);
    final isArchiveView = _currentIndex == 1;

    final username = (otherUser['username'] ?? 'Bilinmeyen').toString();
    final String? avatarUrl = otherUser['avatar_url']?.toString();
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final isOnline = otherUser['status'] == 'online' &&
        (otherUser['show_online_status'] ?? true) == true;
    final timeStr = _timeText(lastMsg);

    final isMineLast = lastMsg != null &&
        lastMsg['sender_id'] != null &&
        lastMsg['sender_id'] == _service.currentUser?.id;
    final showTick =
        isMineLast && lastMsg is Map && lastMsg.containsKey('is_read');
    final lastRead = showTick && lastMsg['is_read'] == true;
    final previewIcon = _previewIcon(lastMsg);
    final deleted = lastMsg != null && lastMsg['is_deleted'] == true;

    final subtitleColor =
        unreadCount > 0 ? AppTheme.textPrimary : AppTheme.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey('conv_$id'),
        direction: isArchiveView
            ? DismissDirection.endToStart
            : DismissDirection.horizontal,
        background: _swipeBackground(
          color: AppTheme.primary,
          icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin,
          alignment: Alignment.centerLeft,
        ),
        secondaryBackground: _swipeBackground(
          color: Colors.orange,
          icon: isArchiveView ? Icons.unarchive_outlined : Icons.archive_outlined,
          alignment: Alignment.centerRight,
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            // Sağa kaydır: sabitle / sabitlemeyi kaldır (öğe yerinde kalır)
            _togglePin(id);
            return false;
          }
          return true; // Sola kaydır: arşivle (onDismissed'da işlenir)
        },
        onDismissed: (direction) => _toggleArchive(id),
        child: Material(
          color: unreadCount > 0 ? AppTheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: () => _openChat(item, otherUser),
            onLongPress: () => _showConversationMenu(item),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),

            // Avatar + çevrimiçi durumu + sabit ikonu
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.primary,
                  backgroundImage:
                      hasAvatar ? CachedNetworkImageProvider(avatarUrl) : null,
                  child: !hasAvatar
                      ? Text(
                          username.isNotEmpty ? username[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
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
                        color: AppTheme.online,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppTheme.background, width: 2),
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
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppTheme.background, width: 2),
                      ),
                      child: const Icon(Icons.push_pin,
                          size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),

            // Kullanıcı adı
            title: Text(
              username,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight:
                    unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // Son mesaj
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (showTick && !deleted) ...[
                    Icon(
                      lastRead ? Icons.done_all : Icons.done,
                      size: 16,
                      color: lastRead
                          ? Colors.lightBlueAccent
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (previewIcon != null) ...[
                    Icon(previewIcon, size: 16, color: subtitleColor),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      (isMineLast && !showTick && !deleted ? 'Sen: ' : '') +
                          _previewText(lastMsg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 14,
                        fontStyle:
                            deleted ? FontStyle.italic : FontStyle.normal,
                        fontWeight: unreadCount > 0
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Saat ve okunmamış sayacı
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (timeStr.isNotEmpty)
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: unreadCount > 0
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: unreadCount > 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                if (unreadCount > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
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

  // ============ ALT MENÜ ============
  Widget _buildBottomNav() {
    final totalUnread = _unreadFor(groups: false) + _unreadFor(groups: true);

    return BottomNavigationBar(
      currentIndex: _currentIndex,
      backgroundColor: AppTheme.surface,
      selectedItemColor: AppTheme.primary,
      unselectedItemColor: AppTheme.textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      onTap: (i) {
        if (i == _currentIndex) return;
        setState(() {
          _currentIndex = i;
          if (i != 2) _filteredConversations = _computeFiltered(_searchController.text);
        });
      },
      items: [
        BottomNavigationBarItem(
          icon: Badge(
            isLabelVisible: totalUnread > 0,
            label: Text(totalUnread > 99 ? '99+' : '$totalUnread'),
            child: const Icon(Icons.chat_bubble_outline),
          ),
          activeIcon: Badge(
            isLabelVisible: totalUnread > 0,
            label: Text(totalUnread > 99 ? '99+' : '$totalUnread'),
            child: const Icon(Icons.chat_bubble),
          ),
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
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
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
      // % ve _ joker karakterlerini kaçır
      final safe = q.replaceAllMapped(RegExp(r'[%_\\]'), (m) => '\\${m[0]}');
      final myId = _service.currentUser?.id;

      final base = Supabase.instance.client
          .from(_kProfilesTable)
          .select()
          .ilike('username', '%$safe%');
      final rows = await (myId != null ? base.neq('id', myId) : base).limit(20);

      final profiles = rows
          .map((e) => Profile.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      // Geç gelen eski cevapları yok say
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
    final height = MediaQuery.of(context).size.height * 0.75;

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
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.inputBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Yeni Sohbet',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
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
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Kullanıcı adı ara...',
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
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _hint(String text, {IconData icon = Icons.person_search_outlined}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Arama başarısız oldu',
                style: TextStyle(color: AppTheme.textSecondary)),
            TextButton(
              onPressed: () => _search(_controller.text),
              child: const Text('Tekrar dene',
                  style: TextStyle(color: AppTheme.primary)),
            ),
          ],
        ),
      );
    }
    if (_controller.text.trim().length < 2) {
      return _hint('En az 2 harf yazarak kullanıcı ara');
    }
    if (_results.isEmpty) {
      return _hint('Kullanıcı bulunamadı', icon: Icons.search_off);
    }

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final u = _results[i];
        final hasAvatar = u.avatarUrl != null && u.avatarUrl!.isNotEmpty;
        return ListTile(
          onTap: () => Navigator.pop(context, u),
          leading: CircleAvatar(
            backgroundColor: AppTheme.primary,
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
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chat_bubble_outline,
              color: AppTheme.primary, size: 20),
        );
      },
    );
  }
}
