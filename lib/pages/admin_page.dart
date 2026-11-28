// ============================================================
// lib/pages/admin_page.dart
// (.txt olarak verildi. Projeye eklerken adını admin_page.dart yapın.)
// Yönetici paneli: kullanıcı ara, banla, ban kaldır.
// Yetki sunucuda kontrol edilir (admin-users fonksiyonu). Bu sayfa yalnızca görünüm.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _searchCtl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<dynamic> _call(Map<String, dynamic> body) async {
    final res = await Supabase.instance.client.functions
        .invoke('admin-users', body: body);
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    return data;
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _call({'action': 'search', 'query': q.trim()});
      final list = (data['results'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() => _results = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleBan(Map<String, dynamic> u) async {
    final banned = u['banned'] == true;
    final name = (u['username'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surface,
        title: Text(banned ? 'Banı kaldır' : 'Kullanıcıyı banla',
            style: TextStyle(color: context.appColors.textPrimary)),
        content: Text(
          banned
              ? '$name kullanıcısının banı kaldırılsın mı?'
              : '$name banlansın mı? Kullanıcı giriş yapamaz.',
          style: TextStyle(color: context.appColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(banned ? 'Kaldır' : 'Banla',
                  style: TextStyle(
                      color: banned ? context.appColors.primary : Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _call({
        'action': banned ? 'unban' : 'ban',
        'userId': u['id'],
      });
      if (!mounted) return;
      setState(() => u['banned'] = !banned);
      _snack(banned ? 'Ban kaldırıldı' : '$name banlandı');
    } catch (e) {
      _snack('Hata: $e', isError: true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.background,
      appBar: AppBar(
        title: const Text('Yönetici paneli'),
        backgroundColor: context.appColors.background,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtl,
              style: TextStyle(color: context.appColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Kullanıcı adı ara (en az 2 harf)',
                prefixIcon: Icon(Icons.search, color: context.appColors.textSecondary),
              ),
              onChanged: _onChanged,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: context.appColors.primary))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final u = _results[i];
                      final banned = u['banned'] == true;
                      final isAdmin = u['role'] == 'admin';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: context.appColors.primary,
                          child: Text(
                            (u['username'] ?? '?').toString().isNotEmpty
                                ? (u['username'] as String)[0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(u['username']?.toString() ?? '',
                            style: TextStyle(color: context.appColors.textPrimary)),
                        subtitle: Text(
                          [
                            if (isAdmin) 'Yönetici',
                            if (banned) 'Banlı',
                          ].join(' · '),
                          style: TextStyle(
                              color: banned
                                  ? Colors.redAccent
                                  : context.appColors.textSecondary),
                        ),
                        trailing: isAdmin
                            ? null
                            : TextButton(
                                onPressed: () => _toggleBan(u),
                                child: Text(banned ? 'Ban kaldır' : 'Banla',
                                    style: TextStyle(
                                        color: banned
                                            ? context.appColors.primary
                                            : Colors.redAccent)),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
