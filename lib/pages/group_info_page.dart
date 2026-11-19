// ============================================================
// lib/pages/group_info_page.dart
// (.txt olarak verildi. Projeye eklerken adını group_info_page.dart yapın.)
// Grup bilgileri: ad, üyeler, üye ekle/çıkar (yönetici), gruptan ayrıl.
// Geri dönüş değeri: yeni grup adı (String), gruptan ayrıldıysa '__left__'.
// ============================================================

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';

const String kGroupLeft = '__left__';

class GroupInfoPage extends StatefulWidget {
  final String conversationId;
  final String groupName;
  final String? createdBy;

  const GroupInfoPage({
    super.key,
    required this.conversationId,
    required this.groupName,
    this.createdBy,
  });

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  final _service = SupabaseService();
  late final TextEditingController _nameController =
      TextEditingController(text: widget.groupName);

  late String _currentName = widget.groupName;
  List<Profile> _members = [];
  bool _isLoading = true;
  bool _isSaving = false;

  String? get _myId => _service.currentUser?.id;
  bool get _isAdmin => widget.createdBy != null && widget.createdBy == _myId;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    try {
      final data = await _service.getGroupMembers(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _members = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Üyeler yüklenemedi: $e', isError: true);
    }
  }

  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == _currentName) return;
    setState(() => _isSaving = true);
    try {
      await _service.updateGroupName(widget.conversationId, newName);
      if (!mounted) return;
      setState(() => _currentName = newName);
      _snack('Grup adı güncellendi');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _leaveGroup() async {
    final ok = await _confirm(
      title: 'Gruptan ayrıl',
      content: 'Bu gruptan ayrılmak istediğine emin misin?',
      confirm: 'Ayrıl',
      isDanger: true,
    );
    if (ok != true || _myId == null) return;
    try {
      await _service.removeGroupMember(widget.conversationId, _myId!);
      if (!mounted) return;
      Navigator.pop(context, kGroupLeft);
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  Future<void> _removeMember(Profile member) async {
    final ok = await _confirm(
      title: 'Üyeyi çıkar',
      content: '${member.username} gruptan çıkarılsın mı?',
      confirm: 'Çıkar',
      isDanger: true,
    );
    if (ok != true) return;
    try {
      await _service.removeGroupMember(widget.conversationId, member.id);
      _snack('${member.username} gruptan çıkarıldı');
      await _loadMembers();
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  Future<void> _addMember() async {
    final selected = await showModalBottomSheet<List<Profile>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMemberSheet(
        existingMemberIds: _members.map((m) => m.id).toList(),
      ),
    );
    if (selected == null || selected.isEmpty) return;
    try {
      await _service.addGroupMembers(
          widget.conversationId, selected.map((u) => u.id).toList());
      _snack('${selected.length} üye eklendi');
      await _loadMembers();
    } catch (e) {
      _snack('Hata: $e', isError: true);
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
            child: Text(confirm,
                style: TextStyle(
                    color: isDanger ? Colors.redAccent : AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) Navigator.pop(context, _currentName);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Grup bilgileri'),
          backgroundColor: AppTheme.background,
          elevation: 0,
          leading: BackButton(
            onPressed: () => Navigator.pop(context, _currentName),
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primary))
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.groups,
                          size: 48, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isAdmin)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: TextField(
                        controller: _nameController,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Grup adı',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _saveName(),
                      ),
                    )
                  else
                    Center(
                      child: Text(
                        _currentName,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      '${_members.length} üye',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 14),
                    ),
                  ),
                  if (_isSaving)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ÜYELER',
                          style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1),
                        ),
                        if (_isAdmin)
                          TextButton.icon(
                            onPressed: _addMember,
                            icon: const Icon(Icons.person_add_alt_1, size: 18),
                            label: const Text('Ekle'),
                            style: TextButton.styleFrom(
                                foregroundColor: AppTheme.primary),
                          ),
                      ],
                    ),
                  ),
                  ..._members.map((member) {
                    final isMe = member.id == _myId;
                    final isCreator = member.id == widget.createdBy;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primary,
                        backgroundImage: member.avatarUrl != null
                            ? CachedNetworkImageProvider(member.avatarUrl!)
                            : null,
                        child: member.avatarUrl == null
                            ? Text(member.initial,
                                style: const TextStyle(color: Colors.white))
                            : null,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              isMe ? '${member.username} (Sen)' : member.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                          if (isCreator)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Text('Yönetici',
                                  style: TextStyle(
                                      color: AppTheme.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      trailing: (_isAdmin && !isMe && !isCreator)
                          ? IconButton(
                              tooltip: 'Gruptan çıkar',
                              icon: const Icon(Icons.person_remove_outlined,
                                  color: Colors.redAccent),
                              onPressed: () => _removeMember(member),
                            )
                          : null,
                    );
                  }),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton.icon(
                      onPressed: _leaveGroup,
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('Gruptan ayrıl'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
      ),
    );
  }
}

// ============================================================
// ÜYE EKLEME (çoklu seçim)
// ============================================================
class _AddMemberSheet extends StatefulWidget {
  final List<String> existingMemberIds;
  const _AddMemberSheet({required this.existingMemberIds});

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _service = SupabaseService();
  final _searchController = TextEditingController();
  List<Profile> _results = [];
  final Map<String, Profile> _selected = {};
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String v) async {
    if (v.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _isSearching = true);
    final res = await _service.searchUsers(v);
    if (!mounted) return;
    setState(() {
      _results = res
          .where((u) => !widget.existingMemberIds.contains(u.id))
          .toList();
      _isSearching = false;
    });
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
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: AppTheme.inputBorder,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text('Üye ekle',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Kullanıcı ara...',
              prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary),
            ),
            onChanged: _search,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                : _results.isEmpty
                    ? const Center(
                        child: Text('Kullanıcı yazarak arayın',
                            style: TextStyle(color: AppTheme.textSecondary)))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final u = _results[i];
                          final on = _selected.containsKey(u.id);
                          return CheckboxListTile(
                            value: on,
                            activeColor: AppTheme.primary,
                            title: Text(u.username,
                                style: const TextStyle(
                                    color: AppTheme.textPrimary)),
                            secondary: CircleAvatar(
                              backgroundColor: AppTheme.primary,
                              backgroundImage: u.avatarUrl != null
                                  ? CachedNetworkImageProvider(u.avatarUrl!)
                                  : null,
                              child: u.avatarUrl == null
                                  ? Text(u.initial,
                                      style: const TextStyle(
                                          color: Colors.white))
                                  : null,
                            ),
                            onChanged: (val) => setState(() {
                              if (val == true) {
                                _selected[u.id] = u;
                              } else {
                                _selected.remove(u.id);
                              }
                            }),
                          );
                        },
                      ),
          ),
          if (_selected.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.pop(context, _selected.values.toList()),
                child: Text('${_selected.length} kişiyi ekle'),
              ),
            ),
        ],
      ),
    );
  }
}
