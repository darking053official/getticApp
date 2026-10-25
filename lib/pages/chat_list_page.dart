import 'dart:async';
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
  bool _isSearching = false;
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
    // Grup sekmesinde mi?
    final isGroupsTab = _tabController.index == 1;

    setState(() {
      var list = _allConversations.where((c) {
        // Arşivlenmişleri gizle
        if (_archivedIds.contains(c['conversation_id'])) return false;

        // Grup filtresi
        final isGroup = c['is_group'] == true;
        if (isGroupsTab && !isGroup) return false;
        if (!isGroupsTab && isGroup) return false;

        // Arama filtresi
        if (query.isNotEmpty) {
          final user = c['other_user'];
          final username = (user?['username'] ?? '').toString().toLowerCase();
          final lastMsg =
              (c['last_message']?['content'] ?? '').toString().toLowerCase();
          return username.contains(query.toLowerCase()) ||
              lastMsg.contains(query.toLowerCase());
        }
        return true;
      }).toList();

      // Sabitlenenler önce, sonra tarihe göre
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
            builder: (_) =>
                ChatRoomPage(conversationId: convId, otherUser: user),
          ),
        ).then((_) => _load());
      }
    }
  }

  // Uzun basınca menü
  void _showConversationMenu(Map<String, dynamic> conv) {
    final id = conv['conversation_id'];
    final isPinned = _pinnedIds.contains(id);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              title: const Text(
                'Okundu Olarak İşaretle',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _snack('Okundu olarak işaretlendi');
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined, color: Colors.orange),
              title: const Text(
                'Arşivle',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
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
              title: const Text(
                'Sohbeti Sil',
                style: TextStyle(color: Colors.redAccent),
              ),
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
            const SizedBox(height: 4),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
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
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(5.0),
              child: Image.asset(
                'assets/logo.png',
                errorBuilder: (_, __, ___) => const Icon(Icons.message,
                    color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 10),
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
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search, color: AppTheme.textSecondary),
              onPressed: () {
                setState(() => _isSearching = true);
                Future.delayed(const Duration(milliseconds: 100),
                    () => _searchFocus.requestFocus());
              },
            ),
          IconButton(
            icon: const Icon(Icons.edit_square, color: AppTheme.textSecondary),
            onPressed: _newChat,
          ),
        ],
      ),
    );
  }

  // ============ SEARCH BAR ============
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _searchFocus.hasFocus
                ? AppTheme.primary
                : AppTheme.inputBorder,
            width: _searchFocus.hasFocus ? 1.5 : 1,
          ),
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          onChanged: (v) {
            _filterConversations(v);
            setState(() {});
          },
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Bir sohbet veya kişi arayın...',
            hintStyle:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            prefixIcon: const Icon(Icons.search,
                color: AppTheme.textSecondary, size: 20),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close,
                        color: AppTheme.textSecondary, size: 18),
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
        ),
      ),
    );
  }

  // ============ TABS ============
  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: AppTheme.textSecondary,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          tabs: const [
            Tab(text: 'Tümü'),
            Tab(text: 'Gruplar'),
          ],
        ),
      ),
    );
  }

  // ============ LIST ============
  Widget _buildList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_filteredConversations.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          final isOnline = otherUser['status'] == 'online' &&
              (otherUser['show_online_status'] ?? true);
          final timeStr = lastMsg != null
              ? AppUtils.formatChatListTime(
                  DateTime.parse(lastMsg['created_at']))
              : '';

          return InkWell(
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
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  // Avatar + Online dot + Pin badge
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: avatarUrl != null ? null : AppTheme.primary,
                          image: avatarUrl != null
                              ? DecorationImage(
                                  image:
                                      CachedNetworkImageProvider(avatarUrl),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: avatarUrl == null
                            ? Center(
                                child: Text(
                                  username.isNotEmpty
                                      ? username[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                  ),
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
                              border: Border.all(
                                  color: AppTheme.background, width: 2),
                            ),
                          ),
                        ),
                      if (isPinned)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppTheme.background, width: 1.5),
                            ),
                            child: const Icon(Icons.push_pin,
                                size: 9, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Name + Message
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lastMsg != null
                              ? (lastMsg['content'] ?? '📎 Medya')
                              : 'Sohbeti başlatın',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unreadCount > 0
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Time + Badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: TextStyle(
                            color: unreadCount > 0
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      if (unreadCount > 0) ...[
                        const SizedBox(height: 6),
                        _UnreadBadge(count: unreadCount),
                      ],
                    ],
                  ),
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
                isSearch
                    ? Icons.search_off_rounded
                    : isGroups
                        ? Icons.groups_outlined
                        : Icons.chat_bubble_outline_rounded,
                size: 56,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isSearch
                  ? 'Sonuç bulunamadı'
                  : isGroups
                      ? 'Henüz grup yok'
                      : 'Henüz sohbetiniz yok',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSearch
                  ? 'Farklı bir kelime deneyin'
                  : isGroups
                      ? 'Gruplar yakında eklenecek'
                      : 'Yeni bir sohbet başlatmak için sağ üstteki kalem ikonuna dokunun',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            if (!isSearch && !isGroups) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _newChat,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Sohbet Başlat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? AppTheme.primary.withOpacity(0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(icon),
    );
  }
}

// ============ UNREAD BADGE (Pulse animasyonlu) ============
class _UnreadBadge extends StatefulWidget {
  final int count;
  const _UnreadBadge({required this.count});
  @override
  State<_UnreadBadge> createState() => _UnreadBadgeState();
}

class _UnreadBadgeState extends State<_UnreadBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        constraints: const BoxConstraints(minWidth: 22),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          widget.count > 99 ? '99+' : widget.count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
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
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.inputBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Yeni Sohbet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Kullanıcı adı ara...',
              prefixIcon:
                  Icon(Icons.search, color: AppTheme.textSecondary),
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
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppTheme.primary))
                : _results.isEmpty && _searchController.text.isNotEmpty
                    ? const Center(
                        child: Text(
                          'Kullanıcı bulunamadı.',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final user = _results[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primary,
                              backgroundImage: user.avatarUrl != null
                                  ? CachedNetworkImageProvider(
                                      user.avatarUrl!)
                                  : null,
                              child: user.avatarUrl == null
                                  ? Text(
                                      user.username[0].toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.white),
                                    )
                                  : null,
                            ),
                            title: Text(
                              user.username,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
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
