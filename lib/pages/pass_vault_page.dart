// ============================================================
// lib/pages/pass_vault_page.dart
//
// Gettic Pass: parola kasası (webdeki düzenle uyumlu).
//  - Kayıtlar SecureVault ile AES-256-GCM şifrelenerek cihazda tutulur.
//  - Favoriler, zayıf parola uyarısı, arama, filtre ve sıralama.
//  - 2FA (TOTP) kodu: kayda gizli anahtar eklenirse 30 sn'de bir yenilenir.
//  - Senkron: pass_sync.dart (uçtan uca şifreli, eklentiyle ortak).
//
// Gerekenler: vault_gate.dart, pass_sync.dart, security.dart, theme.dart
// Ek paket: crypto (pubspec.yaml'a açıkça ekleyin: crypto: ^3.0.3)
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';

import '../core/security.dart';
import '../core/theme.dart';
import '../services/pass_sync.dart';
import 'vault_gate.dart';

const String _kPassLogo = 'assets/getticpass_logo.png';

// ============================================================
// VERİ MODELİ
// ============================================================
class PassEntry {
  final String id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  /// Gizli 2FA (TOTP) anahtarı, base32. Boşsa 2FA kodu gösterilmez.
  final String totpSecret;
  final bool favorite;
  /// Son değişiklik zamanı (ms). Senkronda çakışmayı çözer.
  final int updatedAt;
  /// Silinmiş kayıt (tombstone). Silmeler senkronla yayılsın diye tutulur.
  final bool deleted;

  const PassEntry({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    this.totpSecret = '',
    this.favorite = false,
    this.updatedAt = 0,
    this.deleted = false,
  });

  static String newId() {
    final r = Random.secure();
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$t-${r.nextInt(1 << 30).toRadixString(36)}';
  }

  static PassEntry tombstone(PassEntry e) => PassEntry(
        id: e.id,
        title: '',
        username: '',
        password: '',
        url: '',
        notes: '',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        deleted: true,
      );

  factory PassEntry.fromJson(Map<String, dynamic> j) => PassEntry(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        username: (j['username'] ?? '') as String,
        password: (j['password'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        notes: (j['notes'] ?? '') as String,
        totpSecret: (j['totpSecret'] ?? '') as String,
        favorite: (j['favorite'] ?? false) as bool,
        updatedAt: (j['updatedAt'] ?? 0) as int,
        deleted: (j['deleted'] ?? false) as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'totpSecret': totpSecret,
        'favorite': favorite,
        'updatedAt': updatedAt,
        'deleted': deleted,
      };
}

// ============================================================
// KALICI DEPO (şifreli, SecureVault açıkken)
// ============================================================
class PassRepository {
  PassRepository._();
  static const String _key = 'pass_entries_v1';

  static Future<List<PassEntry>> load() async {
    final raw = await EncryptedPrefs.read(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => PassEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> save(List<PassEntry> items) {
    final json = jsonEncode(items.map((e) => e.toJson()).toList());
    return EncryptedPrefs.write(_key, json);
  }
}

// ============================================================
// PAROLA ÜRETİCİ (kriptografik rastgele)
// ============================================================
class PassGenerator {
  PassGenerator._();

  // Karıştırılabilen karakterler (0/O, 1/l/I) çıkarıldı
  static const String _lower = 'abcdefghijkmnopqrstuvwxyz';
  static const String _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const String _digits = '23456789';
  static final String _symbols = r'!@#$%^&*-_=+?';

  static String generate({int length = 20, bool symbols = true}) {
    final pools = <String>[_lower, _upper, _digits, if (symbols) _symbols];
    final all = pools.join();
    final r = Random.secure();
    final chars = <String>[for (final p in pools) p[r.nextInt(p.length)]];
    while (chars.length < length) {
      chars.add(all[r.nextInt(all.length)]);
    }
    chars.shuffle(r);
    return chars.join();
  }
}

// ============================================================
// TOTP (RFC 6238): 30 sn, 6 hane, HMAC-SHA1
// Doğrulandı: RFC test vektörleri (T=59 -> 287082).
// ============================================================
class Totp {
  Totp._();

  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Base32 çözer. Geçersiz karakter varsa [FormatException] fırlatır.
  static Uint8List base32Decode(String input) {
    final s = input.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
    var bits = 0;
    var value = 0;
    final out = <int>[];
    for (final ch in s.split('')) {
      final idx = _alphabet.indexOf(ch);
      if (idx < 0) throw const FormatException('Geçersiz 2FA anahtarı');
      value = ((value << 5) | idx) & 0xFFFF;
      bits += 5;
      if (bits >= 8) {
        out.add((value >> (bits - 8)) & 0xFF);
        bits -= 8;
      }
    }
    if (out.isEmpty) throw const FormatException('Geçersiz 2FA anahtarı');
    return Uint8List.fromList(out);
  }

  /// Geçerli bir base32 anahtar mı?
  static bool isValidSecret(String s) {
    try {
      base32Decode(s);
      return true;
    } on FormatException {
      return false;
    }
  }

  static String code(String secret, {int? nowMs}) {
    final key = base32Decode(secret);
    final ms = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final counter = (ms ~/ 1000) ~/ 30;
    final msg = ByteData(8)..setUint64(0, counter);
    final h = crypto.Hmac(crypto.sha1, key)
        .convert(msg.buffer.asUint8List())
        .bytes;
    final off = h[h.length - 1] & 0x0F;
    final bin = ((h[off] & 0x7F) << 24) |
        ((h[off + 1] & 0xFF) << 16) |
        ((h[off + 2] & 0xFF) << 8) |
        (h[off + 3] & 0xFF);
    return (bin % 1000000).toString().padLeft(6, '0');
  }

  /// Kodun bitmesine kalan saniye (1..30)
  static int remaining({int? nowMs}) {
    final ms = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return 30 - ((ms ~/ 1000) % 30);
  }
}

// ============================================================
// SAYFA (kasa kapısı + içerik)
// ============================================================
class PassVaultPage extends StatelessWidget {
  const PassVaultPage({super.key});

  @override
  Widget build(BuildContext context) {
    return VaultGate(
      lockedTitle: 'Kasa Kilitli',
      lockedHint: 'Devam etmek için kasa ana şifreni gir',
      logoAsset: _kPassLogo,
      builder: (_) => const _PassBody(),
    );
  }
}

class _PassBody extends StatefulWidget {
  const _PassBody();

  @override
  State<_PassBody> createState() => _PassBodyState();
}

enum _Filter { all, favorites, weak }

class _PassBodyState extends State<_PassBody> {
  List<PassEntry> _items = [];
  String _query = '';
  _Filter _filter = _Filter.all;
  bool _favoritesFirst = true;
  bool _syncOn = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  // ---------- Veri ----------
  Future<void> _loadItems() async {
    try {
      final items = await PassRepository.load();
      final on = await PassSync.instance.isEnabled();
      if (!mounted) return;
      setState(() {
        _items = items;
        _syncOn = on;
      });
      if (on) {
        PassSync.instance.scheduleSync(delay: const Duration(milliseconds: 300));
      }
    } on SecurityException catch (e) {
      _snack(e.message, isError: true);
    }
  }

  Future<void> _persist() async {
    try {
      await PassRepository.save(_items);
      if (mounted) setState(() {});
      if (_syncOn) PassSync.instance.scheduleSync();
    } on SecurityException catch (e) {
      _snack(e.message, isError: true);
    }
  }

  bool _isWeak(PassEntry e) {
    if (e.password.isEmpty) return false;
    final r = PasswordReport.evaluate(
      e.password,
      userInputs: [e.title, e.username],
    );
    return r.strength.index <= PasswordStrength.weak.index;
  }

  List<PassEntry> get _live => _items.where((e) => !e.deleted).toList();

  List<PassEntry> get _visible {
    final q = _query.trim().toLowerCase();
    final list = _live.where((e) {
      switch (_filter) {
        case _Filter.favorites:
          if (!e.favorite) return false;
          break;
        case _Filter.weak:
          if (!_isWeak(e)) return false;
          break;
        case _Filter.all:
          break;
      }
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          e.username.toLowerCase().contains(q) ||
          e.url.toLowerCase().contains(q);
    }).toList();

    list.sort((a, b) {
      if (_favoritesFirst && a.favorite != b.favorite) {
        return a.favorite ? -1 : 1;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return list;
  }

  // ---------- Eylemler ----------
  Future<void> _add() async {
    final result = await _openEditor(null);
    if (result == null) return;
    _items.add(result);
    await _persist();
  }

  Future<void> _edit(PassEntry e) async {
    final result = await _openEditor(e);
    if (result == null) return;
    final idx = _items.indexWhere((x) => x.id == e.id);
    if (idx == -1) return;
    _items[idx] = result;
    await _persist();
  }

  Future<void> _toggleFavorite(PassEntry e) async {
    final idx = _items.indexWhere((x) => x.id == e.id);
    if (idx == -1) return;
    _items[idx] = PassEntry(
      id: e.id,
      title: e.title,
      username: e.username,
      password: e.password,
      url: e.url,
      notes: e.notes,
      totpSecret: e.totpSecret,
      favorite: !e.favorite,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _persist();
  }

  Future<void> _copy(String value, String what) async {
    await SecureClipboard.copy(value);
    _snack('$what kopyalandı. 30 saniye sonra panodan silinecek.');
  }

  Future<void> _confirmDelete(PassEntry e) async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Kaydı sil', style: TextStyle(color: c.textPrimary)),
        content: Text('"${e.title}" kaydı kalıcı olarak silinecek.',
            style: TextStyle(color: c.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final idx = _items.indexWhere((x) => x.id == e.id);
    if (idx == -1) return;
    _items[idx] = PassEntry.tombstone(e);
    await _persist();
  }

  Future<PassEntry?> _openEditor(PassEntry? e) {
    return showModalBottomSheet<PassEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EntryEditor(entry: e),
    );
  }

  Future<void> _onSyncMenu(String v) async {
    switch (v) {
      case 'enable':
        await showPassSyncSetup(context);
        await _loadItems();
        break;
      case 'now':
        try {
          await PassSync.instance.sync();
          _snack('Senkronize edildi');
          await _loadItems();
        } on SecurityException catch (e) {
          _snack(e.message, isError: true);
        } catch (_) {
          _snack('Senkron yapılamadı. İnternet bağlantınızı kontrol edin.',
              isError: true);
        }
        break;
      case 'disable':
        await PassSync.instance.disable();
        if (mounted) setState(() => _syncOn = false);
        _snack('Senkron kapatıldı. Sunucudaki kopya silinmedi.');
        break;
      case 'lock':
        SecureVault.instance.lock();
        break;
    }
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

  // ---------- Görünüm ----------
  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final live = _live;
    final visible = _visible;
    final favCount = live.where((e) => e.favorite).length;
    final weakCount = live.where(_isWeak).length;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                Image.asset(_kPassLogo, width: 36, height: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Gettic Pass',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => _add(),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('+ Yeni'),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Daha fazla',
                  onSelected: _onSyncMenu,
                  itemBuilder: (_) => [
                    if (!_syncOn)
                      const PopupMenuItem(
                          value: 'enable', child: Text('Senkronu aç')),
                    if (_syncOn)
                      const PopupMenuItem(
                          value: 'now', child: Text('Şimdi senkronize et')),
                    if (_syncOn)
                      const PopupMenuItem(
                          value: 'disable', child: Text('Senkronu kapat')),
                    const PopupMenuItem(value: 'lock', child: Text('Kasayı kilitle')),
                  ],
                  icon: Icon(
                    _syncOn ? Icons.sync : Icons.sync_disabled,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _stat('Toplam', live.length, c.primary),
                const SizedBox(width: 10),
                _stat('Favori', favCount, c.primary),
                const SizedBox(width: 10),
                _stat('Zayıf', weakCount, weakCount > 0 ? c.danger : c.primary),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Ara...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 10),
            _dropdown<_Filter>(
              value: _filter,
              items: const {
                _Filter.all: 'Tümü',
                _Filter.favorites: 'Favoriler',
                _Filter.weak: 'Zayıf parolalar',
              },
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 10),
            _dropdown<bool>(
              value: _favoritesFirst,
              items: const {
                true: 'Favoriler önce',
                false: 'A-Z',
              },
              onChanged: (v) => setState(() => _favoritesFirst = v),
            ),
            const SizedBox(height: 14),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    live.isEmpty
                        ? 'Henüz kayıt yok. "+ Yeni" ile ekleyebilirsin.'
                        : 'Sonuç bulunamadı.',
                    style: TextStyle(color: c.textSecondary),
                  ),
                ),
              )
            else
              for (final e in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _EntryCard(
                    key: ValueKey(e.id),
                    entry: e,
                    weak: _isWeak(e),
                    onToggleFavorite: () => _toggleFavorite(e),
                    onCopyUser: () => _copy(e.username, 'Kullanıcı adı'),
                    onCopyPassword: () => _copy(e.password, 'Parola'),
                    onCopyCode: () => _copy(
                        Totp.code(e.totpSecret), '2FA kodu'),
                    onEdit: () => _edit(e),
                    onDelete: () => _confirmDelete(e),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, int value, Color color) {
    final c = context.appColors;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(color: c.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: c.surface,
          style: TextStyle(color: c.textPrimary, fontSize: 15),
          items: [
            for (final e in items.entries)
              DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ============================================================
// KAYIT KARTI
// ============================================================
class _EntryCard extends StatefulWidget {
  final PassEntry entry;
  final bool weak;
  final VoidCallback onToggleFavorite;
  final VoidCallback onCopyUser;
  final VoidCallback onCopyPassword;
  final VoidCallback onCopyCode;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EntryCard({
    super.key,
    required this.entry,
    required this.weak,
    required this.onToggleFavorite,
    required this.onCopyUser,
    required this.onCopyPassword,
    required this.onCopyCode,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _showPassword = false;
  Timer? _ticker;

  bool get _hasTotp => widget.entry.totpSecret.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_hasTotp) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _totpText() {
    try {
      final code = Totp.code(widget.entry.totpSecret);
      return '${code.substring(0, 3)} ${code.substring(3)}';
    } on FormatException {
      return 'Geçersiz anahtar';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final e = widget.entry;
    final initial = e.title.isEmpty ? '?' : e.title[0].toUpperCase();
    final mono = const TextStyle(fontFamily: 'monospace', fontSize: 14);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(initial,
                    style: TextStyle(
                        color: c.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  e.title.isEmpty ? 'Başlıksız' : e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              if (widget.weak)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.danger),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Zayıf',
                      style: TextStyle(color: c.danger, fontSize: 11)),
                ),
              IconButton(
                tooltip: e.favorite ? 'Favoriden çıkar' : 'Favoriye ekle',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  e.favorite ? Icons.star : Icons.star_border,
                  color: e.favorite ? Colors.amber : c.textHint,
                ),
                onPressed: widget.onToggleFavorite,
              ),
            ],
          ),
          if (e.url.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textHint, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          _row(
            'Kullanıcı',
            Text(
              e.username.isEmpty ? '-' : e.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(color: c.textPrimary),
            ),
          ),
          _row(
            'Şifre',
            Row(
              children: [
                Expanded(
                  child: Text(
                    _showPassword ? e.password : '•' * 10,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono.copyWith(color: c.textPrimary),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  child: Text(_showPassword ? 'Gizle' : 'Göster'),
                ),
              ],
            ),
          ),
          if (_hasTotp)
            _row(
              '2FA',
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _totpText(),
                      style: mono.copyWith(
                        color: c.online,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: Totp.remaining() / 30,
                          strokeWidth: 3,
                          color: c.online,
                          backgroundColor: c.border,
                        ),
                        Text('${Totp.remaining()}',
                            style: TextStyle(
                                color: c.textSecondary, fontSize: 9)),
                      ],
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: widget.onCopyCode,
                    child: const Text('Kopyala'),
                  ),
                ],
              ),
            ),
          if (e.notes.trim().isNotEmpty)
            _row(
              'Not',
              Text(
                e.notes,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
            ),
          const SizedBox(height: 10),
          Divider(color: c.border, height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              _action('Kullanıcı', widget.onCopyUser),
              const SizedBox(width: 8),
              _action('Şifre', widget.onCopyPassword),
              const SizedBox(width: 8),
              _action('Düzenle', widget.onEdit),
              const SizedBox(width: 8),
              _action('Sil', widget.onDelete, danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, Widget value) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 78,
            child: Text(label,
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  Widget _action(String label, VoidCallback onTap, {bool danger = false}) {
    final c = context.appColors;
    return Expanded(
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          side: BorderSide(color: c.border),
          foregroundColor: danger ? c.danger : c.textSecondary,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

// ============================================================
// KAYIT DÜZENLEYİCİ (alt sayfa)
// ============================================================
class _EntryEditor extends StatefulWidget {
  final PassEntry? entry;
  const _EntryEditor({this.entry});

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.entry?.title ?? '');
  late final TextEditingController _user =
      TextEditingController(text: widget.entry?.username ?? '');
  late final TextEditingController _pass =
      TextEditingController(text: widget.entry?.password ?? '');
  late final TextEditingController _url =
      TextEditingController(text: widget.entry?.url ?? '');
  late final TextEditingController _totp =
      TextEditingController(text: widget.entry?.totpSecret ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.entry?.notes ?? '');

  bool _obscure = true;
  String? _error;
  late PasswordReport _report = _evaluate(_pass.text);

  PasswordReport _evaluate(String pw) => PasswordReport.evaluate(
        pw,
        userInputs: [_title.text, _user.text],
      );

  @override
  void dispose() {
    for (final c in [_title, _user, _pass, _url, _totp, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _recalc() => setState(() => _report = _evaluate(_pass.text));

  void _generate() {
    _pass.text = PassGenerator.generate();
    _obscure = false;
    _recalc();
  }

  void _save() {
    final title = _title.text.trim();
    final pass = _pass.text;
    final totp = _totp.text.trim().replaceAll(' ', '');

    if (title.isEmpty) {
      setState(() => _error = 'Başlık gerekli');
      return;
    }
    if (pass.isEmpty) {
      setState(() => _error = 'Parola gerekli');
      return;
    }
    if (totp.isNotEmpty && !Totp.isValidSecret(totp)) {
      setState(() => _error = '2FA anahtarı geçersiz (yalnızca A-Z ve 2-7)');
      return;
    }

    Navigator.pop(
      context,
      PassEntry(
        id: widget.entry?.id ?? PassEntry.newId(),
        title: title,
        username: _user.text.trim(),
        password: pass,
        url: _url.text.trim(),
        notes: _notes.text.trim(),
        totpSecret: totp,
        favorite: widget.entry?.favorite ?? false,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        deleted: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.entry == null ? 'Yeni kayıt' : 'Kaydı düzenle',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(hintText: 'Başlık (ör. Instagram)'),
              onChanged: (_) => _recalc(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                  hintText: 'Kullanıcı adı veya e-posta'),
              onChanged: (_) => _recalc(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              onChanged: (_) => _recalc(),
              decoration: InputDecoration(
                hintText: 'Parola',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Güçlü parola üret',
                      icon: const Icon(Icons.autorenew),
                      onPressed: _generate,
                    ),
                    IconButton(
                      tooltip: _obscure ? 'Göster' : 'Gizle',
                      icon: Icon(_obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ],
                ),
              ),
            ),
            if (_pass.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              _StrengthBar(report: _report),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration:
                  const InputDecoration(hintText: 'Site adresi (isteğe bağlı)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _totp,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: '2FA gizli anahtarı (isteğe bağlı)',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration:
                  const InputDecoration(hintText: 'Not (isteğe bağlı)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: c.danger, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PAROLA GÜCÜ GÖSTERGESİ
// ============================================================
class _StrengthBar extends StatelessWidget {
  final PasswordReport report;
  const _StrengthBar({required this.report});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final color = switch (report.strength) {
      PasswordStrength.veryWeak || PasswordStrength.weak => c.danger,
      PasswordStrength.fair => Colors.amber.shade700,
      PasswordStrength.strong || PasswordStrength.veryStrong => c.online,
    };
    final hint = report.hints.isEmpty ? null : report.hints.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(5, (i) {
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                decoration: BoxDecoration(
                  color: i <= report.strength.index ? color : c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text(
          hint == null
              ? 'Parola gücü: ${report.label}'
              : 'Parola gücü: ${report.label} • $hint',
          style: TextStyle(color: color, fontSize: 12),
        ),
      ],
    );
  }
}
