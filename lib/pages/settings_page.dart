// ============================================================
// lib/pages/settings_page.dart
//
// Ayarlar: hesap, gizlilik, bildirim, görünüm, veri, dil, gelişmiş.
// - Tercihler AppSettings üzerinden cihazda kalıcı olarak saklanır.
// - Hesap ve gizlilik (çevrimiçi / son görülme) sunucudaki profilde saklanır.
// - Geri tuşu: onBack verilirse onu çağırır, yoksa önceki sayfaya döner.
// Gerekenler: app_settings.dart, theme.dart, profile_page.dart, constants.dart
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_settings.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import 'profile_page.dart';

class SettingsPage extends StatefulWidget {
  /// Sekme olarak gösterildiğinde geri tuşu bu callback'i çağırır.
  /// Normal (push ile açılan) kullanımda boş bırakılır.
  final VoidCallback? onBack;

  const SettingsPage({super.key, this.onBack});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _service = SupabaseService();
  final AppSettings _s = AppSettings.instance;

  Profile? _profile;
  bool _loadingProfile = true;
  String _cacheSize = 'Hesaplanıyor...';

  // Sunucudaki gizlilik ayarları (profil)
  bool _showOnline = true;
  bool _showLastSeen = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _calculateCache();
  }

  // ==========================================
  // VERİ
  // ==========================================
  Future<void> _loadProfile() async {
    try {
      final p = await _service.getMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _showOnline = p?.showOnlineStatus ?? true;
        _showLastSeen = p?.showLastSeen ?? true;
        _loadingProfile = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _calculateCache() async {
    try {
      final dir =
          Directory('${Directory.systemTemp.path}/cached_network_images');
      var total = 0;
      if (await dir.exists()) {
        await for (final f in dir.list(recursive: true)) {
          if (f is File) total += await f.length();
        }
      }
      if (mounted) {
        setState(() => _cacheSize =
            '${(total / 1024 / 1024).toStringAsFixed(1)} MB');
      }
    } catch (_) {
      if (mounted) setState(() => _cacheSize = '0 MB');
    }
  }

  Future<void> _updateOnlinePrivacy() async {
    try {
      await _service.updatePrivacySettings(
        showOnline: _showOnline,
        showLastSeen: _showLastSeen,
      );
    } catch (e) {
      _snack('Ayar kaydedilemedi: $e', isError: true);
    }
  }

  // ==========================================
  // HESAP İŞLEMLERİ
  // ==========================================
  Future<void> _sendPasswordResetEmail() async {
    final email = _service.currentUser?.email;
    if (email == null || email.isEmpty) {
      _snack('E-posta bulunamadı', isError: true);
      return;
    }
    final ok = await _confirm(
      title: 'Şifre sıfırla',
      content: '$email adresine sıfırlama bağlantısı gönderilsin mi?',
      confirm: 'Gönder',
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'gettic://reset-password',
      );
      _snack('Sıfırlama e-postası gönderildi');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  Future<void> _changeEmail() async {
    final controller =
        TextEditingController(text: _service.currentUser?.email ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = ctx.appColors;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text('E-posta değiştir',
              style: TextStyle(color: c.textPrimary)),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'Yeni e-posta'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null || result.isEmpty || !result.contains('@')) return;
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(email: result));
      _snack('Doğrulama e-postası gönderildi');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  Future<void> _signOut() async {
    final ok = await _confirm(
      title: 'Çıkış yap',
      content: 'Çıkış yapmak istediğine emin misin?',
      confirm: 'Çıkış',
    );
    if (ok == true) await _service.signOut();
  }

  Future<void> _deleteAccount() async {
    final ok = await _confirm(
      title: 'Hesabı sil',
      content:
          'Hesabın ve tüm mesajların kalıcı olarak silinecek. Bu işlem geri alınamaz.',
      confirm: 'Kalıcı sil',
      isDanger: true,
    );
    if (ok != true) return;
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

  Future<void> _showActiveSessions() async {
    final c = context.appColors;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Aktif oturumlar',
            style: TextStyle(color: c.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.phone_android, color: c.online),
              title: Text('Bu cihaz',
                  style: TextStyle(color: c.textPrimary)),
              subtitle: Text('Şu an aktif',
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
            ),
            Divider(color: c.border),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout, color: c.danger),
              title: Text('Tüm oturumları kapat',
                  style: TextStyle(color: c.danger)),
              subtitle: Text('Tüm cihazlardan çıkış yap',
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await Supabase.instance.client.auth
                      .signOut(scope: SignOutScope.global);
                  _snack('Tüm oturumlar kapatıldı');
                } catch (e) {
                  _snack('Hata: $e', isError: true);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VERİ / YEDEK
  // ==========================================
  Future<void> _clearCache() async {
    final ok = await _confirm(
      title: 'Önbelleği temizle',
      content: 'Tüm geçici dosyalar silinecek.',
      confirm: 'Temizle',
    );
    if (ok != true) return;
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await _calculateCache();
      _snack('Önbellek temizlendi');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  Future<void> _backupChats() async {
    final ok = await _confirm(
      title: 'Sohbetleri yedekle',
      content: 'Tüm mesajların JSON olarak panoya kopyalanacak.',
      confirm: 'Yedekle',
    );
    if (ok != true) return;
    try {
      final userId = _service.currentUser?.id;
      if (userId == null) return;

      final members = await Supabase.instance.client
          .from(AppConstants.tableConversationMembers)
          .select('conversation_id')
          .eq('user_id', userId);

      final messages = <Map<String, dynamic>>[];
      for (final m in members) {
        final rows = await Supabase.instance.client
            .from(AppConstants.tableMessages)
            .select()
            .eq('conversation_id', m['conversation_id'])
            .order('created_at');
        messages.addAll(List<Map<String, dynamic>>.from(rows));
      }

      final backup = {
        'user': _profile?.username,
        'exported_at': DateTime.now().toIso8601String(),
        'total_messages': messages.length,
        'messages': messages,
      };
      await Clipboard.setData(ClipboardData(text: jsonEncode(backup)));
      _snack('${messages.length} mesaj kopyalandı');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  Future<void> _downloadMyData() async {
    final ok = await _confirm(
      title: 'Verilerimi indir',
      content: 'Profil ve e-posta bilgilerin JSON olarak panoya kopyalanacak.',
      confirm: 'İndir',
    );
    if (ok != true) return;
    try {
      final userId = _service.currentUser?.id;
      if (userId == null) return;
      final profile = await Supabase.instance.client
          .from(AppConstants.tableProfiles)
          .select()
          .eq('id', userId)
          .single();
      final data = {
        'profile': profile,
        'email': _service.currentUser?.email,
        'exported_at': DateTime.now().toIso8601String(),
      };
      await Clipboard.setData(ClipboardData(text: jsonEncode(data)));
      _snack('Verilerin kopyalandı');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  // ==========================================
  // DESTEK / HAKKINDA
  // ==========================================
  Future<void> _shareApp() async {
    await Clipboard.setData(const ClipboardData(
      text: 'Gettic - Gizlilik odaklı mesajlaşma. İndir: https://gettic.dpdns.org',
    ));
    _snack('Davet linki kopyalandı');
  }

  Future<void> _contactSupport() async {
    await Clipboard.setData(
        const ClipboardData(text: 'writetome@gettic.dpdns.org'));
    _snack('Adres kopyalandı');
  }

  Future<void> _reportBug() async {
    final body = 'Uygulama: ${AppConstants.appName} v${AppConstants.appVersion}\n'
        'Cihaz: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n'
        'Kullanıcı: ${_profile?.username ?? '-'}\n\nHata açıklaması:\n';
    await Clipboard.setData(ClipboardData(text: 'Konu: Hata bildirimi\n\n$body'));
    _snack('Hata şablonu kopyalandı. writetome@gettic.dpdns.org adresine gönder');
  }

  Future<void> _requestFeature() async {
    await Clipboard.setData(const ClipboardData(
      text: 'Konu: Özellik isteği\n\nİstediğim özellik: ',
    ));
    _snack('Şablon kopyalandı. writetome@gettic.dpdns.org adresine gönder');
  }

  void _showLicenses() {
    showLicensePage(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: AppConstants.appVersion,
      applicationIcon: Image.asset('assets/logo.png', width: 40, height: 40),
    );
  }

  Future<void> _showAbout() async {
    final c = context.appColors;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Row(
          children: [
            Image.asset('assets/logo.png', width: 32, height: 32),
            const SizedBox(width: 10),
            Text('Gettic', style: TextStyle(color: c.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sürüm: ${AppConstants.appVersion}',
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Kullanıcı: ${_profile?.username ?? '-'}',
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            Text(
              'Gizlilik odaklı mesajlaşma. Flutter ve Supabase ile geliştirildi.',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text('© 2026 Gettic',
                style: TextStyle(color: c.textHint, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SEÇİM / DİYALOG YARDIMCILARI
  // ==========================================
  void _selectOption({
    required String title,
    required List<String> options,
    required String current,
    required void Function(String) onSelect,
  }) {
    final c = context.appColors;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(title, style: TextStyle(color: c.textPrimary)),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final o in options)
                RadioListTile<String>(
                  value: o,
                  groupValue: current,
                  activeColor: c.primary,
                  title: Text(o, style: TextStyle(color: c.textPrimary)),
                  onChanged: (v) {
                    if (v != null) onSelect(v);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFontDialog() {
    final c = context.appColors;
    var value = _s.fontScale;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: c.surface,
          title: Text('Yazı boyutu', style: TextStyle(color: c.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Önizleme: Merhaba!',
                  style: TextStyle(
                      color: c.textPrimary, fontSize: 16 * value)),
              Slider(
                value: value,
                min: 0.8,
                max: 1.5,
                divisions: 7,
                activeColor: c.primary,
                label: '${(value * 100).round()}%',
                onChanged: (v) {
                  setSt(() => value = v);
                  _s.update(() => _s.fontScale = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _s.update(() => _s.fontScale = 1.0),
              child: const Text('Sıfırla'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tamam'),
            ),
          ],
        ),
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
            child: const Text('İptal'),
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

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final c = context.appColors;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? c.danger : c.primary,
        behavior: SnackBarBehavior.floating,
      ));
  }

  void _back() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.maybePop(context);
    }
  }

  // ==========================================
  // UI
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Geri',
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
        ),
        title: const Text('Ayarlar'),
      ),
      body: ListenableBuilder(
        listenable: _s,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (_loadingProfile)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(color: c.primary),
                  ),
                )
              else if (_profile != null)
                _profileCard(c),

              _section('Hesap', c),
              _card(c, [
                _tile(c, Icons.alternate_email, 'E-posta adresi',
                    subtitle: _service.currentUser?.email ?? '',
                    onTap: _changeEmail),
                _divider(c),
                _tile(c, Icons.lock_outline, 'Şifre sıfırla',
                    subtitle: 'E-posta ile sıfırlama bağlantısı al',
                    onTap: _sendPasswordResetEmail),
                _divider(c),
                _tile(c, Icons.person_outline, 'Profil bilgileri',
                    subtitle: 'Kullanıcı adı, durum, avatar',
                    onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ProfilePage()),
                        ).then((_) => _loadProfile())),
              ]),

              _section('Gizlilik', c),
              _card(c, [
                _switch(c, Icons.visibility_outlined,
                    'Çevrimiçi durumu göster',
                    subtitle: 'Kapalıyken çevrimiçi görünmezsin',
                    value: _showOnline, onChanged: (v) {
                  setState(() => _showOnline = v);
                  _updateOnlinePrivacy();
                }),
                _divider(c),
                _switch(c, Icons.access_time, 'Son görülmeyi göster',
                    subtitle: 'Son görülme zamanın gizlenir',
                    value: _showLastSeen, onChanged: (v) {
                  setState(() => _showLastSeen = v);
                  _updateOnlinePrivacy();
                }),
                _divider(c),
                _switch(c, Icons.done_all, 'Okundu bilgisi',
                    subtitle: 'Mavi tikler gösterilsin mi?',
                    value: _s.showReadReceipts,
                    onChanged: (v) => _s.update(
                        () => _s.showReadReceipts = v)),
                _divider(c),
                _switch(c, Icons.edit_outlined, 'Yazıyor göstergesi',
                    subtitle: 'Yazarken karşı tarafa göster',
                    value: _s.showTypingIndicator,
                    onChanged: (v) => _s.update(
                        () => _s.showTypingIndicator = v)),
                _divider(c),
                _switch(c, Icons.block, 'Bilinmeyenlerden mesajı engelle',
                    subtitle: 'Yalnızca tanıdığın kişiler mesaj atabilsin',
                    value: _s.blockUnknownMessages,
                    onChanged: (v) => _s.update(
                        () => _s.blockUnknownMessages = v)),
              ]),

              _section('Bildirimler', c),
              _card(c, [
                _switch(c, Icons.notifications_active_outlined,
                    'Bildirim sesi',
                    value: _s.notifSound,
                    onChanged: (v) =>
                        _s.update(() => _s.notifSound = v)),
                _divider(c),
                _tile(c, Icons.music_note_outlined, 'Ses tonu',
                    subtitle: _s.notifSoundTone,
                    onTap: () => _selectOption(
                          title: 'Bildirim sesi',
                          options: const [
                            'Varsayılan',
                            'Sessiz',
                            'Ping',
                            'Ding',
                            'Pop'
                          ],
                          current: _s.notifSoundTone,
                          onSelect: (v) => _s.update(
                              () => _s.notifSoundTone = v),
                        )),
                _divider(c),
                _switch(c, Icons.vibration, 'Titreşim',
                    value: _s.notifVibrate,
                    onChanged: (v) =>
                        _s.update(() => _s.notifVibrate = v)),
                _divider(c),
                _switch(c, Icons.message_outlined, 'Mesaj önizleme',
                    subtitle: 'Bildirimde mesaj içeriğini göster',
                    value: _s.notifPreview,
                    onChanged: (v) =>
                        _s.update(() => _s.notifPreview = v)),
                _divider(c),
                _switch(c, Icons.lightbulb_outline, 'LED bildirimi',
                    value: _s.notifLed,
                    onChanged: (v) => _s.update(() => _s.notifLed = v)),
                _divider(c),
                _switch(c, Icons.summarize_outlined,
                    'Grup bildirim özeti',
                    value: _s.notifGroupSummary,
                    onChanged: (v) =>
                        _s.update(() => _s.notifGroupSummary = v)),
              ]),

              _section('Görünüm', c),
              _card(c, [
                _switch(c, Icons.brightness_auto, 'Sistem temasını kullan',
                    value: _s.useSystemTheme,
                    onChanged: (v) =>
                        _s.update(() => _s.useSystemTheme = v)),
                _divider(c),
                _tile(c, Icons.palette_outlined, 'Tema',
                    subtitle: _s.themeMode,
                    trailing: !_s.useSystemTheme,
                    onTap: _s.useSystemTheme
                        ? null
                        : () => _selectOption(
                              title: 'Tema',
                              options: const [
                                'Karanlık',
                                'Aydınlık',
                              ],
                              current: _s.themeMode,
                              onSelect: (v) =>
                                  _s.update(() => _s.themeMode = v),
                            )),
                _divider(c),
                _tile(c, Icons.wallpaper_outlined, 'Sohbet duvar kağıdı',
                    subtitle: _s.chatWallpaper,
                    onTap: () => _selectOption(
                          title: 'Duvar kağıdı',
                          options: const [
                            'Varsayılan',
                            'Koyu',
                            'Desenli',
                          ],
                          current: _s.chatWallpaper,
                          onSelect: (v) =>
                              _s.update(() => _s.chatWallpaper = v),
                        )),
                _divider(c),
                _tile(c, Icons.text_fields, 'Yazı boyutu',
                    subtitle: '${(_s.fontScale * 100).round()}%',
                    onTap: _showFontDialog),
                _divider(c),
                _switch(c, Icons.contrast, 'Yüksek kontrast',
                    value: _s.highContrast,
                    onChanged: (v) =>
                        _s.update(() => _s.highContrast = v)),
              ]),

              _section('Veri ve depolama', c),
              _card(c, [
                _switch(c, Icons.wifi, 'Wi-Fi ile otomatik indir',
                    value: _s.autoDownloadWifi,
                    onChanged: (v) =>
                        _s.update(() => _s.autoDownloadWifi = v)),
                _divider(c),
                _switch(c, Icons.network_cell, 'Mobil veriyle otomatik indir',
                    value: _s.autoDownloadMobile,
                    onChanged: (v) =>
                        _s.update(() => _s.autoDownloadMobile = v)),
                _divider(c),
                _switch(c, Icons.photo_outlined, 'Fotoğrafları indir',
                    value: _s.autoDownloadPhotos,
                    onChanged: (v) =>
                        _s.update(() => _s.autoDownloadPhotos = v)),
                _divider(c),
                _switch(c, Icons.videocam_outlined, 'Videoları indir',
                    value: _s.autoDownloadVideos,
                    onChanged: (v) =>
                        _s.update(() => _s.autoDownloadVideos = v)),
                _divider(c),
                _switch(c, Icons.description_outlined, 'Belgeleri indir',
                    value: _s.autoDownloadDocs,
                    onChanged: (v) =>
                        _s.update(() => _s.autoDownloadDocs = v)),
                _divider(c),
                _tile(c, Icons.cleaning_services_outlined,
                    'Önbelleği temizle',
                    subtitle: _cacheSize, onTap: _clearCache),
              ]),

              _section('Yedekleme', c),
              _card(c, [
                _tile(c, Icons.backup_outlined, 'Sohbetleri yedekle',
                    subtitle: 'JSON olarak panoya kopyala',
                    onTap: _backupChats),
                _divider(c),
                _tile(c, Icons.download_outlined, 'Verilerimi indir',
                    subtitle: 'Profil ve e-posta JSON',
                    onTap: _downloadMyData),
              ]),

              _section('Oturumlar', c),
              _card(c, [
                _tile(c, Icons.devices_outlined, 'Aktif oturumlar',
                    subtitle: 'Tüm cihazlardan çıkış',
                    onTap: _showActiveSessions),
              ]),

              _section('Dil', c),
              _card(c, [
                _tile(c, Icons.language, 'Uygulama dili',
                    subtitle: _s.language,
                    onTap: () => _selectOption(
                          title: 'Dil',
                          options: const [
                            'Türkçe',
                            'English',
                            'Deutsch',
                            'Français',
                            'Español',
                            'العربية',
                          ],
                          current: _s.language,
                          onSelect: (v) =>
                              _s.update(() => _s.language = v),
                        )),
              ]),

              _section('Gelişmiş', c),
              _card(c, [
                _switch(c, Icons.science_outlined, 'Deneysel özellikler',
                    value: _s.experimentalFeatures,
                    onChanged: (v) =>
                        _s.update(() => _s.experimentalFeatures = v)),
                _divider(c),
                _switch(c, Icons.bug_report_outlined, 'Ayrıntılı log',
                    value: _s.verboseLogging,
                    onChanged: (v) =>
                        _s.update(() => _s.verboseLogging = v)),
              ]),

              _section('Davet et', c),
              _card(c, [
                _tile(c, Icons.share_outlined, 'Arkadaşlarını davet et',
                    onTap: _shareApp),
              ]),

              _section('Yardım ve destek', c),
              _card(c, [
                _tile(c, Icons.email_outlined, 'Bize ulaşın',
                    subtitle: 'writetome@gettic.dpdns.org',
                    onTap: _contactSupport),
                _divider(c),
                _tile(c, Icons.bug_report_outlined, 'Hata bildir',
                    onTap: _reportBug),
                _divider(c),
                _tile(c, Icons.lightbulb_outline, 'Özellik iste',
                    onTap: _requestFeature),
              ]),

              _section('Hakkında', c),
              _card(c, [
                _tile(c, Icons.info_outline, 'Gettic hakkında',
                    subtitle: 'v${AppConstants.appVersion}',
                    onTap: _showAbout),
                _divider(c),
                _tile(c, Icons.article_outlined, 'Açık kaynak lisansları',
                    onTap: _showLicenses),
              ]),

              _section('Tehlikeli bölge', c, color: c.danger),
              _card(c, [
                _tile(c, Icons.logout, 'Çıkış yap', onTap: _signOut),
                _divider(c),
                _tile(c, Icons.delete_forever_outlined, 'Hesabımı sil',
                    subtitle: 'Bu işlem geri alınamaz',
                    iconColor: c.danger,
                    titleColor: c.danger,
                    onTap: _deleteAccount),
              ]),

              const SizedBox(height: 28),
              _footer(c),
            ],
          );
        },
      ),
    );
  }

  // ---------- Parçalar ----------
  Widget _profileCard(AppColors c) {
    final p = _profile!;
    final hasAvatar = p.avatarUrl != null && p.avatarUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfilePage()),
          ).then((_) => _loadProfile()),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: c.primary,
                  backgroundImage: hasAvatar
                      ? CachedNetworkImageProvider(p.avatarUrl!)
                      : null,
                  child: !hasAvatar
                      ? Text(
                          p.username.isNotEmpty
                              ? p.username[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 24,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.status ?? 'Durum belirtilmemiş',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: c.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String text, AppColors c, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color ?? c.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _card(AppColors c, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }

  Widget _tile(
    AppColors c,
    IconData icon,
    String title, {
    String? subtitle,
    VoidCallback? onTap,
    Color? iconColor,
    Color? titleColor,
    bool trailing = true,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? c.textSecondary, size: 22),
      title: Text(
        title,
        style: TextStyle(
          color: onTap == null && titleColor == null
              ? c.textHint
              : (titleColor ?? c.textPrimary),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(color: c.textSecondary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis)
          : null,
      trailing: (onTap != null && trailing)
          ? Icon(Icons.chevron_right, color: c.textSecondary, size: 20)
          : null,
      onTap: onTap,
    );
  }

  Widget _switch(
    AppColors c,
    IconData icon,
    String title, {
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: c.textSecondary, size: 22),
      title: Text(title,
          style: TextStyle(
              color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(color: c.textSecondary, fontSize: 12))
          : null,
      value: value,
      activeColor: c.primary,
      onChanged: onChanged,
    );
  }

  Widget _divider(AppColors c) =>
      Divider(color: c.border, height: 1, indent: 56);

  Widget _footer(AppColors c) {
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: c.online, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  '${AppConstants.appName} v${AppConstants.appVersion}',
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Türkiye'de sevgiyle yapıldı",
            style: TextStyle(color: c.textHint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
