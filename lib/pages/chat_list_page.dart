import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import 'chat_page.dart';
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
    setState(() => _loading = true);
    final data = await _service.getMyConversationsWithUnread();
    if (mounted) setState(() { _conversations = data; _loading = false; });
  }

  Future<void> _newChat() async {
    final user = await showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UserSearchSheet(),
    );
    if (user != null) {
      final convId = await _service.createOrGetDirectConversation(user.id);
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversationId: convId, otherUser: user))).then((_) => _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _service.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gettic'),
        actions: [
          IconButton(icon: const Icon(Icons.add_comment, color: GetticTheme.accent), onPressed: _newChat),
          IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())).then((_) => _load())),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator(color: GetticTheme.accent)) 
      : _conversations.isEmpty ? const Center(child: Text('Sohbet yok. Sağ üstten başlat.', style: TextStyle(color: GetticTheme.textSecondary)))
      : ListView.separated(
          itemCount: _conversations.length,
          separatorBuilder: (_, __) => const Divider(color: GetticTheme.border, height: 1),
          itemBuilder: (context, index) {
            final item = _conversations[index];
            final conv = item['conversations'];
            final members = conv['conversation_members'] as List;
            final other = members.firstWhere((m) => m['user_id'] != myId)['profiles'];
            
            final isOnline = other['status'] == 'online' && (other['show_online_status'] ?? true);
            
            return ListTile(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversationId: conv['id'], otherUser: Profile.fromJson(other)))).then((_) => _load()),
              leading: Stack(
                children: [
                  CircleAvatar(backgroundColor: GetticTheme.accent, child: Text(other['username'][0].toUpperCase(), style: const TextStyle(color: Colors.white))),
                  if (isOnline) Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: GetticTheme.online, shape: BoxShape.circle, border: Border.all(color: GetticTheme.bgSecondary, width: 2)))),
                ],
              ),
              title: Text(other['username'], style: const TextStyle(color: GetticTheme.textPrimary, fontWeight: FontWeight.bold)),
              subtitle: Text(conv['type'] == 'group' ? 'Grup' : 'Birebir Sohbet', style: const TextStyle(color: GetticTheme.textSecondary)),
            );
          },
        ),
    );
  }
}

// Kullanıcı Arama Sheet
class UserSearchSheet extends StatefulWidget {
  const UserSearchSheet({super.key});
  @override
  State<UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<UserSearchSheet> {
  final _service = SupabaseService();
  final _searchController = TextEditingController();
  List<Profile> _results = [];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(color: GetticTheme.bgSecondary, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
            decoration: const InputDecoration(hintText: 'Kullanıcı ara...', prefixIcon: Icon(Icons.search)),
            onChanged: (v) async {
              if (v.length >= 2) {
                final res = await _service.searchUsers(v);
                setState(() => _results = res);
              }
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) => ListTile(
                leading: CircleAvatar(backgroundColor: GetticTheme.accent, child: Text(_results[i].username[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
                title: Text(_results[i].username, style: const TextStyle(color: GetticTheme.textPrimary)),
                onTap: () => Navigator.pop(context, _results[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
