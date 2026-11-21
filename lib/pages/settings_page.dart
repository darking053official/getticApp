// ============================================================
// lib/pages/settings_page.dart
// (.txt olarak verildi. Projeye eklerken adını settings_page.dart yapın.)
//
// Her seçenek çalışır:
//  - Hesap / gizlilik (online, son görülme): sunucudaki profil
//  - Güvenlik: kasa şifresi değiştirme, otomatik kilit, senkron yönetimi
//  - Görünüm / medya / bildirim: AppSettings (uygulama genelinde etkili)
//  - Veri: şifreli dışa aktarma, ayar yedekleme, önbellek yönetimi
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_settings.dart';
import '../core/constants.dart';
import '../core/security.dart';
import '../core/theme.dart';
import '../models/profile.dart';
import '../services/cloud_notebook.dart';
import '../services/cloud_pass.dart';
import '../services/cloud_vaults.dart';
import '../services/app_lock.dart';
import 'device_link_page.dart';
import '../services/e2ee_backup.dart';
import '../services/notification_privacy.dart';
import '../services/web_crypto.dart';
import '../services/supabase_service.dart';
import 'profile_page.dart';

const String _kExportPrefix = 'GETTIC-EXPORT-1:';

class SettingsPage extends StatefulWidget {
  /// Sekme olarak gösterildiğinde geri tuşu bu callback'i çağırır.
  /// Push ile açıldığında boş bırakılır.
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
  bool _showOnline = true;
  bool _showLastSeen = true;
  int _cacheBytes = -1; // -1: hesaplanıyor
  bool _busy = false;

  static const Map<int, String> _lockOptions = {
    0: 'Kapalı',
    1: '1 dakika',
    2: '2 dakika',
    5: '5 dakika',
    15: '15 dakika',
  };

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _refreshCacheSize();
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

  Future<void> _savePrivacy() async {
    try {
      await _service.updatePrivacySettings(
        showOnline: _showOnline,
        showLastSeen: _showLastSeen,
      );
    } catch (e) {
      _snack('Ayar kaydedilemedi: $e', isError: true);
    }
  }

  /// flutter_cache_manager'ın varsayılan klasörü (cached_network_image bunu kullanır)
  Future<int> _measureCache() async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/libCachedImageData');
      var total = 0;
      if (await dir.exists()) {
        await for (final f in dir.list(recursive: true)) {
          if (f is File) total += await f.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _refreshCacheSize() async {
    final bytes = await _measureCache();
    if (mounted) setState(() => _cacheBytes = bytes);
  }

  Future<void> _clearCache() async {
    final ok = await _confirm(
      title: 'Önbelleği temizle',
      content: 'İndirilmiş resim ve medya önbelleği silinecek. Mesajlar etkilenmez.',
      confirm: 'Temizle',
    );
    if (ok != true) return;
    try {
      await DefaultCacheManager().emptyCache();
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await _refreshCacheSize();
      _snack('Önbellek temizlendi');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  // ==========================================
  // HESAP
  // ==========================================
  Future<void> _changeEmail() async {
    final controller =
        TextEditingController(text: _service.currentUser?.email ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = ctx.appColors;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text('E-posta değiştir', style: TextStyle(color: c.textPrimary)),
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
    if (result == null || !result.contains('@')) return;
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(email: result));
      _snack('Doğrulama e-postası gönderildi');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

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
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      _snack('Sıfırlama e-postası gönderildi');
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
        title: Text('Aktif oturumlar', style: TextStyle(color: c.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.phone_android, color: c.online),
              title: Text('Bu cihaz', style: TextStyle(color: c.textPrimary)),
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

  Future<void> _signOut() async {
    final ok = await _confirm(
      title: 'Çıkış yap',
      content: 'Çıkış yapmak istediğine emin misin?',
      confirm: 'Çıkış',
    );
    if (ok == true) {
      CloudVaults.lockAll();
      await _service.signOut();
    }
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
      CloudVaults.lockAll();
      await _service.deleteAccount();
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  // ==========================================
  // GÜVENLİK
  // ==========================================
  /// Ürün kasasının parolasını değiştirir (Pass ya da Notebook).
  Future<void> _changeProductPassword(CloudVault vault, String label) async {
    final old = await _askPassword(
      title: '$label: mevcut şifre',
      hint: 'Mevcut şifren',
    );
    if (old == null) return;

    final neu = await _askPassword(
      title: '$label: yeni şifre',
      hint: 'En az 8 karakter',
      withConfirm: true,
    );
    if (neu == null) return;

    setState(() => _busy = true);
    try {
      await vault.changePassword(old, neu);
      _snack('$label şifresi değiştirildi');
    } on SecurityException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('Hata: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _lockVaultNow() {
    CloudVaults.lockAll();
    _snack('Kasa kilitlendi');
  }

  // ==========================================
  // VERİ DIŞA / İÇE AKTARMA
  // ==========================================
  /// Profil + mesajlar + ayarlar, parolayla şifrelenip panoya kopyalanır.
  Future<void> _exportEncrypted() async {
    final pw = await _askPassword(
      title: 'Dışa aktarma şifresi',
      hint: 'Dosyayı açmak için bu şifre gerekir',
      withConfirm: true,
    );
    if (pw == null) return;

    setState(() => _busy = true);
    try {
      final uid = _service.currentUser?.id;
      if (uid == null) throw Exception('Oturum bulunamadı');

      final profile = await Supabase.instance.client
          .from(AppConstants.tableProfiles)
          .select()
          .eq('id', uid)
          .single();

      final members = await Supabase.instance.client
          .from(AppConstants.tableConversationMembers)
          .select('conversation_id')
          .eq('user_id', uid);

      final messages = <Map<String, dynamic>>[];
      for (final m in members) {
        final rows = await Supabase.instance.client
            .from(AppConstants.tableMessages)
            .select()
            .eq('conversation_id', m['conversation_id'])
            .order('created_at');
        messages.addAll(List<Map<String, dynamic>>.from(rows));
      }

      final payload = jsonEncode({
        'app': 'gettic',
        'version': AppConstants.appVersion,
        'exported_at': DateTime.now().toIso8601String(),
        'email': _service.currentUser?.email,
        'profile': profile,
        'settings': _s.toJson(),
        'messages': messages,
      });

      final enc = await Crypto.encryptStringWithPassword(payload, pw);
      await Clipboard.setData(ClipboardData(text: '$_kExportPrefix$enc'));
      _snack('Şifreli dışa aktarım kopyalandı (${messages.length} mesaj)');
    } catch (e) {
      _snack('Dışa aktarılamadı: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportSettings() async {
    await Clipboard.setData(
        ClipboardData(text: jsonEncode({'app': 'gettic', 'settings': _s.toJson()})));
    _snack('Ayarlar panoya kopyalandı');
  }

  Future<void> _importSettings() async {
    final ctrl = TextEditingController();
    final c = context.appColors;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Ayarları içe aktar', style: TextStyle(color: c.textPrimary)),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Dışa aktarılmış ayar metnini buraya yapıştır',
            suffixIcon: IconButton(
              tooltip: 'Panodan yapıştır',
              icon: const Icon(Icons.content_paste),
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if (d?.text != null) ctrl.text = d!.text!;
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.trim().isEmpty) return;

    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      final settings = map['settings'];
      if (map['app'] != 'gettic' || settings is! Map) {
        throw const FormatException('Geçersiz ayar dosyası');
      }
      await _s.importJson(Map<String, dynamic>.from(settings));
      _snack('Ayarlar uygulandı');
    } catch (_) {
      _snack('Geçersiz ayar metni', isError: true);
    }
  }

  Future<void> _resetSettings() async {
    final ok = await _confirm(
      title: 'Ayarları sıfırla',
      content: 'Tüm uygulama ayarları varsayılan değerlere döner. Hesabın ve mesajların etkilenmez.',
      confirm: 'Sıfırla',
      isDanger: true,
    );
    if (ok != true) return;
    await _s.reset();
    _snack('Ayarlar sıfırlandı');
  }

  // ==========================================
  // DESTEK / HAKKINDA
  // ==========================================
  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack(message);
  }

  void _showLicenses() {
    showLicensePage(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: AppConstants.appVersion,
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
            Text('Gizlilik odaklı mesajlaşma. Flutter ve Supabase ile geliştirildi.',
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            Text('© 2026 Gettic', style: TextStyle(color: c.textHint, fontSize: 11)),
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
  // DİYALOG YARDIMCILARI
  // ==========================================
  Future<T?> _pick<T>({
    required String title,
    required Map<T, String> options,
    required T current,
    required void Function(T) onSelect,
  }) {
    final c = context.appColors;
    return showDialog<T>(
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
              for (final e in options.entries)
                RadioListTile<T>(
                  value: e.key,
                  groupValue: current,
                  activeColor: c.primary,
                  title: Text(e.value, style: TextStyle(color: c.textPrimary)),
                  onChanged: (v) {
                    Navigator.pop(ctx, v);
                    if (v != null) onSelect(v);
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
                  style: TextStyle(color: c.textPrimary, fontSize: 16 * value)),
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

  /// Parola sorar. [withConfirm] true ise tekrar ister ve güç kontrolü yapar.
  Future<String?> _askPassword({
    required String title,
    required String hint,
    bool withConfirm = false,
  }) async {
    final c = context.appColors;
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: c.surface,
          title: Text(title, style: TextStyle(color: c.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: first,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(hintText: hint),
              ),
              if (withConfirm) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: second,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(hintText: 'Tekrar gir'),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: TextStyle(color: c.danger, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                final v = first.text;
                if (v.isEmpty) {
                  setSt(() => error = 'Boş bırakma');
                  return;
                }
                if (withConfirm) {
                  if (v.length < 8 ||
                      !PasswordReport.evaluate(v).isAcceptable) {
                    setSt(() => error = 'Daha güçlü bir şifre seç (en az 8 karakter)');
                    return;
                  }
                  if (second.text != v) {
                    setSt(() => error = 'Şifreler eşleşmiyor');
                    return;
                  }
                }
                Navigator.pop(ctx, v);
              },
              child: Text('Onayla', style: TextStyle(color: c.primary)),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    second.dispose();
    return result;
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
            child: Text(confirm, style: TextStyle(color: isDanger ? c.danger : c.primary)),
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

  String _formatBytes(int b) {
    if (b < 0) return 'Hesaplanıyor...';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
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
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.background,
        title: Text(
          'Ayarlar',
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: Stack(
        children: [
          ListenableBuilder(
            listenable: _s,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (_loadingProfile)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(color: c.primary)),
                  )
                else if (_profile != null)
                  _profileCard(c),

                _section('Hesap', c),
                _card(c, [
                  _tile(c, Icons.circle_outlined, 'Durumum',
                      subtitle: _profile?.modeLabel ?? 'Aktif',
                      onTap: _pickMode),
                  _divider(c),
                  _tile(c, Icons.alternate_email, 'E-posta adresi',
                      subtitle: _service.currentUser?.email ?? '',
                      onTap: _changeEmail),
                  _divider(c),
                  _tile(c, Icons.lock_reset, 'Hesap şifresini sıfırla',
                      subtitle: 'E-posta ile sıfırlama bağlantısı al',
                      onTap: _sendPasswordResetEmail),
                  _divider(c),
                  _tile(c, Icons.person_outline, 'Profil bilgileri',
                      subtitle: 'Kullanıcı adı, durum, avatar',
                      onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ProfilePage()),
                          ).then((_) => _loadProfile())),
                  _divider(c),
                  _tile(c, Icons.devices_outlined, 'Aktif oturumlar',
                      subtitle: 'Cihazları yönet', onTap: _showActiveSessions),
                ]),

                _section('Gizlilik', c),
                _card(c, [
                  _switch(c, Icons.visibility_outlined, 'Çevrimiçi durumu göster',
                      subtitle: 'Kapalıyken çevrimiçi görünmezsin',
                      value: _showOnline, onChanged: (v) {
                    setState(() => _showOnline = v);
                    _savePrivacy();
                  }),
                  _divider(c),
                  _switch(c, Icons.access_time, 'Son görülmeyi göster',
                      value: _showLastSeen, onChanged: (v) {
                    setState(() => _showLastSeen = v);
                    _savePrivacy();
                  }),
                  _divider(c),
                  _switch(c, Icons.done_all, 'Okundu bilgisi',
                      subtitle: 'Kapalıyken mesajlar okundu işaretlenmez',
                      value: _s.showReadReceipts,
                      onChanged: (v) => _s.update(() => _s.showReadReceipts = v)),
                  _divider(c),
                  _switch(c, Icons.edit_outlined, 'Yazıyor göstergesi',
                      subtitle: 'Yazarken karşı tarafa göster',
                      value: _s.showTypingIndicator,
                      onChanged: (v) =>
                          _s.update(() => _s.showTypingIndicator = v)),
                ]),

                _section('Güvenlik', c),
                _card(c, [
                  _tile(c, Icons.backup_outlined, 'Anahtar yedeği',
                      subtitle: 'Yedek parolası belirleyin ya da yedeği güncelleyin',
                      onTap: () => showBackupSetupDialog(context)),
                  _divider(c),
                  _tile(c, Icons.devices_outlined, 'Cihaz bağlama',
                      subtitle: 'Yeni cihazı onaylayın veya bu cihazı bağlayın',
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DeviceLinkPage()))),
                  _divider(c),
                  _tile(c, Icons.lock_outline, 'Uygulama kilidi',
                      subtitle: AppLock.instance.enabled
                          ? 'Açık (30 sn arka planda kalınca PIN sorulur)'
                          : 'Kapalı',
                      onTap: _busy ? null : _toggleAppLock),
                  _divider(c),
                  _tile(c, Icons.key_outlined, 'Parola Kasası şifresi',
                      subtitle: 'Parola kasasını açan şifre',
                      onTap: _busy
                          ? null
                          : () => _changeProductPassword(
                              PassCloud.instance, 'Parola Kasası')),
                  _divider(c),
                  _tile(c, Icons.menu_book_outlined, 'Defter şifresi',
                      subtitle: 'Notebook\'u açan şifre',
                      onTap: _busy
                          ? null
                          : () => _changeProductPassword(
                              NotebookCloud.instance, 'Defter')),
                  _divider(c),
                  _tile(c, Icons.timer_outlined, 'Otomatik kilit',
                      subtitle: 'Uygulama bu süre arka planda kalınca kasa kilitlenir: '
                          '${_lockOptions[_s.autoLockMinutes] ?? ''}',
                      onTap: () => _pick<int>(
                            title: 'Otomatik kilit',
                            options: _lockOptions,
                            current: _s.autoLockMinutes,
                            onSelect: (v) =>
                                _s.update(() => _s.autoLockMinutes = v),
                          )),
                  _divider(c),
                  _tile(c, Icons.lock_outline, 'Kasayı şimdi kilitle',
                      onTap: _lockVaultNow),
                  _divider(c),
                ]),

                _section('Bildirimler', c),
                _card(c, [
                  const NotificationPrivacyTile(),
                  _divider(c),
                  _switch(c, Icons.notifications_active_outlined,
                      'Uygulama içi bildirimler',
                      subtitle: 'Kapalıyken uygulama açıkken bildirim gelmez',
                      value: _s.inAppNotifications,
                      onChanged: (v) =>
                          _s.update(() => _s.inAppNotifications = v)),
                  _divider(c),
                  _switch(c, Icons.music_note_outlined, 'Arama zil sesi',
                      subtitle: 'Gelen aramada zil sesi çalsın',
                      value: _s.notifCallSound,
                      onChanged: (v) => _s.update(() => _s.notifCallSound = v)),
                  _divider(c),
                  _switch(c, Icons.vibration, 'Arama titreşimi',
                      subtitle: 'Gelen aramada titreşim olsun',
                      value: _s.notifCallVibrate,
                      onChanged: (v) => _s.update(() => _s.notifCallVibrate = v)),
                  _divider(c),
                  _switch(c, Icons.notifications_none, 'Mesaj sesi',
                      subtitle: 'Yeni mesajda ses çalsın',
                      value: _s.notifMessageSound,
                      onChanged: (v) => _s.update(() => _s.notifMessageSound = v)),
                  _divider(c),
                  _switch(c, Icons.phone_android_outlined, 'Mesaj titreşimi',
                      subtitle: 'Yeni mesajda titreşim olsun',
                      value: _s.notifMessageVibrate,
                      onChanged: (v) => _s.update(() => _s.notifMessageVibrate = v)),
                  _divider(c),
                  _switch(c, Icons.visibility_outlined, 'Mesaj önizlemesi',
                      subtitle: 'Bildirimde mesaj içeriği görünsün',
                      value: _s.notifMessagePreview,
                      onChanged: (v) => _s.update(() => _s.notifMessagePreview = v)),
                ]),

                _section('Tanılama', c),
                _card(c, [
                  _switch(c, Icons.bug_report_outlined, 'Ayrıntılı log',
                      subtitle: 'Görüşme ve bildirim olaylarını kaydeder, görüşme ekranında gösterir',
                      value: _s.detailedLog,
                      onChanged: (v) => _s.update(() => _s.detailedLog = v)),
                ]),

                _section('Görünüm', c),
                _card(c, [
                  _switch(c, Icons.brightness_auto, 'Sistem temasını kullan',
                      value: _s.useSystemTheme,
                      onChanged: (v) => _s.update(() => _s.useSystemTheme = v)),
                  _divider(c),
                  _tile(c, Icons.palette_outlined, 'Tema',
                      subtitle: _s.useSystemTheme ? 'Sistem ayarını izliyor' : _s.themeMode,
                      onTap: _s.useSystemTheme
                          ? null
                          : () => _pick<String>(
                                title: 'Tema',
                                options: const {
                                  'Karanlık': 'Karanlık',
                                  'Aydınlık': 'Aydınlık',
                                },
                                current: _s.themeMode,
                                onSelect: (v) => _s.update(() => _s.themeMode = v),
                              )),
                  _divider(c),
                  _tile(c, Icons.text_fields, 'Yazı boyutu',
                      subtitle: '${(_s.fontScale * 100).round()}%',
                      onTap: _showFontDialog),
                ]),

                _section('Medya ve depolama', c),
                _card(c, [
                  _switch(c, Icons.photo_outlined, 'Fotoğrafları otomatik yükle',
                      value: _s.autoLoadPhotos,
                      onChanged: (v) => _s.update(() => _s.autoLoadPhotos = v)),
                  _divider(c),
                  _switch(c, Icons.videocam_outlined, 'Videoları otomatik yükle',
                      value: _s.autoLoadVideos,
                      onChanged: (v) => _s.update(() => _s.autoLoadVideos = v)),
                  _divider(c),
                  _switch(c, Icons.mic_none, 'Sesli mesajları otomatik yükle',
                      value: _s.autoLoadAudio,
                      onChanged: (v) => _s.update(() => _s.autoLoadAudio = v)),
                  _divider(c),
                  _switch(c, Icons.insert_drive_file_outlined,
                      'Dosyaları otomatik yükle',
                      value: _s.autoLoadFiles,
                      onChanged: (v) => _s.update(() => _s.autoLoadFiles = v)),
                  _divider(c),
                  _tile(c, Icons.cleaning_services_outlined, 'Önbelleği temizle',
                      subtitle: _formatBytes(_cacheBytes), onTap: _clearCache),
                ]),

                _section('Veri', c),
                _card(c, [
                  _tile(c, Icons.lock_outline, 'Şifreli dışa aktar',
                      subtitle: 'Profil, mesajlar ve ayarlar. Kasa şifresinden ayrı şifre ister.',
                      onTap: _busy ? null : _exportEncrypted),
                  _divider(c),
                  _tile(c, Icons.copy_outlined, 'Ayarları dışa aktar',
                      subtitle: 'Yalnızca tercihler, şifre içermez',
                      onTap: _exportSettings),
                  _divider(c),
                  _tile(c, Icons.paste_outlined, 'Ayarları içe aktar',
                      subtitle: 'Dışa aktarılmış ayar metnini yapıştır',
                      onTap: _importSettings),
                  _divider(c),
                  _tile(c, Icons.restart_alt, 'Ayarları sıfırla',
                      subtitle: 'Tercihleri varsayılana döndürür',
                      titleColor: c.danger, onTap: _resetSettings),
                ]),

                _section('Yardım ve destek', c),
                _card(c, [
                  _tile(c, Icons.email_outlined, 'Bize ulaşın',
                      subtitle: 'writetome@gettic.dpdns.org',
                      onTap: () => _copy('writetome@gettic.dpdns.org', 'Adres kopyalandı')),
                  _divider(c),
                  _tile(c, Icons.bug_report_outlined, 'Hata bildir',
                      subtitle: 'Hata şablonunu kopyala ve e-posta ile gönder',
                      onTap: () => _copy(
                          'Konu: Hata bildirimi\n\nUygulama: ${AppConstants.appName} v${AppConstants.appVersion}\nKullanıcı: ${_profile?.username ?? '-'}\n\nHata açıklaması:\n',
                          'Hata şablonu kopyalandı')),
                  _divider(c),
                  _tile(c, Icons.lightbulb_outline, 'Özellik iste',
                      onTap: () => _copy(
                          'Konu: Özellik isteği\n\nİstediğim özellik: ',
                          'Şablon kopyalandı')),
                  _divider(c),
                  _tile(c, Icons.share_outlined, 'Arkadaşlarını davet et',
                      subtitle: 'Uygulama bağlantısını kopyala',
                      onTap: () => _copy(
                          'Gettic - Gizlilik odaklı mesajlaşma. İndir: https://gettic.dpdns.org',
                          'Davet bağlantısı kopyalandı')),
                ]),

                _section('Hakkında', c),
                _card(c, [
                  _tile(c, Icons.info_outline, 'Gettic hakkında',
                      subtitle: 'v${AppConstants.appVersion}', onTap: _showAbout),
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
                      onTap: _busy ? null : _deleteAccount),
                ]),

                const SizedBox(height: 28),
                _footer(c),
              ],
            ),
          ),
          if (_busy)
            Container(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator(color: c.primary)),
            ),
        ],
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
                  backgroundImage:
                      hasAvatar ? CachedNetworkImageProvider(p.avatarUrl!) : null,
                  child: !hasAvatar
                      ? Text(
                          p.username.isNotEmpty ? p.username[0].toUpperCase() : '?',
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
    final accent = color ?? c.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  /// Ayar satırlarının ikonu: renkli, yuvarlatılmış kutu.
  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _card(AppColors c, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border.withOpacity(0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }

  /// Kullanıcının durum modunu seçer: Aktif, Boşta, Rahatsız etmeyin.
  Future<void> _pickMode() async {
    final current = _profile?.mode ?? 'active';
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            for (final opt in const [
              ['active', 'Aktif', 'Herkes size mesaj gönderebilir', Colors.green],
              ['idle', 'Boşta', 'Uzakta olduğunuzu gösterir', Colors.amber],
              ['dnd', 'Rahatsız etmeyin', 'Bu moddayken size bildirim gelmez', Colors.redAccent],
            ])
              ListTile(
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: opt[3] as Color,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(opt[1] as String,
                    style: TextStyle(
                        color: ctx.appColors.textPrimary,
                        fontWeight: FontWeight.w600)),
                subtitle: Text(opt[2] as String,
                    style: TextStyle(color: ctx.appColors.textSecondary, fontSize: 12)),
                trailing: current == opt[0]
                    ? Icon(Icons.check, color: ctx.appColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, opt[0] as String),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (choice == null || choice == current) return;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      await Supabase.instance.client
          .from('profiles')
          .update({'mode': choice})
          .eq('id', uid);
      if (!mounted) return;
      setState(() => _profile = _profile?.copyWith(mode: choice));
      _snack('Durum güncellendi');
    } catch (e) {
      _snack('Durum kaydedilemedi: $e');
    }
  }

  Future<void> _toggleAppLock() async {
    if (AppLock.instance.enabled) {
      final pin = await _askPinDialog('Kilidi kapatmak için PIN');
      if (pin == null) return;
      if (!await AppLock.instance.verifyPin(pin)) {
        _snackMsg('PIN yanlış');
        return;
      }
      await AppLock.instance.disable();
      _snackMsg('Uygulama kilidi kapatıldı');
    } else {
      final pin = await _askNewPinDialog();
      if (pin == null) return;
      await AppLock.instance.setPin(pin);
      _snackMsg('Uygulama kilidi açıldı');
    }
    if (mounted) setState(() {});
  }

  void _snackMsg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<String?> _askPinDialog(String title) async {
    final c = context.appColors;
    final ctl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(title, style: TextStyle(color: c.textPrimary)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PIN'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
              child: Text('Tamam', style: TextStyle(color: c.primary))),
        ],
      ),
    );
    ctl.dispose();
    return (res == null || res.length < 4) ? null : res;
  }

  Future<String?> _askNewPinDialog() async {
    final c = context.appColors;
    final a = TextEditingController();
    final b = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Uygulama için PIN belirleyin',
            style: TextStyle(color: c.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: a,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN (en az 4 hane)'),
            ),
            TextField(
              controller: b,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN (tekrar)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal')),
          TextButton(
              onPressed: () {
                final p = a.text.trim();
                if (p.length >= 4 && p == b.text.trim()) {
                  Navigator.pop(ctx, p);
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('PIN en az 4 hane ve eşleşmeli')));
                }
              },
              child: Text('Kaydet', style: TextStyle(color: c.primary))),
        ],
      ),
    );
    a.dispose();
    b.dispose();
    return res;
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
    final enabled = onTap != null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _iconBox(icon, iconColor ?? c.primary),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? (enabled ? c.textPrimary : c.textHint),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(color: c.textSecondary, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis)
          : null,
      trailing: (enabled && trailing)
          ? Icon(Icons.chevron_right_rounded, color: c.textHint, size: 22)
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: _iconBox(icon, c.primary),
      title: Text(title,
          style: TextStyle(
              color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(color: c.textSecondary, fontSize: 12))
          : null,
      value: value,
      activeColor: c.primary,
      onChanged: onChanged,
    );
  }

  Widget _divider(AppColors c) =>
      Divider(color: c.border.withOpacity(0.6), height: 1, indent: 68, endIndent: 16);

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
                  decoration: BoxDecoration(color: c.online, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  '${AppConstants.appName} v${AppConstants.appVersion}',
                  style: TextStyle(
                      color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text("Türkiye'de sevgiyle yapıldı",
              style: TextStyle(color: c.textHint, fontSize: 11)),
        ],
      ),
    );
  }
}
