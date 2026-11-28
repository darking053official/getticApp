import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_settings.dart';
import '../core/theme.dart';
import '../models/profile.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';

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
  bool _muteAll = false;

  // İstatistikler
  int _totalMessages = 0;
  int _totalConversations = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _statusController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await _service.getMyProfile();
      final muted = await _loadMuteAll();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _usernameController.text = p?.username ?? '';
        _statusController.text = p?.status ?? '';
        _bioController.text = p?.fullName ?? '';
        _showOnline = p?.showOnlineStatus ?? true;
        _showLastSeen = p?.showLastSeen ?? true;
        _muteAll = muted;
        _isLoading = false;
      });
      _loadStats();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _loadMuteAll() async {
    try {
      final uid = _service.currentUser?.id;
      if (uid == null) return false;
      final row = await Supabase.instance.client
          .from('profiles')
          .select('notifications_muted')
          .eq('id', uid)
          .maybeSingle();
      return row?['notifications_muted'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadStats() async {
    try {
      final userId = _service.currentUser?.id;
      if (userId == null) return;
      final convs = await _service.getMyConversationsWithUnread();
      int count = 0;
      for (final m in convs) {
        final msgs = await _service.getMessages(m['conversation_id']);
        count += msgs.where((msg) => msg.senderId == userId).length;
      }
      if (mounted) {
        setState(() {
          _totalConversations = convs.length;
          _totalMessages = count;
        });
      }
    } catch (e) {
      debugPrint('İstatistik hatası: $e');
    }
  }

  // ---------- Profil fotoğrafı ----------

  Future<void> _pickAvatar() async {
    final c = context.appColors;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: c.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text('Profil fotoğrafı',
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: c.primary),
              title: Text('Galeriden seç',
                  style: TextStyle(color: c.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined, color: c.primary),
              title:
                  Text('Kamera ile çek', style: TextStyle(color: c.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            if (_profile?.avatarUrl != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: c.danger),
                title: Text('Fotoğrafı kaldır', style: TextStyle(color: c.danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeAvatar();
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
    final ok = await _confirm(
      title: 'Fotoğrafı kaldır',
      content: 'Profil fotoğrafın kaldırılsın mı?',
      confirm: 'Kaldır',
      isDanger: true,
    );
    if (ok != true) return;
    try {
      final userId = _service.currentUser?.id;
      if (userId == null) return;
      await _service.updateProfile(userId, {'avatar_url': null});
      setState(() => _localAvatar = null);
      await _load();
      _snack('Fotoğraf kaldırıldı');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  void _showFullAvatar() {
    final url = _profile?.avatarUrl;
    if (url == null) return;
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
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => Center(
                    child: CircularProgressIndicator(
                        color: context.appColors.primary),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
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

  // ---------- Kaydetme ----------

  Future<void> _saveProfile() async {
    final username = _usernameController.text.trim();
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

  Future<void> _setMuteAll(bool v) async {
    setState(() => _muteAll = v);
    try {
      final uid = _service.currentUser?.id;
      if (uid == null) return;
      await Supabase.instance.client
          .from('profiles')
          .update({'notifications_muted': v}).eq('id', uid);
    } catch (e) {
      if (mounted) setState(() => _muteAll = !v);
      _snack('Kaydedilemedi: $e', isError: true);
    }
  }

  Future<void> _shareProfile() async {
    final username = _profile?.username ?? '';
    await Clipboard.setData(ClipboardData(
      text: 'Gettic\'te beni bul: @$username\nhttps://gettic.dpdns.org',
    ));
    _snack('Profil linki kopyalandı');
  }

  // ---------- Yardımcılar ----------

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final c = context.appColors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? c.danger : c.primary,
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
    final c = context.appColors;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(title, style: TextStyle(color: c.textPrimary)),
        content: Text(content, style: TextStyle(color: c.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirm,
                style: TextStyle(color: isDanger ? c.danger : c.primary)),
          ),
        ],
      ),
    );
  }

  String _memberSince() {
    try {
      final createdAt = _service.currentUser?.createdAt;
      if (createdAt == null) return 'Bilinmiyor';
      return DateFormat('d MMMM yyyy', 'tr_TR')
          .format(DateTime.parse(createdAt));
    } catch (_) {
      return 'Bilinmiyor';
    }
  }

  int _memberDays() {
    try {
      final createdAt = _service.currentUser?.createdAt;
      if (createdAt == null) return 0;
      return DateTime.now().difference(DateTime.parse(createdAt)).inDays;
    } catch (_) {
      return 0;
    }
  }

  // ---------- Arayüz ----------

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    if (_isLoading) {
      return Scaffold(
        backgroundColor: c.background,
        body: Center(child: CircularProgressIndicator(color: c.primary)),
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      body: CustomScrollView(
        slivers: [
          _buildHeader(c),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_profile?.fullName != null &&
                      _profile!.fullName!.isNotEmpty) ...[
                    _bioCard(c),
                    const SizedBox(height: 16),
                  ],
                  _statsCard(c),
                  const SizedBox(height: 24),

                  _sectionHeader('Kişisel bilgiler', c),
                  _card(c, [
                    _textField(c,
                        controller: _usernameController,
                        icon: Icons.alternate_email,
                        label: 'Kullanıcı adı',
                        hint: 'kullanici_adi'),
                    _divider(c),
                    _textField(c,
                        controller: _statusController,
                        icon: Icons.mood_outlined,
                        label: 'Durum',
                        hint: 'Örn: Kod yazıyorum...'),
                    _divider(c),
                    _textField(c,
                        controller: _bioController,
                        icon: Icons.info_outline,
                        label: 'Hakkımda',
                        hint: 'Kendinden bahset...',
                        maxLines: 3),
                  ]),
                  const SizedBox(height: 24),

                  _sectionHeader('Gizlilik ve bildirimler', c),
                  _card(c, [
                    _switchTile(c,
                        icon: Icons.visibility_outlined,
                        title: 'Çevrimiçi durumumu göster',
                        subtitle: 'Kapalıyken çevrimiçi görünmezsin',
                        value: _showOnline,
                        onChanged: (v) => setState(() => _showOnline = v)),
                    _divider(c),
                    _switchTile(c,
                        icon: Icons.access_time,
                        title: 'Son görülmemi göster',
                        subtitle: 'Son görülme zamanın gizlenir',
                        value: _showLastSeen,
                        onChanged: (v) => setState(() => _showLastSeen = v)),
                    _divider(c),
                    _switchTile(c,
                        icon: Icons.done_all,
                        title: 'Okundu bilgisi',
                        subtitle: 'Kapalıyken mesajlar okundu işaretlenmez',
                        value: AppSettings.instance.showReadReceipts,
                        onChanged: (v) => AppSettings.instance
                            .update(() => AppSettings.instance.showReadReceipts = v)
                            .then((_) => setState(() {}))),
                    _divider(c),
                    _switchTile(c,
                        icon: Icons.notifications_off_outlined,
                        title: 'Tüm bildirimleri sessize al',
                        subtitle: 'Açıkken sana bildirim gelmez',
                        value: _muteAll,
                        onChanged: _setMuteAll),
                  ]),
                  const SizedBox(height: 24),

                  _sectionHeader('Hesap', c),
                  _card(c, [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              color: c.textSecondary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Hesap oluşturma',
                                    style: TextStyle(
                                        color: c.textSecondary, fontSize: 12)),
                                const SizedBox(height: 2),
                                Text(_memberSince(),
                                    style: TextStyle(
                                        color: c.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Değişiklikleri kaydet',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
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

  Widget _buildHeader(AppColors c) {
    final name = _profile?.username ?? '';
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      stretch: true,
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: c.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.share_outlined, color: c.textPrimary),
          onPressed: _shareProfile,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.primary.withOpacity(0.35), c.background],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 28),
                GestureDetector(
                  onTap: _showFullAvatar,
                  child: Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [c.primary, c.primary.withOpacity(0.4)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: c.primary.withOpacity(0.35),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 56,
                          backgroundColor: c.surface,
                          backgroundImage: _localAvatar != null
                              ? FileImage(_localAvatar!) as ImageProvider
                              : (_profile?.avatarUrl != null
                                  ? CachedNetworkImageProvider(
                                      _profile!.avatarUrl!)
                                  : null),
                          child: (_localAvatar == null &&
                                  _profile?.avatarUrl == null)
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                    fontSize: 44,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _isUploadingAvatar ? null : _pickAvatar,
                          child: Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: c.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.background, width: 3),
                            ),
                            child: _isUploadingAvatar
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.camera_alt,
                                    size: 20, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '@$name',
                  style: TextStyle(color: c.textSecondary, fontSize: 14),
                ),
                if (_profile?.status != null &&
                    _profile!.status!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.surface.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      _profile!.status!,
                      style: TextStyle(color: c.textPrimary, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bioCard(AppColors c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HAKKIMDA',
              style: TextStyle(
                  color: c.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4)),
          const SizedBox(height: 8),
          Text(_profile!.fullName!,
              style: TextStyle(color: c.textPrimary, fontSize: 15, height: 1.5)),
        ],
      ),
    );
  }

  Widget _statsCard(AppColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          _statItem(c, '$_totalConversations', 'Sohbet', Icons.chat_bubble_outline),
          _statDivider(c),
          _statItem(c, '$_totalMessages', 'Mesaj', Icons.message_outlined),
          _statDivider(c),
          _statItem(c, '${_memberDays()}', 'Gün', Icons.calendar_today_outlined),
        ],
      ),
    );
  }

  Widget _statItem(AppColors c, String value, String label, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: c.primary, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: c.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _statDivider(AppColors c) =>
      Container(width: 1, height: 40, color: c.border);

  Widget _sectionHeader(String text, AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _card(AppColors c, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border.withOpacity(0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _textField(
    AppColors c, {
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
        style: TextStyle(color: c.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: c.textSecondary),
          hintStyle: TextStyle(color: c.textHint),
          prefixIcon: Icon(icon, color: c.textSecondary, size: 22),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      ),
    );
  }

  Widget _switchTile(
    AppColors c, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: c.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: c.primary, size: 20),
      ),
      title: Text(title,
          style: TextStyle(
              color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(color: c.textSecondary, fontSize: 12)),
      value: value,
      activeColor: c.primary,
      onChanged: onChanged,
    );
  }

  Widget _divider(AppColors c) =>
      Divider(color: c.border.withOpacity(0.6), height: 1, indent: 68, endIndent: 16);
}
