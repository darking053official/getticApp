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

class _ChatListPageState extends State<ChatListPage> {
  final _service = SupabaseService();
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final data = await _service.getMyConversationsWithUnread();
    if (mounted) {
      setState(() {
        _conversations = data;
        _loading = false;
      });
    }
  }

  Future<void> _newChat() async {
    final user = await showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UserSearchSheet(),
    );
    
    if (user != null) {
      // Servis fonksiyon ismi ile uyumlu hale getirildi
      final convId = await _service.createConversation(user.id);
      if (mounted) {
        Navigator.push(
          context, 
          MaterialPageRoute(
            builder: (_) => ChatRoomPage(conversationId: convId, otherUser: user)
          )
        ).then((_) => _load());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Gettic'),
        backgroundColor: AppTheme.background,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: AppTheme.primary), 
            onPressed: _newChat
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined), 
            onPressed: () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (_) => const SettingsPage())
            ).then((_) => _load())
          ),
        ],
      ),
      body: _loading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary)) 
        : _conversations.isEmpty 
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _conversations.length,
                separatorBuilder: (_, __) => const Divider(color: AppTheme.inputBorder, height: 1, indent: 80),
                itemBuilder: (context, index) {
                  final item = _conversations[index];
                  final otherUser = item['other_user'];
                  final lastMsg = item['last_message'];
                  final unreadCount = item['unread_count'] as int? ?? 0;

                  if (otherUser == null) return const SizedBox.shrink();

                  final isOnline = otherUser['status'] == 'online' && (otherUser['show_online_status'] ?? true);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    onTap: () => Navigator.push(
                      context, 
                      MaterialPageRoute(
                        builder: (_) => ChatRoomPage(
                          conversationId: item['conversation_id'], 
                          otherUser: Profile.fromJson(otherUser)
                        )
                      )
                    ).then((_) => _load()),
                    
                    // Avatar ve Online Durum Noktası
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppTheme.primary,
                          backgroundImage: otherUser['avatar_url'] != null 
                              ? CachedNetworkImageProvider(otherUser['avatar_url']) 
                              : null,
                          child: otherUser['avatar_url'] == null
                              ? Text(
                                  otherUser['username'][0].toUpperCase(), 
                                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)
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
                                color: const Color(0xFF22c55e), // Yeşil online rengi
                                shape: BoxShape.circle, 
                                border: Border.all(color: AppTheme.background, width: 2)
                              )
                            )
                          ),
                      ],
                    ),
                    
                    // Kullanıcı Adı
                    title: Text(
                      otherUser['username'], 
                      style: const TextStyle(
                        color: AppTheme.textPrimary, 
                        fontWeight: FontWeight.w600,
                        fontSize: 16
                      )
                    ),
                    
                    // Son Mesaj Önizlemesi
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        lastMsg != null 
                            ? AppUtils.truncateMessage(lastMsg['content'] ?? '') 
                            : 'Sohbeti başlatın...', 
                        style: TextStyle(
                          color: unreadCount > 0 ? AppTheme.textPrimary : AppTheme.textSecondary, 
                          fontSize: 13,
                          fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    // Saat ve Okunmamış Badge
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (lastMsg != null)
                          Text(
                            AppUtils.formatChatListTime(DateTime.parse(lastMsg['created_at'])),
                            style: TextStyle(
                              color: unreadCount > 0 ? AppTheme.primary : AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal
                            ),
                          ),
                        if (unreadCount > 0) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : unreadCount.toString(),
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  // Boş Durum Ekranı
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 80, color: AppTheme.surface),
          const SizedBox(height: 16),
          const Text(
            'Henüz sohbetiniz yok.',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Yeni bir sohbet başlatmak için sağ üstteki ikona dokunun.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ==========================================
// KULLANICI ARAMA MODALI (BOTTOM SHEET)
// ==========================================
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))
      ),
      padding: EdgeInsets.only(
        top: 16, 
        left: 16, 
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16
      ),
      child: Column(
        children: [
          // Sürükleme Çubuğu
          Container(
            width: 40, 
            height: 4, 
            decoration: BoxDecoration(
              color: AppTheme.inputBorder, 
              borderRadius: BorderRadius.circular(2)
            )
          ),
          const SizedBox(height: 20),
          const Text(
            'Yeni Sohbet', 
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)
          ),
          const SizedBox(height: 16),
          
          // Arama Alanı
          TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Kullanıcı adı ara...', 
              prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary)
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
          
          // Sonuç Listesi
          Expanded(
            child: _isSearching
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _results.isEmpty && _searchController.text.isNotEmpty
                ? const Center(child: Text('Kullanıcı bulunamadı.', style: TextStyle(color: AppTheme.textSecondary)))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final user = _results[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primary, 
                          backgroundImage: user.avatarUrl != null ? CachedNetworkImageProvider(user.avatarUrl!) : null,
                          child: user.avatarUrl == null 
                              ? Text(user.username[0].toUpperCase(), style: const TextStyle(color: Colors.white))
                              : null,
                        ),
                        title: Text(user.username, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
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
