import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _service.getMyProfile();
      if (mounted) {
        setState(() {
          _profile = p;
          _showOnline = p?.showOnlineStatus ?? true;
          _showLastSeen = p?.showLastSeen ?? true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profil yüklenemedi: $e')),
        );
      }
    }
  }

  Future<void> _updatePrivacy() async {
    try {
      await _service.updatePrivacySettings(
        showOnline: _showOnline, 
        showLastSeen: _showLastSeen
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gizlilik ayarları kaydedildi'),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ayar kaydedilemedi: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Hesabı Sil', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'Hesabınızı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false), 
            child: const Text('İptal', style: TextStyle(color: AppTheme.textSecondary))
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true), 
            child: const Text('Sil', style: TextStyle(color: Colors.redAccent))
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _service.deleteAccount();
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Hata: $e'), 
              backgroundColor: Colors.redAccent
            )
          );
        }
      }
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Çıkış Yap', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'Çıkış yapmak istediğinize emin misiniz?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false), 
            child: const Text('İptal', style: TextStyle(color: AppTheme.textSecondary))
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true), 
            child: const Text('Çıkış', style: TextStyle(color: AppTheme.primary))
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _service.signOut();
      // AuthWrapper main.dart'ta otomatik AuthPage'e yönlendirir
    }
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
        title: const Text('Ayarlar'),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- PROFİL ÖZET KARTI ---
          if (_profile != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.inputBorder),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: AppTheme.primary,
                    backgroundImage: _profile!.avatarUrl != null
                        ? CachedNetworkImageProvider(_profile!.avatarUrl!)
                        : null,
                    child: _profile!.avatarUrl == null
                        ? Text(
                            _profile!.username.isNotEmpty
                                ? _profile!.username[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 30, 
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _profile!.username,
                    style: const TextStyle(
                      fontSize: 20, 
                      fontWeight: FontWeight.bold, 
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_profile!.status != null && _profile!.status!.isNotEmpty)
                    Text(
                      _profile!.status!,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // --- GİZLİLİK AYARLARI ---
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              'GİZLİLİK',
              style: TextStyle(
                color: AppTheme.primary, 
                fontWeight: FontWeight.bold, 
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.inputBorder),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    'Çevrimiçi durumumu göster',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  ),
                  subtitle: const Text(
                    'Kapalıyken diğerleri sizi çevrimiçi göremez',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  value: _showOnline,
                  activeColor: AppTheme.primary,
                  onChanged: (v) {
                    setState(() => _showOnline = v);
                    _updatePrivacy();
                  },
                ),
                const Divider(color: AppTheme.inputBorder, height: 1),
                SwitchListTile(
                  title: const Text(
                    'Son görülmemi göster',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  ),
                  subtitle: const Text(
                    'Kapalıyken son görülme gizlenir',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  value: _showLastSeen,
                  activeColor: AppTheme.primary,
                  onChanged: (v) {
                    setState(() => _showLastSeen = v);
                    _updatePrivacy();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // --- HESAP İŞLEMLERİ ---
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              'HESAP',
              style: TextStyle(
                color: AppTheme.primary, 
                fontWeight: FontWeight.bold, 
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.inputBorder),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.logout, color: AppTheme.textPrimary),
                  title: const Text(
                    'Çıkış Yap', 
                    style: TextStyle(color: AppTheme.textPrimary),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                  onTap: _signOut,
                ),
                const Divider(color: AppTheme.inputBorder, height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: const Text(
                    'Hesabımı Sil', 
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.redAccent),
                  onTap: _deleteAccount,
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
          
          // --- VERSİYON BİLGİSİ ---
          const Center(
            child: Text(
              'Gettic v1.0.0',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
