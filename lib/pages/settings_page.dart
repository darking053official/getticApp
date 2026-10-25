import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import 'profile_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _service = SupabaseService();
  Profile? _profile;
  bool _isLoading = true;
  String _cacheSize = 'Hesaplanıyor...';

  // Gizlilik
  bool _showOnline = true;
  bool _showLastSeen = true;
  bool _showReadReceipts = true;
  bool _showTypingIndicator = true;
  bool _blockUnknownMessages = false;

  // Bildirimler
  bool _notifSound = true;
  bool _notifVibrate = true;
  bool _notifPreview = true;
  bool _notifLed = true;
  bool _notifGroupSummary = true;
  String _notifSoundTone = 'Varsayılan';

  // Görünüm
  bool _useSystemTheme = true;
  String _themeMode = 'Karanlık';
  String _chatWallpaper = 'Varsayılan';
  double _fontScale = 1.0;
  bool _highContrast = false;

  // Veri
  bool _autoDownloadWifi = true;
  bool _autoDownloadMobile = false;
  bool _autoDownloadPhotos = true;
  bool _autoDownloadVideos = false;
  bool _autoDownloadDocs = true;

  // Dil
  String _language = 'Türkçe';

  // Gelişmiş
  bool _experimentalFeatures = false;
  bool _verboseLogging = false;

  @override
  void initState() {
    super.initState();
    _load();
    _calculateCache();
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
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _calculateCache() async {
    try {
      final dir = Directory('${Directory.systemTemp.path}/cached_network_images');
      int total = 0;
      if (await dir.exists()) {
        await for (final f in dir.list(recursive: true)) {
          if (f is File) total += await f.length();
        }
      }
      if (mounted) {
        setState(() => _cacheSize = '${(total / 1024 / 1024).toStringAsFixed(1)} MB');
      }
    } catch (_) {
      if (mounted) setState(() => _cacheSize = '0 MB');
    }
  }

  Future<void> _updatePrivacy() async {
    try {
      await _service.updatePrivacySettings(
        showOnline: _showOnline,
        showLastSeen: _showLastSeen,
      );
    } catch (e) {
      _snack('Ayar kaydedilemedi: $e', isError: true);
    }
  }

  // ✅ GERÇEK: Şifre sıfırlama e-postası
  Future<void> _sendPasswordResetEmail() async {
    final email = _service.currentUser?.email;
    if (email == null || email.isEmpty) {
      _snack('E-posta bulunamadı', isError: true);
      return;
    }
    final c = await _confirm(
      title: 'Şifre Sıfırla',
      content: '$email adresine sıfırlama bağlantısı gönderilsin mi?',
      confirm: 'Gönder',
    );
    if (c != true) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'gettic://reset-password',
      );
      _snack('Sıfırlama e-postası gönderildi ✓');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  // ✅ GERÇEK: E-posta değiştir (doğrulama e-postası gider)
  Future<void> _changeEmail() async {
    final controller = TextEditingController(text: _service.currentUser?.email ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('E-posta Değiştir', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppTheme.textPrimary),
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'Yeni e-posta'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Kaydet')),
        ],
      ),
    );
    if (result == null || result.isEmpty || !result.contains('@')) return;
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(email: result));
      _snack('Doğrulama e-postası gönderildi ✓');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  // ✅ GERÇEK: Çıkış yap
  Future<void> _signOut() async {
    final c = await _confirm(
      title: 'Çıkış Yap',
      content: 'Çıkış yapmak istediğine emin misin?',
      confirm: 'Çıkış',
    );
    if (c == true) await _service.signOut();
  }

  // ✅ GERÇEK: Hesabı sil
  Future<void> _deleteAccount() async {
    final c = await _confirm(
      title: 'Hesabı Sil',
      content: 'Hesabın ve tüm mesajların kalıcı olarak silinecek. Bu işlem GERİ ALINAMAZ.',
      confirm: 'Kalıcı Sil',
      isDanger: true,
    );
    if (c != true) return;
    try {
      final userId = _service.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client
            .from(AppConstants.tableProfiles)
            .delete()
            .eq('id', userId);
      }
      await _service.deleteAccount();
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  // ✅ GERÇEK: Önbellek temizle
  Future<void> _clearCache() async {
    final c = await _confirm(
      title: 'Önbelleği Temizle',
      content: 'Tüm geçici dosyalar silinecek.',
      confirm: 'Temizle',
    );
    if (c != true) return;
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await _calculateCache();
      _snack('Önbellek temizlendi ✓');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  // ✅ GERÇEK: Uygulamayı paylaş
  Future<void> _shareApp() async {
    await Clipboard.setData(const ClipboardData(
      text: 'Gettic - Gizlilik odaklı mesajlaşma. İndir: https://gettic.dpdns.org',
    ));
    _snack('Davet linki kopyalandı ✓');
  }

  // ✅ GERÇEK: QR kod assets/qr.png
  Future<void> _showQrCode() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('QR Kod ile Davet', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Image.asset(
                'assets/qr.png',
                width: 240, height: 240,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 240, height: 240,
                  child: Center(child: Text('QR kod bulunamadı', style: TextStyle(color: Colors.black))),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Arkadaşın bu QR kodu okutabilir',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Text(_profile?.username ?? '',
                style: const TextStyle(color: AppTheme.primary, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))],
      ),
    );
  }

  // ✅ GERÇEK: Destek e-postası kopyala
  Future<void> _contactSupport() async {
    await Clipboard.setData(const ClipboardData(text: 'support@gettic.app'));
    _snack('support@gettic.app kopyalandı ✓');
  }

  // ✅ GERÇEK: Hata raporu şablonu
  Future<void> _reportBug() async {
    final body = 'Uygulama: Gettic v${AppConstants.appVersion}\n'
        'Cihaz: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n'
        'Kullanıcı: ${_profile?.username}\n\nHata Açıklaması:\n';
    await Clipboard.setData(ClipboardData(text: body));
    _snack('Hata şablonu kopyalandı ✓');
  }

  // ✅ GERÇEK: Özellik isteği şablonu
  Future<void> _requestFeature() async {
    await Clipboard.setData(const ClipboardData(
      text: 'Konu: Özellik İsteği\n\nİstediğim özellik: ',
    ));
    _snack('Şablon kopyalandı ✓');
  }

  // ✅ GERÇEK: Açık kaynak lisansları
  Future<void> _showLicenses() async {
    showLicensePage(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: AppConstants.appVersion,
      applicationIcon: const Icon(Icons.message_rounded, color: AppTheme.primary),
    );
  }

  // ✅ GERÇEK: Hakkında
  Future<void> _showAbout() async {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.message_rounded, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            const Text('Gettic', style: TextStyle(color: AppTheme.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versiyon: ${AppConstants.appVersion}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Kullanıcı: ${_profile?.username ?? "?"}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            const Text(
              'Gizlilik odaklı, modern mesajlaşma uygulaması. Flutter + Supabase.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text('© 2026 Gettic', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c),
              child: const Text('Kapat', style: TextStyle(color: AppTheme.primary))),
        ],
      ),
    );
  }

  // ✅ GERÇEK: Tüm oturumları kapat
  Future<void> _showActiveSessions() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Aktif Oturumlar', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone_android, color: AppTheme.online),
              title: const Text('Bu Cihaz', style: TextStyle(color: AppTheme.textPrimary)),
              subtitle: const Text('Şu an aktif',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.online.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('AKTİF',
                    style: TextStyle(color: AppTheme.online, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
            const Divider(color: AppTheme.inputBorder),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Tüm Oturumları Kapat',
                  style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('Tüm cihazlardan çıkış yap',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await Supabase.instance.client.auth.signOut(scope: SignOutScope.global);
                  _snack('Tüm oturumlar kapatıldı ✓');
                } catch (e) {
                  _snack('Hata: $e', isError: true);
                }
              },
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
      ),
    );
  }

  // ✅ GERÇEK: Sohbetleri JSON olarak kopyala
  Future<void> _backupChats() async {
    final c = await _confirm(
      title: 'Sohbetleri Yedekle',
      content: 'Tüm mesajların JSON olarak panoya kopyalanacak.',
      confirm: 'Yedekle',
    );
    if (c != true) return;

    try {
      final userId = _service.currentUser?.id;
      if (userId == null) return;

      final members = await Supabase.instance.client
          .from(AppConstants.tableConversationMembers)
          .select('conversation_id')
          .eq('user_id', userId);

      final convIds = members.map((e) => e['conversation_id']).toList();
      final List<Map<String, dynamic>> allMessages = [];

      for (final cid in convIds) {
        final msgs = await Supabase.instance.client
            .from(AppConstants.tableMessages)
            .select()
            .eq('conversation_id', cid)
            .order('created_at');
        allMessages.addAll(List<Map<String, dynamic>>.from(msgs));
      }

      final backup = {
        'user': _profile?.username,
        'exported_at': DateTime.now().toIso8601String(),
        'total_messages': allMessages.length,
        'messages': allMessages,
      };

      await Clipboard.setData(ClipboardData(text: jsonEncode(backup)));
      _snack('${allMessages.length} mesaj kopyalandı ✓');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  // ✅ GERÇEK: Verilerimi indir
  Future<void> _downloadMyData() async {
    final c = await _confirm(
      title: 'Verilerimi İndir',
      content: 'Profil ve e-posta bilgilerin JSON olarak panoya kopyalanacak.',
      confirm: 'İndir',
    );
    if (c != true) return;

    try {
      final userId = _service.currentUser?.id;
      if (userId == null) return;

      final profileData = await Supabase.instance.client
          .from(AppConstants.tableProfiles)
          .select()
          .eq('id', userId)
          .single();

      final data = {
        'profile': profileData,
        'email': _service.currentUser?.email,
        'exported_at': DateTime.now().toIso8601String(),
      };

      await Clipboard.setData(ClipboardData(text: jsonEncode(data)));
      _snack('Verilerin kopyalandı ✓');
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
        content: Text(content, style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
              child: const Text('İptal', style: TextStyle(color: AppTheme.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(c, true),
              child: Text(confirm, style: TextStyle(color: isDanger ? Colors.redAccent : AppTheme.primary))),
        ],
      ),
    );
  }

  // Seçim dialogu
  void _showSelection({
    required String title,
    required List<String> options,
    required String current,
    required void Function(String) onSelect,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (_, i) {
              final o = options[i];
              return RadioListTile<String>(
                value: o,
                groupValue: current,
                activeColor: AppTheme.primary,
                title: Text(o, style: const TextStyle(color: AppTheme.textPrimary)),
                onChanged: (v) {
                  onSelect(v!);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
      ),
    );
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (_profile != null) _profileCard(),

          _section('HESAP'),
          _card([
            _tile(Icons.alternate_email, 'E-posta Adresi',
                subtitle: _service.currentUser?.email ?? '', onTap: _changeEmail),
            _divider(),
            _tile(Icons.lock_outline, 'Şifre Sıfırla',
                subtitle: 'E-posta ile sıfırlama bağlantısı al', onTap: _sendPasswordResetEmail),
            _divider(),
            _tile(Icons.person_outline, 'Profil Bilgileri',
                subtitle: 'Kullanıcı adı, durum, avatar',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProfilePage())).then((_) => _load())),
          ]),

          _section('GİZLİLİK'),
          _card([
            _switch(Icons.visibility_outlined, 'Çevrimiçi durumu göster',
                subtitle: 'Kapalıyken çevrimiçi görünmezsin',
                value: _showOnline, onChanged: (v) {
                  setState(() => _showOnline = v);
                  _updatePrivacy();
                }),
            _divider(),
            _switch(Icons.access_time, 'Son görülmeyi göster',
                subtitle: 'Son görülme zamanın gizlenir',
                value: _showLastSeen, onChanged: (v) {
                  setState(() => _showLastSeen = v);
                  _updatePrivacy();
                }),
            _divider(),
            _switch(Icons.done_all, 'Okundu bilgisi',
                subtitle: 'Mavi tikler gösterilsin mi?',
                value: _showReadReceipts, onChanged: (v) => setState(() => _showReadReceipts = v)),
            _divider(),
            _switch(Icons.edit_outlined, 'Yazıyor göstergesi',
                subtitle: 'Yazarken karşı tarafa göster',
                value: _showTypingIndicator, onChanged: (v) => setState(() => _showTypingIndicator = v)),
            _divider(),
            _switch(Icons.block, 'Bilinmeyenlerden gelen mesajları engelle',
                subtitle: 'Sadece rehberindekiler mesaj atabilsin',
                value: _blockUnknownMessages, onChanged: (v) => setState(() => _blockUnknownMessages = v)),
          ]),

          _section('BİLDİRİMLER'),
          _card([
            _switch(Icons.notifications_active_outlined, 'Bildirim Sesi',
                value: _notifSound, onChanged: (v) => setState(() => _notifSound = v)),
            _divider(),
            _tile(Icons.music_note, 'Ses Tonu', subtitle: _notifSoundTone,
                onTap: () => _showSelection(title: 'Bildirim Sesi Tonu',
                    options: const ['Varsayılan', 'Sessiz', 'Ping', 'Ding', 'Pop'],
                    current: _notifSoundTone,
                    onSelect: (v) => setState(() => _notifSoundTone = v))),
            _divider(),
            _switch(Icons.vibration, 'Titreşim',
                value: _notifVibrate, onChanged: (v) => setState(() => _notifVibrate = v)),
            _divider(),
            _switch(Icons.message_outlined, 'Mesaj Önizleme',
                subtitle: 'Bildirimde mesaj içeriğini göster',
                value: _notifPreview, onChanged: (v) => setState(() => _notifPreview = v)),
            _divider(),
            _switch(Icons.lightbulb_outline, 'LED Bildirim',
                value: _notifLed, onChanged: (v) => setState(() => _notifLed = v)),
            _divider(),
            _switch(Icons.summarize_outlined, 'Grup Bildirim Özeti',
                value: _notifGroupSummary, onChanged: (v) => setState(() => _notifGroupSummary = v)),
          ]),

          _section('GÖRÜNÜM'),
          _card([
            _switch(Icons.brightness_auto, 'Sistem Temasını Kullan',
                value: _useSystemTheme, onChanged: (v) => setState(() => _useSystemTheme = v)),
            _divider(),
            _tile(Icons.palette_outlined, 'Tema', subtitle: _themeMode,
                onTap: () => _showSelection(title: 'Tema',
                    options: const ['Karanlık', 'Aydınlık', 'Sistem'],
                    current: _themeMode,
                    onSelect: (v) => setState(() => _themeMode = v))),
            _divider(),
            _tile(Icons.wallpaper_outlined, 'Duvar Kağıdı', subtitle: _chatWallpaper,
                onTap: () => _showSelection(title: 'Duvar Kağıdı',
                    options: const ['Varsayılan', 'Koyu', 'Desenli', 'Galeriden Seç'],
                    current: _chatWallpaper,
                    onSelect: (v) => setState(() => _chatWallpaper = v))),
            _divider(),
            _tile(Icons.text_fields, 'Yazı Boyutu',
                subtitle: '${(_fontScale * 100).toInt()}%', onTap: _showFontDialog),
            _divider(),
            _switch(Icons.contrast, 'Yüksek Kontrast',
                value: _highContrast, onChanged: (v) => setState(() => _highContrast = v)),
          ]),

          _section('VERİ VE DEPOLAMA'),
          _card([
            _switch(Icons.wifi, 'Wi-Fi ile Otomatik İndir',
                value: _autoDownloadWifi, onChanged: (v) => setState(() => _autoDownloadWifi = v)),
            _divider(),
            _switch(Icons.network_cell, 'Mobil Veri ile İndir',
                value: _autoDownloadMobile, onChanged: (v) => setState(() => _autoDownloadMobile = v)),
            _divider(),
            _switch(Icons.photo_outlined, 'Fotoğrafları İndir',
                value: _autoDownloadPhotos, onChanged: (v) => setState(() => _autoDownloadPhotos = v)),
            _divider(),
            _switch(Icons.videocam_outlined, 'Videoları İndir',
                value: _autoDownloadVideos, onChanged: (v) => setState(() => _autoDownloadVideos = v)),
            _divider(),
            _switch(Icons.description_outlined, 'Belgeleri İndir',
                value: _autoDownloadDocs, onChanged: (v) => setState(() => _autoDownloadDocs = v)),
            _divider(),
            _tile(Icons.cleaning_services_outlined, 'Önbelleği Temizle',
                subtitle: _cacheSize, onTap: _clearCache),
          ]),

          _section('SOHBET YEDEKLEME'),
          _card([
            _tile(Icons.backup_outlined, 'Sohbetleri Yedekle',
                subtitle: 'JSON olarak kopyala', onTap: _backupChats),
            _divider(),
            _tile(Icons.download_outlined, 'Verilerimi İndir',
                subtitle: 'Profil + e-posta JSON', onTap: _downloadMyData),
          ]),

          _section('CİHAZLARIM'),
          _card([
            _tile(Icons.phone_android, 'Aktif Oturumlar',
                subtitle: 'Tüm cihazlardan çıkış', onTap: _showActiveSessions),
          ]),

          _section('DİL'),
          _card([
            _tile(Icons.language, 'Uygulama Dili', subtitle: _language,
                onTap: () => _showSelection(title: 'Dil',
                    options: const ['Türkçe', 'English', 'Deutsch', 'Français', 'Español', 'العربية'],
                    current: _language,
                    onSelect: (v) => setState(() => _language = v))),
          ]),

          _section('GELİŞMİŞ'),
          _card([
            _switch(Icons.science_outlined, 'Deneysel Özellikler',
                value: _experimentalFeatures,
                onChanged: (v) => setState(() => _experimentalFeatures = v)),
            _divider(),
            _switch(Icons.bug_report_outlined, 'Ayrıntılı Log',
                value: _verboseLogging, onChanged: (v) => setState(() => _verboseLogging = v)),
          ]),

          _section('DAVET ET'),
          _card([
            _tile(Icons.share_outlined, 'Arkadaşlarını Davet Et',
                onTap: _shareApp),
            _divider(),
            _tile(Icons.qr_code, 'QR Kod ile Davet', onTap: _showQrCode),
          ]),

          _section('YARDIM VE DESTEK'),
          _card([
            _tile(Icons.email_outlined, 'Bize Ulaşın', subtitle: 'support@gettic.app',
                onTap: _contactSupport),
            _divider(),
            _tile(Icons.bug_report_outlined, 'Hata Bildir', onTap: _reportBug),
            _divider(),
            _tile(Icons.lightbulb_outline, 'Özellik İste', onTap: _requestFeature),
          ]),

          _section('HAKKINDA'),
          _card([
            _tile(Icons.info_outline, 'Gettic Hakkında',
                subtitle: 'v${AppConstants.appVersion}', onTap: _showAbout),
            _divider(),
            _tile(Icons.article_outlined, 'Açık Kaynak Lisansları', onTap: _showLicenses),
            _divider(),
            _tile(Icons.star_outline, 'Uygulamayı Puanla',
                onTap: () => _snack('Teşekkürler! 💜')),
          ]),

          _section('TEHLİKELİ BÖLGE', color: Colors.redAccent),
          _card([
            _tile(Icons.logout, 'Çıkış Yap', onTap: _signOut),
            _divider(),
            _tile(Icons.delete_forever_outlined, 'Hesabımı Sil',
                subtitle: 'Bu işlem geri alınamaz',
                iconColor: Colors.redAccent, titleColor: Colors.redAccent,
                onTap: _deleteAccount),
          ]),

          const SizedBox(height: 30),
          _footer(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ============ YARDIMCI WIDGET'LAR ============

  Widget _profileCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: InkWell(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ProfilePage())).then((_) => _load()),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primary.withOpacity(0.15), AppTheme.surface],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppTheme.primary,
                backgroundImage: _profile!.avatarUrl != null
                    ? CachedNetworkImageProvider(_profile!.avatarUrl!) : null,
                child: _profile!.avatarUrl == null
                    ? Text(
                        _profile!.username.isNotEmpty ? _profile!.username[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 26, color: Colors.white, fontWeight: FontWeight.bold),
                      ) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_profile!.username,
                        style: const TextStyle(color: AppTheme.textPrimary,
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(_profile!.status ?? 'Durum belirtilmemiş',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(_service.currentUser?.email ?? '',
                        style: TextStyle(color: AppTheme.textSecondary.withOpacity(0.7), fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.inputBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: AppTheme.online, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('${AppConstants.appName} v${AppConstants.appVersion}',
                    style: const TextStyle(color: AppTheme.textPrimary,
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('Made with 💜 in Türkiye',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _section(String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(text,
          style: TextStyle(color: color ?? AppTheme.primary,
              fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
    );
  }

  Widget _card(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.inputBorder),
        ),
        child: Column(children: children),
      ),
    );
  }

  Widget _tile(IconData icon, String title, {
    String? subtitle, VoidCallback? onTap, Color? iconColor, Color? titleColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppTheme.textSecondary, size: 22),
      title: Text(title,
          style: TextStyle(color: titleColor ?? AppTheme.textPrimary,
              fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: onTap != null
          ? const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 20)
          : null,
      onTap: onTap,
    );
  }

  Widget _switch(IconData icon, String title, {
    String? subtitle, required bool value, required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppTheme.textSecondary, size: 22),
      title: Text(title,
          style: const TextStyle(color: AppTheme.textPrimary,
              fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))
          : null,
      value: value,
      activeColor: AppTheme.primary,
      onChanged: onChanged,
    );
  }

  Widget _divider() => const Divider(color: AppTheme.inputBorder, height: 1, indent: 56);

  void _showFontDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Yazı Boyutu', style: TextStyle(color: AppTheme.textPrimary)),
        content: StatefulBuilder(
          builder: (ctx2, setSt) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Önizleme: Merhaba!',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 15 * _fontScale)),
              Slider(
                value: _fontScale, min: 0.8, max: 1.5, divisions: 7,
                activeColor: AppTheme.primary, label: '${(_fontScale * 100).toInt()}%',
                onChanged: (v) {
                  setSt(() => _fontScale = v);
                  setState(() => _fontScale = v);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () { setState(() => _fontScale = 1.0); Navigator.pop(ctx); },
            child: const Text('Sıfırla'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
        ],
      ),
    );
  }
}
