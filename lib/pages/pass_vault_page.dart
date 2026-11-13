// ============================================================
// lib/pages/pass_vault_page.dart
//
// GetticPass - uygulama içi parola kasası.
// Kayıtlar, security.dart içindeki SecureVault ile açılan kasada
// AES-256-GCM ile şifrelenmiş olarak cihazda tutulur.
//
// Gerekenler: lib/core/security.dart, lib/core/theme.dart (AppColors)
// Ek paket gerekmez.
// ============================================================

import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/material.dart';

import '../core/security.dart';
import '../core/theme.dart';
import '../services/pass_sync.dart';

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
    this.updatedAt = 0,
    this.deleted = false,
  });

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

  static String newId() {
    final r = Random.secure();
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$t-${r.nextInt(1 << 30).toRadixString(36)}';
  }

  factory PassEntry.fromJson(Map<String, dynamic> j) => PassEntry(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        username: (j['username'] ?? '') as String,
        password: (j['password'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        notes: (j['notes'] ?? '') as String,
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
        'updatedAt': updatedAt,
        'deleted': deleted,
      };
}

// ============================================================
// KALICI DEPO (tek şifreli blob: SecureVault açıkken yazılır)
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

  // Karışıklık yaratan karakterler (0/O, 1/l/I) çıkarıldı
  static const String _lower = 'abcdefghijkmnopqrstuvwxyz';
  static const String _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const String _digits = '23456789';
  static final String _symbols = r'!@#$%^&*-_=+?';

  static String generate({int length = 20, bool symbols = true}) {
    final pools = <String>[_lower, _upper, _digits, if (symbols) _symbols];
    final all = pools.join();
    final r = Random.secure();

    // Her kümeden en az bir karakter (kurallara uyum)
    final chars = <String>[
      for (final p in pools) p[r.nextInt(p.length)],
    ];
    while (chars.length < length) {
      chars.add(all[r.nextInt(all.length)]);
    }
    chars.shuffle(r);
    return chars.join();
  }
}

// ============================================================
// SAYFA
// ============================================================
class PassVaultPage extends StatefulWidget {
  const PassVaultPage({super.key});

  @override
  State<PassVaultPage> createState() => _PassVaultPageState();
}

class _PassVaultPageState extends State<PassVaultPage> {
  final SecureVault _vault = SecureVault.instance;

  bool? _isSetUp; // null: henüz kontrol edilmedi
  List<PassEntry> _items = [];
  String _query = '';
  bool _syncOn = false;

  @override
  void initState() {
    super.initState();
    _vault.addListener(_onVaultChanged);
    _vault.enableAutoLock(after: const Duration(minutes: 2));
    _init();
  }

  @override
  void dispose() {
    _vault.removeListener(_onVaultChanged);
    _vault.disableAutoLock();
    // Sayfadan çıkınca kasayı kilitle: parolalar bellekte kalmasın
    _vault.lock();
    super.dispose();
  }

  Future<void> _init() async {
    final setUp = await _vault.isSetUp;
    if (!mounted) return;
    setState(() => _isSetUp = setUp);
    if (_vault.isUnlocked) await _loadItems();
  }

  void _onVaultChanged() {
    if (!mounted) return;
    if (!_vault.isUnlocked) {
      setState(() => _items = []);
    }
  }

  Future<void> _loadItems() async {
    try {
      final items = await PassRepository.load();
      final on = await PassSync.instance.isEnabled();
      if (!mounted) return;
      setState(() {
        _items = items;
        _syncOn = on;
      });
      if (on) PassSync.instance.scheduleSync(delay: const Duration(milliseconds: 300));
    } on SecurityException catch (e) {
      _snack(e.message, isError: true);
    }
  }

  /// Kasa kurulu değilse oluşturur, kuruluysa açar.
  Future<void> _unlockOrSetup(String secret, bool isSetUp) async {
    if (isSetUp) {
      await _vault.unlock(secret);
    } else {
      await _vault.setUp(secret);
      _isSetUp = true;
    }
    await _loadItems();
    if (mounted) setState(() {});
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

  Future<void> _copy(PassEntry e) async {
    await SecureClipboard.copy(e.password);
    _snack('Parola kopyalandı. 30 saniye sonra panodan silinecek.');
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

  Future<void> _onSyncMenu(String v) async {
    switch (v) {
      case 'enable':
        await showPassSyncSetup(context);
        await _loadItems();
        break;
      case 'now':
        await PassSync.instance.sync().then((_) async {
          _snack('Senkronize edildi');
          await _loadItems();
        }).catchError((Object e) {
          _snack(
              e is SecurityException
                  ? e.message
                  : 'Senkron yapılamadı. İnternet bağlantınızı kontrol edin.',
              isError: true);
        });
        break;
      case 'disable':
        await PassSync.instance.disable();
        if (mounted) setState(() => _syncOn = false);
        _snack('Senkron kapatıldı. Sunucudaki kopya silinmedi.');
        break;
    }
  }

  // ---------- Görünüm ----------
  @override
  Widget build(BuildContext context) {
    if (_isSetUp == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_vault.isUnlocked) {
      return _LockScreen(isSetUp: _isSetUp!, onSubmit: _unlockOrSetup);
    }
    return _buildList(context);
  }

  Widget _buildList(BuildContext context) {
    final c = context.appColors;
    final q = _query.trim().toLowerCase();
    final shown = _items.where((e) {
      if (e.deleted) return false;
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          e.username.toLowerCase().contains(q) ||
          e.url.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parola Kasası'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Senkron',
            icon: Icon(_syncOn ? Icons.sync : Icons.sync_disabled),
            onSelected: _onSyncMenu,
            itemBuilder: (_) => [
              if (!_syncOn)
                const PopupMenuItem(value: 'enable', child: Text('Senkronu aç')),
              if (_syncOn)
                const PopupMenuItem(value: 'now', child: Text('Şimdi senkronize et')),
              if (_syncOn)
                const PopupMenuItem(value: 'disable', child: Text('Senkronu kapat')),
            ],
          ),
          IconButton(
            tooltip: 'Kasayı kilitle',
            icon: const Icon(Icons.lock_outline),
            onPressed: () => _vault.lock(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Yeni kayıt',
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Ara',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      _items.every((e) => e.deleted)
                          ? 'Henüz kayıt yok. + ile ekleyebilirsin.'
                          : 'Sonuç bulunamadı.',
                      style: TextStyle(color: c.textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => _tile(shown[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tile(PassEntry e) {
    final c = context.appColors;
    final initial = e.title.isEmpty ? '?' : e.title[0].toUpperCase();
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: c.primary.withOpacity(0.15),
        child: Text(initial,
            style: TextStyle(color: c.primary, fontWeight: FontWeight.bold)),
      ),
      title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        e.username.isNotEmpty ? e.username : e.url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: c.textSecondary, fontSize: 13),
      ),
      trailing: IconButton(
        tooltip: 'Parolayı kopyala',
        icon: const Icon(Icons.copy_outlined),
        onPressed: () => _copy(e),
      ),
      onTap: () => _edit(e),
      onLongPress: () => _confirmDelete(e),
    );
  }
}

// ============================================================
// KİLİT EKRANI (kurulum veya açma)
// ============================================================
class _LockScreen extends StatefulWidget {
  final bool isSetUp;
  final Future<void> Function(String secret, bool isSetUp) onSubmit;

  const _LockScreen({required this.isSetUp, required this.onSubmit});

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  final _secret = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  PasswordReport _report = PasswordReport.evaluate('');

  @override
  void dispose() {
    _secret.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _secret.text;
    if (text.isEmpty) {
      setState(() => _error = 'Parola gerekli');
      return;
    }
    if (!widget.isSetUp) {
      if (!_report.isAcceptable) {
        setState(() => _error = 'Daha güçlü bir kasa parolası seç');
        return;
      }
      if (_confirm.text != text) {
        setState(() => _error = 'Parolalar eşleşmiyor');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(text, widget.isSetUp);
    } on SecurityException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final setup = !widget.isSetUp;

    return Scaffold(
      appBar: AppBar(title: const Text('Parola Kasası')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.shield_outlined, size: 56, color: c.primary),
                const SizedBox(height: 16),
                Text(
                  setup ? 'Kasa parolanı oluştur' : 'Kasanı aç',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  setup
                      ? 'Bu parola kasandaki tüm kayıtları açar. Uygulama hesap parolanızdan ayrıdır ve unutulursa kayıtlar kurtarılamaz.'
                      : 'Kasa parolanı gir.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _secret,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  onChanged: setup
                      ? (v) => setState(
                          () => _report = PasswordReport.evaluate(v))
                      : null,
                  onSubmitted: (_) => setup ? null : _submit(),
                  decoration: InputDecoration(
                    hintText: 'Kasa parolası',
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (setup) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      hintText: 'Kasa parolasını tekrar gir',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 12),
                  _StrengthBar(report: _report),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.danger, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(setup ? 'Kasayı oluştur' : 'Aç'),
                  ),
                ),
              ],
            ),
          ),
        ),
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
    _title.dispose();
    _user.dispose();
    _pass.dispose();
    _url.dispose();
    _notes.dispose();
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
    if (title.isEmpty) {
      setState(() => _error = 'Başlık gerekli');
      return;
    }
    if (pass.isEmpty) {
      setState(() => _error = 'Parola gerekli');
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
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Başlık (ör. Instagram)'),
              onChanged: (_) => _recalc(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: 'Kullanıcı adı veya e-posta'),
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
              decoration: const InputDecoration(hintText: 'Site adresi (isteğe bağlı)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Not (isteğe bağlı)'),
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
