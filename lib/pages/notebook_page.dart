// ============================================================
// lib/pages/notebook_page.dart
//
// Notebook: not listesi, arama, düzenleme (otomatik kayıt), silme.
// Notlar SharedPreferences'ta JSON olarak tutulur.
// Ek paket gerekmez (intl, shared_preferences zaten pubspec'te).
// ============================================================

import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

// ============================================================
// MODEL
// ============================================================
class NoteItem {
  final String id;
  final String title;
  final String body;
  final int updatedAt; // ms

  const NoteItem({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  static String newId() {
    final r = Random.secure();
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$t${r.nextInt(1 << 30).toRadixString(36)}';
  }

  factory NoteItem.fromJson(Map<String, dynamic> j) => NoteItem(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        updatedAt: (j['updatedAt'] ?? 0) as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'updatedAt': updatedAt,
      };
}

/// Editörden dönen sonuç: ya kaydedilmiş not ya da silinen notun id'si.
class NoteResult {
  final NoteItem? note;
  final String? deletedId;

  const NoteResult._({this.note, this.deletedId});

  factory NoteResult.saved(NoteItem note) => NoteResult._(note: note);
  factory NoteResult.deleted(String id) => NoteResult._(deletedId: id);
}

// ============================================================
// DEPO
// ============================================================
class NotebookRepository {
  NotebookRepository._();
  static const String _key = 'notebook_notes_v1';

  static Future<List<NoteItem>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => NoteItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> save(List<NoteItem> notes) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      jsonEncode(notes.map((n) => n.toJson()).toList()),
    );
  }
}

// ============================================================
// LİSTE SAYFASI
// ============================================================
class NotebookPage extends StatefulWidget {
  const NotebookPage({super.key});

  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<NotebookPage> {
  List<NoteItem> _notes = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await NotebookRepository.load();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  List<NoteItem> get _visible {
    final q = _query.trim().toLowerCase();
    final list = _notes.where((n) {
      if (q.isEmpty) return true;
      return n.title.toLowerCase().contains(q) ||
          n.body.toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<void> _open(NoteItem? note) async {
    final result = await Navigator.push<NoteResult>(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)),
    );
    if (result == null || !mounted) return;

    if (result.deletedId != null) {
      _notes.removeWhere((n) => n.id == result.deletedId);
    } else if (result.note != null) {
      final saved = result.note!;
      final idx = _notes.indexWhere((n) => n.id == saved.id);
      if (idx == -1) {
        _notes.add(saved);
      } else {
        _notes[idx] = saved;
      }
    }

    await NotebookRepository.save(_notes);
    if (mounted) setState(() {});
  }

  Future<void> _confirmDelete(NoteItem n) async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Notu sil', style: TextStyle(color: c.textPrimary)),
        content: Text(
          '"${n.title.isEmpty ? 'Başlıksız' : n.title}" kalıcı olarak silinecek.',
          style: TextStyle(color: c.textSecondary),
        ),
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
    _notes.removeWhere((x) => x.id == n.id);
    await NotebookRepository.save(_notes);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(title: const Text('Notebook')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Yeni not',
        onPressed: () => _open(null),
        child: const Icon(Icons.edit_note),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Notlarda ara',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: c.primary),
                  )
                : visible.isEmpty
                    ? Center(
                        child: Text(
                          _notes.isEmpty
                              ? 'Henüz not yok. + ile ekleyebilirsin.'
                              : 'Sonuç bulunamadı.',
                          style: TextStyle(color: c.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                        itemCount: visible.length,
                        itemBuilder: (_, i) => _card(visible[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _card(NoteItem n) {
    final c = context.appColors;
    final date = DateFormat('d MMM yyyy HH:mm', 'tr_TR')
        .format(DateTime.fromMillisecondsSinceEpoch(n.updatedAt));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
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
                Text(
                  n.title.isEmpty ? 'Başlıksız' : n.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: n.title.isEmpty ? c.textSecondary : c.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    n.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 8),
                Text(date, style: TextStyle(color: c.textHint, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// EDİTÖR
// Geri tuşu ve çıkış otomatik kaydeder. Tamamen boş not kaydedilmez.
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
  late final TextEditingController _body =
      TextEditingController(text: widget.note?.body ?? '');
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => _changed = true);
    _body.addListener(() => _changed = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _finish() {
    if (!_changed) {
      Navigator.pop(context);
      return;
    }

    final title = _title.text.trim();
    final body = _body.text.trimRight();

    if (title.isEmpty && body.trim().isEmpty) {
      // Tümü silindiyse mevcut not kaldırılır, yeni not hiç eklenmez
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
        appBar: AppBar(
          title: Text(widget.note == null ? 'Yeni not' : 'Not'),
          leading: IconButton(
            tooltip: 'Kaydet ve çık',
            icon: const Icon(Icons.arrow_back),
            onPressed: _finish,
          ),
          actions: [
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
                  fontSize: 20,
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
