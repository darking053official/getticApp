import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/conversation.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import 'chat_room_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final _service = SupabaseService();
  List<Conversation> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() => _loading = true);
    final convs = await _service.getMyConversations();
    if (mounted) {
      setState(() {
        _conversations = convs;
        _loading = false;
      });
    }
  }

  Future<void> _startNewChat() async {
    final user = await showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UserSearchSheet(),
    );

    if (user != null) {
      final convId = await _service.createOrGetDirectConversation(user.id);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatRoomPage(
              conversationId: convId,
              otherUser: user,
            ),
          ),
        ).then((_) => _loadConversations());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _service.currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sohbetler'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment, color: GetticTheme.accent),
            onPressed: _startNewChat,
            tooltip: 'Yeni Sohbet',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _service.signOut();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: GetticTheme.accent))
          : _conversations.isEmpty
              ? const Center(
                  child: Text('Henüz bir sohbetin yok.\nSağ üstten yeni sohbet başlat.', 
                    textAlign: TextAlign.center, 
                    style: TextStyle(color: GetticTheme.textSecondary)
                  )
                )
              : ListView.separated(
                  itemCount: _conversations.length,
                  separatorBuilder: (_, __) => const Divider(color: GetticTheme.border, height: 1),
                  itemBuilder: (context, index) {
                    final conv = _conversations[index];
                    final other = conv.getOtherMember(myId);
                    
                    return ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatRoomPage(
                              conversationId: conv.id,
                              otherUser: other,
                            ),
                          ),
                        ).then((_) => _loadConversations());
                      },
                      leading: CircleAvatar(
                        backgroundColor: GetticTheme.accent,
                        child: Text(other.username.isNotEmpty ? other.username[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(other.username, style: const TextStyle(color: GetticTheme.textPrimary, fontWeight: FontWeight.bold)),
                      subtitle: Text('Sohbeti aç', style: TextStyle(color: GetticTheme.textSecondary)),
                    );
                  },
                ),
    );
  }
}

// Kullanıcı Arama Bottom Sheet
class UserSearchSheet extends StatefulWidget {
  const UserSearchSheet({super.key});

  @override
  State<UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<UserSearchSheet> {
  final _service = SupabaseService();
  final _searchController = TextEditingController();
  List<Profile> _results = [];
  bool _searching = false;

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    final res = await _service.searchUsers(query);
    if (mounted) {
      setState(() {
        _results = res;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: GetticTheme.bgSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: GetticTheme.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Yeni Sohbet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: GetticTheme.textPrimary)),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Kullanıcı adı ara...',
              prefixIcon: Icon(Icons.search, color: GetticTheme.textSecondary),
            ),
            onChanged: (val) {
              if (val.trim().length >= 2) _search(val.trim());
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator(color: GetticTheme.accent))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final user = _results[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: GetticTheme.accent,
                          child: Text(user.username[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(user.username, style: const TextStyle(color: GetticTheme.textPrimary)),
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
