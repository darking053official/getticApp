import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _service = SupabaseService();
  final _usernameController = TextEditingController();
  final _statusController = TextEditingController();
  
  bool _isLoading = true;
  bool _isSaving = false;
  Profile? _profile;

  // Gizlilik Ayarları (Switch State'leri)
  bool _showOnlineStatus = true;
  bool _showLastSeen = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      // ✅ getProfile zaten Profile nesnesi döndürüyor
      final profile = await _service.getMyProfile();
      
      if (mounted) {
        if (profile != null) {
          setState(() {
            _profile = profile;
            _usernameController.text = profile.username;
            _statusController.text = profile.status ?? '';
            _showOnlineStatus = profile.showOnlineStatus;
            _showLastSeen = profile.showLastSeen;
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
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

  Future<void> _saveProfile() async {
    final userId = _service.currentUser?.id;
    if (userId == null) return;

    final newUsername = _usernameController.text.trim();
    if (newUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı adı boş olamaz.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updates = {
        'username': newUsername,
        'status': _statusController.text.trim(),
        'show_online_status': _showOnlineStatus,
        'show_last_seen': _showLastSeen,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _service.updateProfile(userId, updates);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil başarıyla güncellendi.'),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Güncelleme başarısız: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Gizlilik switch'leri değiştiğinde anında veritabanına yaz
  Future<void> _togglePrivacy(String field, bool value) async {
    setState(() {
      if (field == 'show_online_status') _showOnlineStatus = value;
      if (field == 'show_last_seen') _showLastSeen = value;
    });

    final userId = _service.currentUser?.id;
    if (userId != null) {
      try {
        // ✅ Servis fonksiyonumuzla uyumlu hale getirildi
        await _service.updateProfile(userId, {field: value});
      } catch (e) {
        // Hata durumunda eski haline getir
        setState(() {
          if (field == 'show_online_status') _showOnlineStatus = !value;
          if (field == 'show_last_seen') _showLastSeen = !value;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gizlilik ayarı kaydedilemedi.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _statusController.dispose();
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
        title: const Text('Profil & Ayarlar'),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // --- AVATAR ALANI ---
            Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: AppTheme.surface,
                  backgroundImage: _profile?.avatarUrl != null
                      ? CachedNetworkImageProvider(_profile!.avatarUrl!)
                      : null,
                  child: _profile?.avatarUrl == null
                      ? Text(
                          (_profile?.username.isNotEmpty ?? false)
                              ? _profile!.username[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () {
                      // TODO: StorageService ile avatar yükleme işlemi buraya gelecek
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Avatar yükleme özelliği yakında.')),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // ✅ Email yerine username gösteriliyor (profiles tablosunda email yok)
            Text(
              '@${_profile?.username ?? "kullanici"}',
              style: const TextStyle(
                color: AppTheme.textSecondary, 
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),

            // --- KİŞİSEL BİLGİLER KARTI ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.inputBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kişisel Bilgiler',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Kullanıcı Adı',
                      labelStyle: TextStyle(color: AppTheme.textSecondary),
                      prefixIcon: Icon(Icons.person_outline, color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _statusController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Durum (İsteğe bağlı)',
                      hintText: 'Örn: Kod yazıyorum...',
                      labelStyle: TextStyle(color: AppTheme.textSecondary),
                      prefixIcon: Icon(Icons.info_outline, color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // --- GİZLİLİK AYARLARI KARTI ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.inputBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gizlilik',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Çevrimiçi durumumu göster',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Kapalıysa kimse çevrimiçi olduğunuzu göremez.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                    activeColor: AppTheme.primary,
                    value: _showOnlineStatus,
                    onChanged: (val) => _togglePrivacy('show_online_status', val),
                  ),
                  const Divider(color: AppTheme.inputBorder),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Son görülmemi göster',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Kapalıysa son görülme zamanınız gizlenir.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                    activeColor: AppTheme.primary,
                    value: _showLastSeen,
                    onChanged: (val) => _togglePrivacy('show_last_seen', val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // --- KAYDET BUTONU ---
            ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Değişiklikleri Kaydet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
