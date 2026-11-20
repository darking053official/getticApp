// ============================================================
// lib/pages/group_info_page.dart
// Grup bilgileri: fotoğraf, ad, üyeler, üye ekle/çıkar, yönetici devri,
// gruptan ayrılma. Geri dönüş: yeni grup adı (String) ya da '__left__'.
// ============================================================

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme.dart';
import '../models/profile.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';

const String kGroupLeft = '__left__';
const String _kMediaBucket = 'chat-media';

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
  final _storage = StorageService();
  late final TextEditingController _nameController =
      TextEditingController(text: widget.groupName);

  late String _currentName = widget.groupName;
  String? _adminId;
  String? _avatarUrl; // imzalı URL (görüntüleme için)
  List<Profile> _members = [];
  bool _isLoading = true;
  bool _isBusy = false;

  String? get _myId => _service.currentUser?.id;
  bool get _isAdmin => _adminId != null && _adminId == _myId;

  @override
  void initState() {
    super.initState();
    _adminId = widget.createdBy;
    _loadAll();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final info = await _service.getGroupInfo(widget.conversationId);
      final members = await _service.getGroupMembers(widget.conversationId);
      String? avatar;
      final path = info?['group_avatar_url']?.toString();
      if (path != null && path.isNotEmpty) {
        avatar = await _signedUrl(path);
      }
      if (!mounted) return;
      setState(() {
        _adminId = info?['created_by']?.toString() ?? _adminId;
        _avatarUrl = avatar;
        _members = members;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Bilgiler yüklenemedi: $e', isError: true);
    }
  }

  Future<String?> _signedUrl(String path) async {
    try {
      return await Supabase.instance.client.storage
          .from(_kMediaBucket)
          .createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  // ---------- Fotoğraf ----------
  Future<void> _changeAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _isBusy = true);
    try {
      final path = await _storage.uploadChatMedia(
        file: File(picked.path),
        conversationId: widget.conversationId,
        type: 'image',
      );
      if (path == null) throw Exception('Yükleme başarısız');
      await _service.setGroupAvatar(widget.conversationId, path);
      final url = await _signedUrl(path);
      if (!mounted) return;
      setState(() => _avatarUrl = url);
      _snack('Grup fotoğrafı güncellendi');
    } catch (e) {
      _snack('Fotoğraf değiştirilemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ---------- Ad ----------
  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == _currentName) return;
    setState(() => _isBusy = true);
    try {
      await _service.updateGroupName(widget.conversationId, newName);
      if (!mounted) return;
      setState(() => _currentName = newName);
      _snack('Grup adı güncellendi');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ---------- Üyeler ----------
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
      await _reloadMembers();
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  Future<void> _makeAdmin(Profile member) async {
    final ok = await _confirm(
      title: 'Yönetici yap',
      content:
          '${member.username} yönetici olunca grubu siz yönetemezsiniz. Devam edilsin mi?',
      confirm: 'Devret',
    );
    if (ok != true) return;
    try {
      await _service.transferGroupAdmin(widget.conversationId, member.id);
      if (!mounted) return;
      setState(() => _adminId = member.id);
      _snack('${member.username} artık yönetici');
    } catch (e) {
      _snack('Devredilemedi: $e', isError: true);
    }
  }

  Future<void> _reloadMembers() async {
    final members = await _service.getGroupMembers(widget.conversationId);
    if (mounted) setState(() => _members = members);
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
      await _reloadMembers();
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  // ---------- Ayrılma ----------
  Future<void> _leaveGroup() async {
    final others = _members.where((m) => m.id != _myId).toList();

    if (_isAdmin && others.isNotEmpty) {
      // Yönetici ayrılmadan önce yetkiyi bir üyeye devretmeli
      final newAdmin = await showModalBottomSheet<Profile>(
        context: context,
        backgroundColor: AppTheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Yöneticiliği kime devretmek istersiniz?',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ),
              ...others.map((m) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary,
                      child: Text(m.initial,
                          style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(m.username,
                        style: const TextStyle(color: AppTheme.textPrimary)),
                    onTap: () => Navigator.pop(ctx, m),
                  )),
            ],
          ),
        ),
      );
      if (newAdmin == null) return;
      try {
        await _service.transferGroupAdmin(widget.conversationId, newAdmin.id);
      } catch (e) {
        _snack('Devredilemedi: $e', isError: true);
        return;
      }
    } else {
      final ok = await _confirm(
        title: 'Gruptan ayrıl',
        content: 'Bu gruptan ayrılmak istediğinize emin misiniz?',
        confirm: 'Ayrıl',
        isDanger: true,
      );
      if (ok != true) return;
    }

    try {
      await _service.leaveGroupRpc(widget.conversationId);
      if (!mounted) return;
      Navigator.pop(context, kGroupLeft);
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  // ---------- Yardımcılar ----------
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

  void _memberOptions(Profile member) {
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
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined,
                  color: AppTheme.primary),
              title: const Text('Yönetici yap',
                  style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _makeAdmin(member);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined,
                  color: Colors.redAccent),
              title: const Text('Gruptan çıkar',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _removeMember(member);
              },
            ),
          ],
        ),
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
                    child: GestureDetector(
                      onTap: _isAdmin && !_isBusy ? _changeAvatar : null,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: AppTheme.primary,
                            backgroundImage: _avatarUrl != null
                                ? CachedNetworkImageProvider(_avatarUrl!)
                                : null,
                            child: _avatarUrl == null
                                ? const Icon(Icons.groups,
                                    size: 48, color: Colors.white)
                                : null,
                          ),
                          if (_isAdmin)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppTheme.background, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt,
                                    size: 16, color: AppTheme.textSecondary),
                              ),
                            ),
                          if (_isBusy)
                            const Positioned.fill(
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
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
                    final isAdminMember = member.id == _adminId;
                    final canManage = _isAdmin && !isMe;
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
                          if (isAdminMember)
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
                      trailing: canManage
                          ? IconButton(
                              tooltip: 'Seçenekler',
                              icon: const Icon(Icons.more_vert,
                                  color: AppTheme.textSecondary),
                              onPressed: () => _memberOptions(member),
                            )
                          : null,
                    );
                  }),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton.icon(
                      onPressed: _isBusy ? null : _leaveGroup,
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
