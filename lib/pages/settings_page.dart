import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _service = SupabaseService();
  Profile? _profile;
  bool _showOnline = true;
  bool _showLastSeen = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _service.getMyProfile();
    if (mounted && p != null) {
      setState(() {
        _profile = p;
        _showOnline = p.showOnlineStatus;
        _showLastSeen = p.showLastSeen;
      });
    }
  }

  Future<void> _updatePrivacy() async {
    await _service.updatePrivacySettings(showOnline: _showOnline, showLastSeen: _showLastSeen);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gizlilik ayarları kaydedildi'), backgroundColor: GetticTheme.online));
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: GetticTheme.bgSecondary,
        title: const Text('Hesabı Sil', style: TextStyle(color: GetticTheme.textPrimary)),
        content: const Text('Hesabınızı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.', style: TextStyle(color: GetticTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _service.deleteAccount();
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: GetticTheme.danger));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_profile != null) ...[
            CircleAvatar(backgroundColor: GetticTheme.accent, radius: 40, child: Text(_profile!.username[0].toUpperCase(), style: const TextStyle(fontSize: 30, color: Colors.white))),
            const SizedBox(height: 10),
            Center(child: Text(_profile!.username, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: GetticTheme.textPrimary))),
            Center(child: Text(_profile!.fullName ?? '', style: const TextStyle(color: GetticTheme.textSecondary))),
            const SizedBox(height: 30),
          ],

          const Text('Gizlilik', style: TextStyle(color: GetticTheme.accent, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          SwitchListTile(
            title: const Text('Çevrimiçi durumumu göster', style: TextStyle(color: GetticTheme.textPrimary)),
            subtitle: const Text('Kapalıyken diğerleri sizi çevrimiçi göremez', style: TextStyle(color: GetticTheme.textSecondary, fontSize: 12)),
            value: _showOnline,
            activeColor: GetticTheme.accent,
            onChanged: (v) { setState(() => _showOnline = v); _updatePrivacy(); },
          ),
          SwitchListTile(
            title: const Text('Son görülmemi göster', style: TextStyle(color: GetticTheme.textPrimary)),
            subtitle: const Text('Kapalıyken son görülme gizlenir', style: TextStyle(color: GetticTheme.textSecondary, fontSize: 12)),
            value: _showLastSeen,
            activeColor: GetticTheme.accent,
            onChanged: (v) { setState(() => _showLastSeen = v); _updatePrivacy(); },
          ),

          const SizedBox(height: 30),
          const Text('Hesap', style: TextStyle(color: GetticTheme.accent, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.logout, color: GetticTheme.textPrimary),
            title: const Text('Çıkış Yap', style: TextStyle(color: GetticTheme.textPrimary)),
            onTap: () async { await _service.signOut(); if (mounted) Navigator.pop(context); },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Hesabımı Sil', style: TextStyle(color: Colors.red)),
            onTap: _deleteAccount,
          ),
        ],
      ),
    );
  }
}
