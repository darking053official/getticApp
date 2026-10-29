import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import 'chat_room_page.dart';
import 'settings_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});
  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage>
    with SingleTickerProviderStateMixin {
  final _service = SupabaseService();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  late TabController _tabController;

  List<Map<String, dynamic>> _allConversations = [];
  List<Map<String, dynamic>> _filteredConversations = [];
  Set<String> _pinnedIds = {};
  Set<String> _archivedIds = {};

  bool _loading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      _filterConversations(_searchController.text);
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final data = await _service.getMyConversationsWithUnread();
    if (mounted) {
      setState(() {
        _allConversations = data;
        _filterConversations(_searchController.text);
        _loading = false;
      });
    }
  }

  void _filterConversations(String query) {
    final isGroupsTab = _tabController.index == 1;

    setState(() {
      var list = _allConversations.where((c) {
        if (_archivedIds.contains(c['conversation_id'])) return false;

        final isGroup = c['is_group'] == true;
        if (isGroupsTab && !isGroup) return false;
        if (!isGroupsTab && isGroup) return false;

        if (query.isNotEmpty) {
          final user = c['other_user'];
          final username = (user?['username'] ?? '').toString().toLowerCase();
          final lastMsg = (c['last_message']?['content'] ?? '').toString().toLowerCase();
          return username.contains(query.toLowerCase()) ||
              lastMsg.contains(query.toLowerCase());
        }
        return true;
      }).toList();

      list.sort((a, b) {
        final aPinned = _pinnedIds.contains(a['conversation_id']);
        final bPinned = _pinnedIds.contains(b['conversation_id']);
        if (aPinned && !bPinned) return -1;
        if (!aPinned && bPinned) return 1;

        final aTime = a['last_message']?['created_at'] ?? '';
        final bTime = b['last_message']?['created_at'] ?? '';
        return bTime.toString().compareTo(aTime.toString());
      });

      _filteredConversations = list;
    });
  }

  Future<void> _newChat() async {
    final user = await showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UserSearchSheet(),
    );

    if (user != null) {
      final convId = await _service.createConversation(user.id);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatRoomPage(conversationId: convId, otherUser: user),
          ),
        ).then((_) => _load());
      }
    }
  }

  void _showConversationMenu(Map<String, dynamic> conv) {
    final id = conv['conversation_id'];
    final isPinned = _pinnedIds.contains(id);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
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
              leading: Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: AppTheme.primary,
              ),
              title: Text(
                isPinned ? 'Sabitlemeyi Kaldır' : 'Sohbeti Sabitle',
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
              onTap: () {
                setState(() {
                  if (isPinned) {
                    _pinnedIds.remove(id);
                  } else {
                    _pinnedIds.add(id);
                  }
                  _filterConversations(_searchController.text);
                });
                Navigator.pop(ctx);
                _snack(isPinned ? 'Sabitleme kaldırıldı' : 'Sohbet sabitlendi');
              },
            ),
            ListTile(
              leading: const Icon(Icons.done_all, color: AppTheme.online),
              title: const Text('Okundu Olarak İşaretle', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _snack('Okundu olarak işaretlendi');
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined, color: Colors.orange),
              title: const Text('Arşivle', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                setState(() {
                  _archivedIds.add(id);
                  _filterConversations(_searchController.text);
                });
                Navigator.pop(ctx);
                _snack('Sohbet arşivlendi');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Sohbeti Sil', style: TextStyle(color: Colors.redAccent)),
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

  Future<void> _confirmDelete(Map<String, dynamic> conv) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Sohbeti Sil', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'Bu sohbeti silmek istediğine emin misin? Bu işlem geri alınamaz.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _service.deleteConversation(conv['conversation_id']);
        await _load();
        _snack('Sohbet silindi');
      } catch (e) {
        _snack('Hata: $e', isError: true);
      }
    }
  }

  void _snack(String msg, {bool isError = false}) {
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

  @override
  Widget build(BuildContext context) {
    if (_currentIndex == 2) {
      return const SettingsPage();
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            _buildTabs(),
            const SizedBox(height: 8),
            Expanded(child: _buildList()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ============ HEADER ============
  Widget _buildHeader() {
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
                errorBuilder: (_, __, ___) => const Icon(Icons.message, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Gettic',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.8,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search, color: AppTheme.textSecondary, size: 26),
            onPressed: () => _searchFocus.requestFocus(),
          ),
          IconButton(
            icon: const Icon(Icons.edit_square, color: AppTheme.textSecondary, size: 26),
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
            color: _searchFocus.hasFocus ? AppTheme.primary : AppTheme.inputBorder,
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
          decoration: InputDecoration(
            hintText: 'Bir sohbet veya kişi arayın...',
            hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary, size: 22),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      _filterConversations('');
                      setState(() {});
                    },
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onChanged: (v) {
            _filterConversations(v);
            setState(() {});
          },
        ),
      ),
    );
  }

  // ============ TABS ============
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
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          tabs: const [
            Tab(text: 'Sohbetler'),
            Tab(text: 'Gruplar'),
          ],
        ),
      ),
    );
  }

  // ============ LIST ============
  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (_filteredConversations.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _filteredConversations.length,
        itemBuilder: (context, index) {
          final item = _filteredConversations[index];
          final otherUser = item['other_user'];
          final lastMsg = item['last_message'];
          final unreadCount = item['unread_count'] as int? ?? 0;
          final isPinned = _pinnedIds.contains(item['conversation_id']);

          if (otherUser == null) return const SizedBox.shrink();

          final username = otherUser['username'] ?? 'Bilinmeyen';
          final avatarUrl = otherUser['avatar_url'];
          final isOnline = otherUser['status'] == 'online' && (otherUser['show_online_status'] ?? true);
          final timeStr = lastMsg != null
              ? AppUtils.formatChatListTime(DateTime.parse(lastMsg['created_at']))
              : '';

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: unreadCount > 0 ? AppTheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatRoomPage(
                    conversationId: item['conversation_id'],
                    otherUser: Profile.fromJson(otherUser),
                  ),
                ),
              ).then((_) => _load()),
              onLongPress: () => _showConversationMenu(item),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              
              // Avatar + Online durumu + Pin ikonu
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppTheme.primary,
                    backgroundImage: avatarUrl != null
                        ? CachedNetworkImageProvider(avatarUrl)
                        : null,
                    child: avatarUrl == null
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
                      right: 0, bottom: 0,
                      child: Container(
                        width: 14, height: 14,
                        decoration: BoxDecoration(
                          color: AppTheme.online,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.background, width: 2),
                        ),
                      ),
                    ),
                  if (isPinned)
                    Positioned(
                      right: -6, top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.background, width: 2),
                        ),
                        child: const Icon(Icons.push_pin, size: 10, color: Colors.white),
                      ),
                    ),
                ],
              ),

              // Kullanıcı Adı ve Son Mesaj
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      username,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  lastMsg != null
                      ? (lastMsg['type'] == 'image'
                          ? 'Fotoğraf'
                          : lastMsg['type'] == 'video'
                              ? 'Video'
                              : lastMsg['type'] == 'audio'
                                  ? 'Sesli Mesaj'
                                  : lastMsg['type'] == 'file'
                                      ? 'Dosya'
                                      : (lastMsg['content'] ?? ''))
                      : 'Sohbeti başlatın',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: unreadCount > 0 ? AppTheme.textPrimary : AppTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),

              // Saat ve Okunmamış Sayacı
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (timeStr.isNotEmpty)
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: unreadCount > 0 ? AppTheme.primary : AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  if (unreadCount > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ============ EMPTY STATE ============
  Widget _buildEmptyState() {
    final isGroups = _tabController.index == 1;
    final isSearch = _searchController.text.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.inputBorder),
              ),
              child: Icon(
                isSearch ? Icons.search_off_rounded : isGroups ? Icons.groups_outlined : Icons.chat_bubble_outline_rounded,
                size: 56,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isSearch ? 'Sonuç Bulunamadı' : isGroups ? 'Henüz Grup Yok' : 'Henüz Sohbetiniz Yok',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isSearch
                  ? 'Farklı bir kelime ile aramayı deneyin.'
                  : isGroups
                      ? 'Yeni bir grup oluşturmak için sağ üstteki ikona dokunun.'
                      : 'Yeni bir sohbet başlatmak için sağ üstteki kalem ikonuna dokunun.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ============ BOTTOM NAV ============
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: AppTheme.inputBorder, width: 1)),
      ),
      child: BottomNavigationBar(
        backgroundColor: AppTheme.background,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: AppTheme.textSecondary,
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        iconSize: 24,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 0) _load();
        },
        items: [
          BottomNavigationBarItem(
            icon: _navIcon(Icons.chat_bubble_outline_rounded, 0),
            activeIcon: _navIcon(Icons.chat_bubble_rounded, 0),
            label: 'Sohbetler',
          ),
          BottomNavigationBarItem(
            icon: _navIcon(Icons.people_outline_rounded, 1),
            activeIcon: _navIcon(Icons.people_rounded, 1),
            label: 'Gruplar',
          ),
          BottomNavigationBarItem(
            icon: _navIcon(Icons.settings_outlined, 2),
            activeIcon: _navIcon(Icons.settings_rounded, 2),
            label: 'Ayarlar',
          ),
        ],
      ),
    );
  }

  Widget _navIcon(IconData icon, int index) {
    final active = _currentIndex == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: active ? AppTheme.primary.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(icon, color: active ? AppTheme.primary : AppTheme.textSecondary),
    );
  }
}

// ============ USER SEARCH SHEET ============
class UserSearchSheet extends StatefulWidget {
  const UserSearchSheet({super.key});
  @override
  State<UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<UserSearchSheet> {
  final _service = SupabaseService();
  final _searchController = TextEditingController();
  List<Profile> _results = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16, left: 20, right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: AppTheme.inputBorder, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Yeni Sohbet',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
            decoration: const InputDecoration(
              hintText: 'Kullanıcı adı ara...',
              prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary),
            ),
            onChanged: (v) async {
              if (v.trim().length >= 2) {
                setState(() => _isSearching = true);
                final res = await _service.searchUsers(v);
                if (mounted) {
                  setState(() {
                    _results = res;
                    _isSearching = false;
                  });
                }
              } else {
                setState(() => _results = []);
              }
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _results.isEmpty && _searchController.text.isNotEmpty
                    ? const Center(child: Text('Kullanıcı bulunamadı.', style: TextStyle(color: AppTheme.textSecondary)))
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(color: AppTheme.inputBorder, height: 1, indent: 64),
                        itemBuilder: (context, i) {
                          final user = _results[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundColor: AppTheme.primary,
                              backgroundImage: user.avatarUrl != null
                                  ? CachedNetworkImageProvider(user.avatarUrl!)
                                  : null,
                              child: user.avatarUrl == null
                                  ? Text(user.username[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18))
                                  : null,
                            ),
                            title: Text(
                              user.username,
                              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                            onTap: () => Navigator.pop(context, user),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
