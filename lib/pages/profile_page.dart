import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../core/utils.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _service = SupabaseService();
  final _storage = StorageService();
  final _usernameController = TextEditingController();
  final _statusController = TextEditingController();
  final _bioController = TextEditingController();
  final _picker = ImagePicker();

  Profile? _profile;
  File? _localAvatar;
  bool _isLoading = true;
  bool _isUploadingAvatar = false;
  bool _isSaving = false;

  // Gizlilik
  bool _showOnline = true;
  bool _showLastSeen = true;
  bool _showReadReceipts = true;
  bool _muteNotifications = false;

  // İstatistikler
  int _totalMessages = 0;
  int _totalConversations = 0;

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
          _usernameController.text = p?.username ?? '';
          _statusController.text = p?.status ?? '';
          _bioController.text = p?.fullName ?? '';
          _showOnline = p?.showOnlineStatus ?? true;
          _showLastSeen = p?.showLastSeen ?? true;
          _isLoading = false;
        });
        _loadStats();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    try {
      final userId = _service.currentUser?.id;
      if (userId == null) return;

      final members = await _service.getMyConversationsWithUnread();
      int messagesCount = 0;
      for (final m in members) {
        final msgs = await _service.getMessages(m['conversation_id']);
        messagesCount += msgs.where((msg) => msg.senderId == userId).length;
      }

      if (mounted) {
        setState(() {
          _totalConversations = members.length;
          _totalMessages = messagesCount;
        });
      }
    } catch (e) {
      debugPrint('İstatistik hatası: $e');
    }
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.inputBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Profil Fotoğrafı',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppTheme.primary),
              title: const Text('Galeriden Seç',
                  style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.primary),
              title: const Text('Kamera ile Çek',
                  style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            if (_profile?.avatarUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Fotoğrafı Kaldır',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _removeAvatar();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() {
        _localAvatar = File(picked.path);
        _isUploadingAvatar = true;
      });

      final userId = _service.currentUser?.id;
      if (userId == null) return;

      final url = await _storage.uploadAvatar(File(picked.path), userId);

      if (url != null) {
        await _service.updateProfile(userId, {'avatar_url': url});
        await _load();
        _snack('Profil fotoğrafı güncellendi');
      } else {
        _snack('Yükleme başarısız', isError: true);
      }
    } catch (e) {
      _snack('Hata: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    final confirm = await _confirm(
      title: 'Fotoğrafı Kaldır',
      content: 'Profil fotoğrafın kaldırılsın mı?',
      confirm: 'Kaldır',
      isDanger: true,
    );
    if (confirm != true) return;

    try {
      final userId = _service.currentUser?.id;
      if (userId == null) return;
      await _service.updateProfile(userId, {'avatar_url': null});
      await _load();
      _snack('Fotoğraf kaldırıldı');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  Future<void> _saveProfile() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      _snack('Kullanıcı adı boş olamaz', isError: true);
      return;
    }
    if (username.length < 3) {
      _snack('Kullanıcı adı en az 3 karakter olmalı', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final userId = _service.currentUser?.id;
      if (userId == null) return;

      await _service.updateProfile(userId, {
        'username': username,
        'status': _statusController.text.trim(),
        'full_name': _bioController.text.trim(),
        'show_online_status': _showOnline,
        'show_last_seen': _showLastSeen,
        'updated_at': DateTime.now().toIso8601String(),
      });

      await _load();
      _snack('Profil güncellendi');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _shareProfile() async {
    final username = _profile?.username ?? '';
    await Clipboard.setData(ClipboardData(
      text: 'Gettic\'te beni bul: @$username\nhttps://gettic.dpdns.org',
    ));
    _snack('Profil linki kopyalandı');
  }

  void _showFullAvatar() {
    if (_profile?.avatarUrl == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: _profile!.avatarUrl!,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40, right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            child: Text(confirm,
                style: TextStyle(color: isDanger ? Colors.redAccent : AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _statusController.dispose();
    _bioController.dispose();
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
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bio
                  if (_profile?.fullName != null && _profile!.fullName!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.inputBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('HAKKIMDA',
                              style: TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5)),
                          const SizedBox(height: 8),
                          Text(
                            _profile!.fullName!,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // İstatistikler
                  _buildStatsCard(),

                  const SizedBox(height: 24),

                  // Kişisel Bilgiler
                  _sectionHeader('KİŞİSEL BİLGİLER'),
                  _card([
                    _textField(
                      controller: _usernameController,
                      icon: Icons.alternate_email,
                      label: 'Kullanıcı Adı',
                      hint: 'kullanici_adi',
                    ),
                    _divider(),
                    _textField(
                      controller: _statusController,
                      icon: Icons.mood_outlined,
                      label: 'Durum',
                      hint: 'Örn: Kod yazıyorum...',
                    ),
                    _divider(),
                    _textField(
                      controller: _bioController,
                      icon: Icons.info_outline,
                      label: 'Hakkımda',
                      hint: 'Kendinden bahset...',
                      maxLines: 3,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // Gizlilik
                  _sectionHeader('GİZLİLİK'),
                  _card([
                    _switchTile(
                      icon: Icons.visibility_outlined,
                      title: 'Çevrimiçi durumumu göster',
                      subtitle: 'Kapalıyken çevrimiçi görünmezsin',
                      value: _showOnline,
                      onChanged: (v) => setState(() => _showOnline = v),
                    ),
                    _divider(),
                    _switchTile(
                      icon: Icons.access_time,
                      title: 'Son görülmemi göster',
                      subtitle: 'Son görülme zamanın gizlenir',
                      value: _showLastSeen,
                      onChanged: (v) => setState(() => _showLastSeen = v),
                    ),
                    _divider(),
                    _switchTile(
                      icon: Icons.done_all,
                      title: 'Okundu bilgisi',
                      subtitle: 'Mavi tikler gösterilsin mi?',
                      value: _showReadReceipts,
                      onChanged: (v) => setState(() => _showReadReceipts = v),
                    ),
                    _divider(),
                    _switchTile(
                      icon: Icons.notifications_off_outlined,
                      title: 'Bildirimleri Sessize Al',
                      subtitle: 'Tüm bildirimleri kapat',
                      value: _muteNotifications,
                      onChanged: (v) => setState(() => _muteNotifications = v),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // Hesap Bilgileri
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.inputBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            color: AppTheme.textSecondary, size: 20),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Hesap Oluşturma',
                                style: TextStyle(
                                    color: AppTheme.textSecondary, fontSize: 12)),
                            Text(
                              _formatMemberSince(),
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Kaydet Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                        shadowColor: AppTheme.primary.withOpacity(0.5),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Değişiklikleri Kaydet',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: AppTheme.background,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.share_outlined, color: AppTheme.textPrimary),
          onPressed: _shareProfile,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withOpacity(0.4),
                AppTheme.background,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _showFullAvatar,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.primary, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: AppTheme.surface,
                          backgroundImage: _localAvatar != null
                              ? FileImage(_localAvatar!)
                              : (_profile?.avatarUrl != null
                                  ? CachedNetworkImageProvider(
                                      _profile!.avatarUrl!)
                                  : null) as ImageProvider?,
                          child: (_localAvatar == null &&
                                  _profile?.avatarUrl == null)
                              ? Text(
                                  _profile!.username.isNotEmpty
                                      ? _profile!.username[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 45,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: GestureDetector(
                          onTap: _isUploadingAvatar ? null : _pickAvatar,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppTheme.background, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withOpacity(0.5),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: _isUploadingAvatar
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.camera_alt,
                                    size: 22, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _profile?.username ?? '',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.verified,
                        color: AppTheme.primary, size: 22),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '@${_profile?.username ?? ''}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.inputBorder),
      ),
      child: Row(
        children: [
          _statItem('$_totalConversations', 'Sohbet', Icons.chat_bubble_outline),
          _statDivider(),
          _statItem('$_totalMessages', 'Mesaj', Icons.message_outlined),
          _statDivider(),
          _statItem(_formatMemberDays(), 'Gün', Icons.calendar_today_outlined),
        ],
      ),
    );
  }

  String _formatMemberSince() {
    try {
      final createdAt = _service.currentUser?.createdAt;
      if (createdAt == null) return 'Bilinmiyor';
      final date = DateTime.parse(createdAt);
      return DateFormat('d MMMM yyyy', 'tr_TR').format(date);
    } catch (_) {
      return 'Bilinmiyor';
    }
  }

  String _formatMemberDays() {
    try {
      final createdAt = _service.currentUser?.createdAt;
      if (createdAt == null) return '0';
      final date = DateTime.parse(createdAt);
      final days = DateTime.now().difference(date).inDays;
      return '$days';
    } catch (_) {
      return '0';
    }
  }

  Widget _statItem(String value, String label, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppTheme.primary, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 40,
      color: AppTheme.inputBorder,
    );
  }

  Widget _sectionHeader(String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          color: color ?? AppTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.inputBorder),
      ),
      child: Column(children: children),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: AppTheme.textSecondary),
          hintStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.5)),
          prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 22),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppTheme.textSecondary, size: 22),
      title: Text(title,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 12)),
      value: value,
      activeColor: AppTheme.primary,
      onChanged: onChanged,
    );
  }

  Widget _divider() =>
      const Divider(color: AppTheme.inputBorder, height: 1, indent: 56);
}
