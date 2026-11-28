// ============================================================
// lib/pages/notebook_page.dart
//
// Notebook: klasörler, sabitlenenler, arama, düzenleme (otomatik kayıt).
// Notlar SecureVault ile AES-256-GCM şifrelenerek cihazda tutulur.
// Eski düz kayıtlar ilk açılışta şifreli depoya taşınır.
// Gerekenler: vault_gate.dart, security.dart, theme.dart
// ============================================================

import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/security.dart';
import '../core/theme.dart';
import 'vault_gate.dart';
import '../services/cloud_notebook.dart';
import '../services/cloud_vaults.dart';
import '../services/web_crypto.dart';
import '../services/secure_screen.dart';

const String _kNotebookLogo = 'assets/getticnotebook_logo.png';
const String _kTabAll = '__all__';
const String _kTabPinned = '__pinned__';
const String _kTabNoFolder = '__nofolder__';

// ============================================================
// MODEL
// ============================================================
class NoteItem {
  final String id;
  final String title;
  final String body;
  final String folder; // boşsa klasörsüz
  final bool pinned;
  final int updatedAt; // ms
  final bool deleted; // silinmiş (senkron için tombstone)

  const NoteItem({
    required this.id,
    required this.title,
    required this.body,
    required this.folder,
    required this.pinned,
    required this.updatedAt,
    this.deleted = false,
  });

  static NoteItem tombstone(NoteItem n) => NoteItem(
        id: n.id,
        title: '',
        body: '',
        folder: '',
        pinned: false,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        deleted: true,
      );

  static String newId() => WebCrypto.uuidV4();

  factory NoteItem.fromJson(Map<String, dynamic> j) => NoteItem(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        folder: (j['folder'] ?? '') as String,
        pinned: (j['pinned'] ?? false) as bool,
        updatedAt: (j['updatedAt'] ?? 0) as int,
        deleted: (j['deleted'] ?? false) as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'folder': folder,
        'pinned': pinned,
        'updatedAt': updatedAt,
        'deleted': deleted,
      };
}

/// Editörden dönen sonuç: kaydedilmiş not ya da silinen notun id'si.
class NoteResult {
  final NoteItem? note;
  final String? deletedId;

  const NoteResult._({this.note, this.deletedId});

  factory NoteResult.saved(NoteItem note) => NoteResult._(note: note);
  factory NoteResult.deleted(String id) => NoteResult._(deletedId: id);
}

// ============================================================
// DEPO (şifreli)
// ============================================================
class NotebookRepository {
  NotebookRepository._();

  /// Notları sunucudan çeker (defter açık olmalı)
  static Future<List<NoteItem>> load() => NotebookCloud.instance.fetchAll();

  /// Notları sunucuya yazar (silinmişler dahil)
  static Future<void> save(List<NoteItem> notes) =>
      NotebookCloud.instance.saveAll(notes);
}

// ============================================================
// SAYFA (kasa kapısı + içerik)
// ============================================================
class NotebookPage extends StatelessWidget {
  const NotebookPage({super.key});

  @override
  Widget build(BuildContext context) {
    return VaultGate(
      vault: NotebookCloud.instance,
      lockedTitle: 'Defter kilitli',
      lockedHint:
          'Notların cihazında şifrelenir. Devam etmek için defter şifreni gir.',
      logoAsset: _kNotebookLogo,
      builder: (_) => const _NotebookBody(),
    );
  }
}

class _NotebookBody extends StatefulWidget {
  const _NotebookBody();

  @override
  State<_NotebookBody> createState() => _NotebookBodyState();
}

class _NotebookBodyState extends State<_NotebookBody> {
  List<NoteItem> _notes = [];
  String _query = '';
  String _tab = _kTabAll;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SecureScreen.set(true);
    _load();
  }

  Future<void> _load() async {
    try {
      final notes = await NotebookRepository.load();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
      // Açılışta diğer cihazlardaki değişiklikleri çek
    } on SecurityException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(e.message, isError: true);
    }
  }

  // ---------- Türetilmiş veriler ----------
  List<String> get _folders {
    final set = _notes
        .where((n) => !n.deleted)
        .map((n) => n.folder)
        .where((f) => f.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return set;
  }

  bool _matchesTab(NoteItem n, String tab) {
    switch (tab) {
      case _kTabAll:
        return true;
      case _kTabPinned:
        return n.pinned;
      case _kTabNoFolder:
        return n.folder.trim().isEmpty;
      default:
        return n.folder == tab;
    }
  }

  List<NoteItem> get _visible {
    final q = _query.trim().toLowerCase();
    final list = _notes.where((n) {
      if (n.deleted) return false;
      if (!_matchesTab(n, _tab)) return false;
      if (q.isEmpty) return true;
      return n.title.toLowerCase().contains(q) ||
          n.body.toLowerCase().contains(q) ||
          n.folder.toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  int _countFor(String tab) =>
      _notes.where((n) => !n.deleted && _matchesTab(n, tab)).length;

  /// Notu silinmiş olarak işaretler (senkronda silme yayılsın diye listeden hemen çıkarılmaz)
  void _markDeleted(String id) {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx != -1) _notes[idx] = NoteItem.tombstone(_notes[idx]);
  }

  // ---------- Eylemler ----------
  Future<void> _persist() async {
    try {
      await NotebookRepository.save(_notes);
      if (mounted) setState(() {});
    } on SecurityException catch (e) {
      _snack(e.message, isError: true);
    }
  }

  Future<void> _open(NoteItem? note) async {
    final result = await Navigator.push<NoteResult>(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)),
    );
    if (result == null || !mounted) return;

    if (result.deletedId != null) {
      _markDeleted(result.deletedId!);
    } else if (result.note != null) {
      final saved = result.note!;
      final idx = _notes.indexWhere((n) => n.id == saved.id);
      if (idx == -1) {
        _notes.add(saved);
      } else {
        _notes[idx] = saved;
      }
    }
    await _persist();
  }

  Future<void> _togglePin(NoteItem n) async {
    final idx = _notes.indexWhere((x) => x.id == n.id);
    if (idx == -1) return;
    _notes[idx] = NoteItem(
      id: n.id,
      title: n.title,
      body: n.body,
      folder: n.folder,
      pinned: !n.pinned,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _persist();
  }

  Future<void> _confirmDelete(NoteItem n) async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Notu sil', style: TextStyle(color: c.textPrimary)),
        content: Text('Bu not kalıcı olarak silinecek.',
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
    _markDeleted(n.id);
    await _persist();
  }

  void _lock() => NotebookCloud.instance.lock();

  Future<void> _signOut() => Supabase.instance.client.auth.signOut();

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
  void dispose() {
    SecureScreen.set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final visible = _visible;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Image.asset(_kNotebookLogo, width: 36, height: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Gettic Notebook',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.primary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill('+ Yeni', filled: true, onTap: () => _open(null)),
                  _pill('Kilitle', onTap: _lock),
                  _pill('Çıkış', onTap: _signOut),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Notlarda ara...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                children: [
                  _tabChip('Tümü', _kTabAll),
                  _tabChip('Sabitlenenler', _kTabPinned),
                  for (final f in _folders) _tabChip(f, f),
                  _tabChip('Klasörsüz', _kTabNoFolder),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '${visible.length} not',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: c.primary))
                  : visible.isEmpty
                      ? Center(
                          child: Text(
                            _notes.every((n) => n.deleted)
                                ? 'Henüz not yok. "+ Yeni" ile ekleyebilirsin.'
                                : 'Sonuç bulunamadı.',
                            style: TextStyle(color: c.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _noteCard(visible[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label,
      {bool filled = false, required VoidCallback onTap}) {
    final c = context.appColors;
    return SizedBox(
      height: 40,
      child: filled
          ? ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                side: BorderSide(color: c.border),
                foregroundColor: c.textSecondary,
              ),
              child: Text(label),
            ),
    );
  }

  Widget _tabChip(String label, String tab) {
    final c = context.appColors;
    final selected = _tab == tab;
    final count = _countFor(tab);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label  $count'),
        selected: selected,
        onSelected: (_) => setState(() => _tab = tab),
        selectedColor: c.primary.withOpacity(0.18),
        backgroundColor: c.surface,
        side: BorderSide(color: selected ? c.primary : c.border),
        labelStyle: TextStyle(
          color: selected ? c.primary : c.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        showCheckmark: false,
      ),
    );
  }

  Widget _noteCard(NoteItem n) {
    final c = context.appColors;
    final date = DateFormat('d MMM HH:mm', 'tr_TR')
        .format(DateTime.fromMillisecondsSinceEpoch(n.updatedAt));
    final folderLabel = n.folder.trim().isEmpty ? 'Klasörsüz' : n.folder;

    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(n),
        onLongPress: () => _confirmDelete(n),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      n.title.isEmpty ? 'Başlıksız' : n.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: n.pinned ? 'Sabitlemeyi kaldır' : 'Sabitle',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      n.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      color: n.pinned ? c.primary : c.textHint,
                      size: 20,
                    ),
                    onPressed: () => _togglePin(n),
                  ),
                ],
              ),
              if (n.body.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  n.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 14),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '$folderLabel · $date',
                style: TextStyle(color: c.textHint, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// EDİTÖR
// Geri tuşu ve çıkış otomatik kaydeder. Tamamen boş yeni not kaydedilmez.
// ============================================================
class NoteEditorPage extends StatefulWidget {
  final NoteItem? note;
  const NoteEditorPage({super.key, this.note});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final String _id = widget.note?.id ?? NoteItem.newId();
  late final TextEditingController _title =
      TextEditingController(text: widget.note?.title ?? '');
  late final TextEditingController _folder =
      TextEditingController(text: widget.note?.folder ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.note?.body ?? '');
  late bool _pinned = widget.note?.pinned ?? false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => _changed = true);
    _folder.addListener(() => _changed = true);
    _body.addListener(() => _changed = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _folder.dispose();
    _body.dispose();
    super.dispose();
  }

  void _finish() {
    if (!_changed && _pinned == (widget.note?.pinned ?? false)) {
      Navigator.pop(context);
      return;
    }

    final title = _title.text.trim();
    final body = _body.text.trimRight();

    if (title.isEmpty && body.trim().isEmpty) {
      // Tüm içerik silindiyse mevcut not kaldırılır, yeni not eklenmez
      Navigator.pop(
        context,
        widget.note != null ? NoteResult.deleted(_id) : null,
      );
      return;
    }

    Navigator.pop(
      context,
      NoteResult.saved(
        NoteItem(
          id: _id,
          title: title,
          body: body,
          folder: _folder.text.trim(),
          pinned: _pinned,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  Future<void> _askDelete() async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Notu sil', style: TextStyle(color: c.textPrimary)),
        content: Text('Bu not kalıcı olarak silinecek.',
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
    if (ok == true && mounted) {
      Navigator.pop(context, NoteResult.deleted(_id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          title: Text(widget.note == null ? 'Yeni not' : 'Not'),
          leading: IconButton(
            tooltip: 'Kaydet ve çık',
            icon: const Icon(Icons.arrow_back),
            onPressed: _finish,
          ),
          actions: [
            IconButton(
              tooltip: _pinned ? 'Sabitlemeyi kaldır' : 'Sabitle',
              icon: Icon(
                _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: _pinned ? c.primary : null,
              ),
              onPressed: () => setState(() {
                _pinned = !_pinned;
                _changed = true;
              }),
            ),
            if (widget.note != null)
              IconButton(
                tooltip: 'Sil',
                icon: const Icon(Icons.delete_outline),
                onPressed: _askDelete,
              ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  hintText: 'Başlık',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
              TextField(
                controller: _folder,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(color: c.textSecondary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Klasör (isteğe bağlı)',
                  prefixIcon: Icon(Icons.folder_outlined,
                      color: c.textSecondary, size: 18),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
              Divider(color: c.border),
              Expanded(
                child: TextField(
                  controller: _body,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    height: 1.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Notunuzu yazın...',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
