// ============================================================
// lib/pages/new_group_page.dart
// (.txt olarak verildi. Projeye eklerken adını new_group_page.dart yapın.)
// Yeni grup: ad, isteğe bağlı fotoğraf, üye seçimi. Oluşturulunca grup kimliğini döndürür.
// ============================================================

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../models/profile.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';

class NewGroupPage extends StatefulWidget {
  const NewGroupPage({super.key});

  @override
  State<NewGroupPage> createState() => _NewGroupPageState();
}

class _NewGroupPageState extends State<NewGroupPage> {
  static const int _maxMembers = 100;

  final _service = SupabaseService();
  final _storage = StorageService();
  final _nameCtl = TextEditingController();
  final _searchCtl = TextEditingController();

  Timer? _debounce;
  int _searchId = 0;

  List<Profile> _results = [];
  final Map<String, Profile> _selected = {};
  File? _avatar;

  bool _searching = false;
  bool _creating = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  // ---------- Arama ----------

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String value) async {
    final id = ++_searchId;
    final q = value.trim();
    if (q.length < 2) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final res = await _service.searchUsers(q);
    if (!mounted || id != _searchId) return;
    setState(() {
      _results = res.where((u) => !_selected.containsKey(u.id)).toList();
      _searching = false;
    });
  }

  // ---------- Seçim ----------

  void _toggle(Profile u) {
    setState(() {
      if (_selected.containsKey(u.id)) {
        _selected.remove(u.id);
      } else {
        if (_selected.length >= _maxMembers) {
          _snack('En fazla $_maxMembers üye ekleyebilirsiniz', isError: true);
          return;
        }
        _selected[u.id] = u;
        _results.removeWhere((x) => x.id == u.id);
      }
    });
  }

  // ---------- Fotoğraf ----------

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _avatar = File(picked.path));
  }

  // ---------- Oluşturma ----------

  Future<void> _create() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      _snack('Lütfen bir grup adı girin', isError: true);
      return;
    }
    if (_selected.isEmpty) {
      _snack('Lütfen en az bir üye seçin', isError: true);
      return;
    }

    setState(() => _creating = true);
    try {
      final convId = await _service.createGroupConversation(
        groupName: name,
        memberIds: _selected.keys.toList(),
      );

      // Fotoğraf isteğe bağlı: hata olursa grup yine de oluşturulmuş olur
      if (_avatar != null) {
        final path = await _storage.uploadChatMedia(
          file: _avatar!,
          conversationId: convId,
          type: 'image',
        );
        if (path != null) {
          try {
            await _service.setGroupAvatar(convId, path);
          } catch (_) {
            _snack('Grup oluşturuldu ama fotoğraf kaydedilemedi', isError: true);
          }
        }
      }

      if (!mounted) return;
      Navigator.pop(context, convId);
    } catch (e) {
      _snack('Grup oluşturulamadı: $e', isError: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : context.appColors.primary,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ---------- Arayüz ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.background,
      appBar: AppBar(
        title: const Text('Yeni grup'),
        backgroundColor: context.appColors.background,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _creating ? null : _create,
            child: _creating
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: context.appColors.primary))
                : Text(
                    'Oluştur',
                    style: TextStyle(
                        color: context.appColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          Divider(color: context.appColors.border, height: 1),
          if (_selected.isNotEmpty) _buildChips(),
          _buildSearch(),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: _creating ? null : _pickAvatar,
            child: CircleAvatar(
              radius: 26,
              backgroundColor: context.appColors.surface,
              backgroundImage: _avatar != null ? FileImage(_avatar!) : null,
              child: _avatar == null
                  ? Icon(Icons.camera_alt, color: context.appColors.textSecondary)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _nameCtl,
              enabled: !_creating,
              maxLength: 60,
              style: TextStyle(color: context.appColors.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Grup adı',
                counterText: '',
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: context.appColors.border),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: context.appColors.border),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: context.appColors.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _selected.values.map((u) {
          return Chip(
            avatar: CircleAvatar(
              backgroundColor: context.appColors.primary,
              backgroundImage: u.avatarUrl != null
                  ? CachedNetworkImageProvider(u.avatarUrl!)
                  : null,
              child: u.avatarUrl == null
                  ? Text(u.initial,
                      style: const TextStyle(color: Colors.white, fontSize: 10))
                  : null,
            ),
            label: Text(u.username,
                style: TextStyle(color: context.appColors.textPrimary)),
            backgroundColor: context.appColors.surface,
            side: BorderSide(color: context.appColors.border),
            deleteIcon:
                Icon(Icons.close, size: 16, color: context.appColors.textSecondary),
            onDeleted: _creating ? null : () => _toggle(u),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchCtl,
        enabled: !_creating,
        style: TextStyle(color: context.appColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Kullanıcı ara (en az 2 harf)',
          prefixIcon: Icon(Icons.search, color: context.appColors.textSecondary),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildResults() {
    if (_searching) {
      return Center(
          child: CircularProgressIndicator(color: context.appColors.primary));
    }
    if (_searchCtl.text.trim().length < 2) {
      return Center(
        child: Text('Üye eklemek için kullanıcı adı yazın',
            style: TextStyle(color: context.appColors.textSecondary)),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('Kullanıcı bulunamadı',
            style: TextStyle(color: context.appColors.textSecondary)),
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final u = _results[i];
        final isOn = _selected.containsKey(u.id);
        return ListTile(
          enabled: !_creating,
          leading: CircleAvatar(
            backgroundColor: context.appColors.primary,
            backgroundImage: u.avatarUrl != null
                ? CachedNetworkImageProvider(u.avatarUrl!)
                : null,
            child: u.avatarUrl == null
                ? Text(u.initial, style: const TextStyle(color: Colors.white))
                : null,
          ),
          title: Text(u.username,
              style: TextStyle(color: context.appColors.textPrimary)),
          trailing: Icon(
            isOn ? Icons.check_circle : Icons.add_circle_outline,
            color: isOn ? context.appColors.primary : context.appColors.textSecondary,
          ),
          onTap: () => _toggle(u),
        );
      },
    );
  }
}
