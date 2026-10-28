import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';

class NewGroupPage extends StatefulWidget {
  const NewGroupPage({super.key});

  @override
  State<NewGroupPage> createState() => _NewGroupPageState();
}

class _NewGroupPageState extends State<NewGroupPage> {
  final _service = SupabaseService();
  final _groupNameController = TextEditingController();
  final _searchController = TextEditingController();

  List<Profile> _searchResults = [];
  final Set<String> _selectedUserIds = {};
  final Map<String, Profile> _selectedUsers = {}; // ID -> Profile eşleşmesi

  bool _isSearching = false;
  bool _isCreating = false;

  @override
  void dispose() {
    _groupNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isSearching = true);
    final results = await _service.searchUsers(query);
    
    if (mounted) {
      setState(() {
        // Zaten seçilmiş olanları arama sonuçlarından çıkar
        _searchResults = results.where((u) => !_selectedUserIds.contains(u.id)).toList();
        _isSearching = false;
      });
    }
  }

  void _toggleUserSelection(Profile user) {
    setState(() {
      if (_selectedUserIds.contains(user.id)) {
        _selectedUserIds.remove(user.id);
        _selectedUsers.remove(user.id);
      } else {
        _selectedUserIds.add(user.id);
        _selectedUsers[user.id] = user;
      }
      // Seçilen kullanıcıyı arama sonuçlarından kaldır
      _searchResults.removeWhere((u) => u.id == user.id);
    });
  }

  void _removeSelectedUser(String userId) {
    setState(() {
      _selectedUserIds.remove(userId);
      _selectedUsers.remove(userId);
    });
  }

  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();
    
    if (groupName.isEmpty) {
      _snack('Lütfen bir grup adı girin', isError: true);
      return;
    }
    
    if (_selectedUserIds.isEmpty) {
      _snack('Lütfen en az bir üye seçin', isError: true);
      return;
    }

    setState(() => _isCreating = true);

    try {
      final currentUserId = _service.currentUser?.id;
      if (currentUserId == null) throw Exception('Kullanıcı girişi yapılmamış.');

      // 1. Grubu oluştur
      final convId = await _service.createGroupConversation(
        groupName: groupName,
        memberIds: _selectedUserIds.toList(),
      );

      if (mounted) {
        _snack('Grup başarıyla oluşturuldu');
        // Grup oluşturulduktan sonra geri dön (veya sohbete yönlendir)
        Navigator.pop(context, convId); 
      }
    } catch (e) {
      if (mounted) {
        _snack('Grup oluşturulamadı: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Yeni Grup'),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createGroup,
            child: _isCreating
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
                : const Text(
                    'Oluştur',
                    style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // --- GRUP ADI GİRİŞİ ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _groupNameController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                    decoration: const InputDecoration(
                      hintText: 'Grup Adı',
                      hintStyle: TextStyle(color: AppTheme.textSecondary),
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.inputBorder),
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.inputBorder),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.primary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(color: AppTheme.inputBorder, height: 1),

          // --- SEÇİLEN ÜYELER (CHIPS) ---
          if (_selectedUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedUsers.values.map((user) {
                  return Chip(
                    avatar: CircleAvatar(
                      backgroundColor: AppTheme.primary,
                      backgroundImage: user.avatarUrl != null
                          ? CachedNetworkImageProvider(user.avatarUrl!)
                          : null,
                      child: user.avatarUrl == null
                          ? Text(user.username[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10))
                          : null,
                    ),
                    label: Text(user.username, style: const TextStyle(color: AppTheme.textPrimary)),
                    backgroundColor: AppTheme.surface,
                    side: const BorderSide(color: AppTheme.inputBorder),
                    deleteIcon: const Icon(Icons.close, size: 16, color: AppTheme.textSecondary),
                    onDeleted: () => _removeSelectedUser(user.id),
                  );
                }).toList(),
              ),
            ),

          // --- KULLANICI ARAMA ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Kullanıcı ara...',
                prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary),
              ),
              onChanged: _searchUsers,
            ),
          ),

          // --- ARAMA SONUÇLARI / KULLANICI LİSTESİ ---
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _searchResults.isEmpty && _searchController.text.isNotEmpty
                    ? const Center(child: Text('Kullanıcı bulunamadı.', style: TextStyle(color: AppTheme.textSecondary)))
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primary,
                              backgroundImage: user.avatarUrl != null
                                  ? CachedNetworkImageProvider(user.avatarUrl!)
                                  : null,
                              child: user.avatarUrl == null
                                  ? Text(user.username[0].toUpperCase(), style: const TextStyle(color: Colors.white))
                                  : null,
                            ),
                            title: Text(user.username, style: const TextStyle(color: AppTheme.textPrimary)),
                            onTap: () => _toggleUserSelection(user),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
