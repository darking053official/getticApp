import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import '../models/conversation.dart';

class GroupInfoPage extends StatefulWidget {
  final Conversation conversation;
  const GroupInfoPage({super.key, required this.conversation});

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  final _service = SupabaseService();
  final _groupNameController = TextEditingController();
  
  List<Profile> _members = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _groupNameController.text = widget.conversation.name ?? 'Grup';
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      // Üyeleri yükle
      final data = await _service.getGroupMembers(widget.conversation.id);
      final myId = _service.currentUser?.id;
      
      if (mounted) {
        setState(() {
          _members = data;
          // Basit admin kontrolü: Sohbeti oluşturan admin kabul edilir
          _isAdmin = widget.conversation.createdBy == myId;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _snack('Üyeler yüklenemedi: $e', isError: true);
      }
    }
  }

  Future<void> _updateGroupName() async {
    final newName = _groupNameController.text.trim();
    if (newName.isEmpty || newName == widget.conversation.name) return;

    setState(() => _isSaving = true);
    try {
      await _service.updateGroupName(widget.conversation.id, newName);
      if (mounted) {
        _snack('Grup adı güncellendi');
        setState(() => _isSaving = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _snack('Hata: $e', isError: true);
      }
    }
  }

  Future<void> _leaveGroup() async {
    final c = await _confirm(
      title: 'Gruptan Ayrıl',
      content: 'Bu gruptan ayrılmak istediğine emin misin?',
      confirm: 'Ayrıl',
      isDanger: true,
    );
    if (c != true) return;

    try {
      final myId = _service.currentUser?.id;
      if (myId == null) return;
      
      await _service.removeGroupMember(widget.conversation.id, myId);
      if (mounted) {
        Navigator.pop(context); // Grup bilgilerinden çık
        Navigator.pop(context); // Sohbet odasından çık
      }
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  Future<void> _removeMember(Profile member) async {
    final c = await _confirm(
      title: 'Üyeyi Çıkar',
      content: '${member.username} adlı kullanıcıyı gruptan çıkarmak istediğine emin misin?',
      confirm: 'Çıkar',
      isDanger: true,
    );
    if (c != true) return;

    try {
      await _service.removeGroupMember(widget.conversation.id, member.id);
      await _loadMembers();
      _snack('${member.username} gruptan çıkarıldı');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  Future<void> _addMember() async {
    final selectedUsers = await showModalBottomSheet<List<Profile>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddMemberSheet(
        groupId: widget.conversation.id,
        existingMemberIds: _members.map((m) => m.id).toList(),
      ),
    );

    if (selectedUsers != null && selectedUsers.isNotEmpty) {
      try {
        await _service.addGroupMembers(
          widget.conversation.id, 
          selectedUsers.map((u) => u.id).toList()
        );
        await _loadMembers();
        _snack('${selectedUsers.length} üye eklendi');
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
      ),
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String content,
    required String confirm,
    bool isDanger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
        content: Text(content, style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirm, style: TextStyle(color: isDanger ? Colors.redAccent : AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Grup Bilgileri'),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // --- GRUP AVATARI VE ADI ---
          Center(
            child: Stack(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.groups, size: 50, color: Colors.white),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.background, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt, size: 16, color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: TextField(
                controller: _groupNameController,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Grup Adı',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: Border.all(color: AppTheme.primary, width: 2),
                ),
                onSubmitted: (_) => _updateGroupName(),
              ),
            )
          else
            Center(
              child: Text(
                widget.conversation.name ?? 'Grup',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
            ),
          
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${_members.length} üye',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ),
          
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),

          const SizedBox(height: 24),

          // --- ÜYELER ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Üyeler',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                if (_isAdmin)
                  TextButton.icon(
                    onPressed: _addMember,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Ekle'),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
                  ),
              ],
            ),
          ),
          
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _members.length,
            itemBuilder: (context, index) {
              final member = _members[index];
              final isMe = member.id == _service.currentUser?.id;
              final isCreator = member.id == widget.conversation.createdBy;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary,
                  backgroundImage: member.avatarUrl != null
                      ? CachedNetworkImageProvider(member.avatarUrl!)
                      : null,
                  child: member.avatarUrl == null
                      ? Text(member.username[0].toUpperCase(), style: const TextStyle(color: Colors.white))
                      : null,
                ),
                title: Row(
                  children: [
                    Text(
                      member.username + (isMe ? ' (Sen)' : ''),
                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                    ),
                    if (isCreator)
                      const Padding(
                        padding: EdgeInsets.only(left: 8.0),
                        child: Text('Admin', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                trailing: (_isAdmin && !isMe && !isCreator)
                    ? IconButton(
                        icon: const Icon(Icons.person_remove_outlined, color: Colors.redAccent),
                        onPressed: () => _removeMember(member),
                      )
                    : null,
              );
            },
          ),

          const SizedBox(height: 24),

          // --- GRUPTAN AYRILMA ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: _leaveGroup,
              icon: const Icon(Icons.exit_to_app),
              label: const Text('Gruptan Ayrıl'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withOpacity(0.1),
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent, width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// ÜYE EKLEME MODALI
// ==========================================
class _AddMemberSheet extends StatefulWidget {
  final String groupId;
  final List<String> existingMemberIds;

  const _AddMemberSheet({
    required this.groupId,
    required this.existingMemberIds,
  });

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _service = SupabaseService();
  final _searchController = TextEditingController();
  List<Profile> _results = [];
  final Set<String> _selectedIds = {};
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
        top: 16, left: 16, right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppTheme.inputBorder, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Üye Ekle',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Kullanıcı ara...',
              prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary),
            ),
            onChanged: (v) async {
              if (v.trim().length >= 2) {
                setState(() => _isSearching = true);
                final res = await _service.searchUsers(v);
                if (mounted) {
                  setState(() {
                    // Zaten grupta olanları filtrele
                    _results = res.where((u) => !widget.existingMemberIds.contains(u.id)).toList();
                    _isSearching = false;
                  });
                }
              } else {
                setState(() => _results = []);
              }
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _results.isEmpty && _searchController.text.isNotEmpty
                    ? const Center(child: Text('Kullanıcı bulunamadı.', style: TextStyle(color: AppTheme.textSecondary)))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final user = _results[i];
                          final isSelected = _selectedIds.contains(user.id);
                          return CheckboxListTile(
                            value: isSelected,
                            activeColor: AppTheme.primary,
                            title: Text(user.username, style: const TextStyle(color: AppTheme.textPrimary)),
                            secondary: CircleAvatar(
                              backgroundColor: AppTheme.primary,
                              backgroundImage: user.avatarUrl != null ? CachedNetworkImageProvider(user.avatarUrl!) : null,
                              child: user.avatarUrl == null 
                                  ? Text(user.username[0].toUpperCase(), style: const TextStyle(color: Colors.white)) 
                                  : null,
                            ),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedIds.add(user.id);
                                } else {
                                  _selectedIds.remove(user.id);
                                }
                              });
                            },
                          );
                        },
                      ),
          ),
          if (_selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final selectedProfiles = _results.where((u) => _selectedIds.contains(u.id)).toList();
                    Navigator.pop(context, selectedProfiles);
                  },
                  child: Text('${_selectedIds.length} Kişiyi Ekle'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
