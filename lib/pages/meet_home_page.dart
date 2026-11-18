// ============================================================
// lib/pages/meet_home_page.dart
// (.txt olarak verildi. Projeye eklerken adını meet_home_page.dart yapın.)
//
// Gettic Meet ana ekranı:
//  - Kişiler: sohbet geçmişindeki bireysel kişiler, sesli/görüntülü arama
//  - Son aramalar: gelen/giden, cevaplanan/cevapsız, tekrar ara
// ============================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme.dart';
import '../services/meet_service.dart';
import '../services/supabase_service.dart';

const String _kMeetLogo = 'assets/getticmeet_logo.png';

class MeetHomePage extends StatefulWidget {
  const MeetHomePage({super.key});

  @override
  State<MeetHomePage> createState() => _MeetHomePageState();
}

class _MeetHomePageState extends State<MeetHomePage> {
  final SupabaseService _service = SupabaseService();
  SupabaseClient get _sb => Supabase.instance.client;

  bool _loading = true;
  String _query = '';
  String? _error;
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _history = [];
  final Map<String, String> _names = {};

  String? get _me => _sb.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = _me;
    if (me == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Kişiler: bireysel sohbetlerdeki karşı taraflar (tekrar edenler çıkarılır)
      final convs = await _service.getMyConversationsWithUnread();
      final contacts = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final c in convs) {
        if (c['is_group'] == true) continue;
        final u = c['other_user'];
        if (u == null) continue;
        final id = u['id'].toString();
        if (seen.add(id)) {
          contacts.add({'id': id, 'username': (u['username'] ?? '').toString()});
          _names[id] = (u['username'] ?? '').toString();
        }
      }

      // Son aramalar
      final rows = await _sb
          .from('meet_invites')
          .select()
          .or('from_id.eq.$me,to_id.eq.$me')
          .order('created_at', ascending: false)
          .limit(50);
      final history = List<Map<String, dynamic>>.from(rows);

      // Geçmişte olup kişiler listesinde olmayan karşı tarafların adlarını getir
      final unknown = <String>{};
      for (final r in history) {
        final other = r['from_id'] == me ? r['to_id'] : r['from_id'];
        final id = other.toString();
        if (!_names.containsKey(id)) unknown.add(id);
      }
      if (unknown.isNotEmpty) {
        final profiles = await _sb
            .from('profiles')
            .select('id,username')
            .inFilter('id', unknown.toList());
        for (final p in profiles) {
          _names[p['id'].toString()] = (p['username'] ?? '').toString();
        }
      }

      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _history = history;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Yüklenemedi. Bağlantını kontrol et.';
        _loading = false;
      });
    }
  }

  String _nameOf(String id) => _names[id] ?? 'Bilinmeyen';

  String _otherIdOf(Map<String, dynamic> h) =>
      (h['from_id'] == _me ? h['to_id'] : h['from_id']).toString();

  bool _matches(String name) =>
      _query.isEmpty || name.toLowerCase().contains(_query.toLowerCase());

  List<Map<String, dynamic>> get _filteredContacts =>
      _contacts.where((ct) => _matches(ct['username'] as String)).toList();

  List<Map<String, dynamic>> get _filteredHistory =>
      _history.where((h) => _matches(_nameOf(_otherIdOf(h)))).toList();

  Future<void> _call(String toId, {required bool video}) async {
    try {
      await MeetService.instance.startCall(
        toId: toId,
        toName: _nameOf(toId),
        video: video,
      );
    } catch (_) {
      if (!mounted) return;
      final c = context.appColors;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Arama başlatılamadı'),
        backgroundColor: c.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(_kMeetLogo, width: 28, height: 28,
                errorBuilder: (_, __, ___) => Icon(Icons.videocam, color: c.primary)),
            const SizedBox(width: 10),
            const Text('Gettic Meet'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: c.primary,
        child: _loading
            ? Center(child: CircularProgressIndicator(color: c.primary))
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 120),
                    Center(child: Text(_error!, style: TextStyle(color: c.textSecondary))),
                    const SizedBox(height: 12),
                    Center(child: ElevatedButton(onPressed: _load, child: const Text('Tekrar dene'))),
                  ])
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      TextField(
                        onChanged: (v) => setState(() => _query = v.trim()),
                        decoration: const InputDecoration(
                          hintText: 'Kişi veya arama ara',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _sectionTitle('Kişiler', c),
                      if (_contacts.isEmpty)
                        _empty('Henüz kişi yok. Önce bir sohbet başlatın.', c)
                      else if (_filteredContacts.isEmpty)
                        _empty('Eşleşen kişi yok.', c)
                      else
                        for (final ct in _filteredContacts) _contactTile(ct, c),
                      const SizedBox(height: 20),
                      _sectionTitle('Son aramalar', c),
                      if (_history.isEmpty)
                        _empty('Henüz arama yok.', c)
                      else if (_filteredHistory.isEmpty)
                        _empty('Eşleşen arama yok.', c)
                      else
                        for (final h in _filteredHistory) _historyTile(h, c),
                    ],
                  ),
      ),
    );
  }

  Widget _sectionTitle(String t, AppColors c) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Text(
          t.toUpperCase(),
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _empty(String t, AppColors c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(t, style: TextStyle(color: c.textSecondary)),
      );

  Widget _contactTile(Map<String, dynamic> ct, AppColors c) {
    final name = ct['username'] as String;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: c.primary,
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        title: Text(name, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Sesli ara',
              icon: Icon(Icons.call_outlined, color: c.primary),
              onPressed: () => _call(ct['id'] as String, video: false),
            ),
            IconButton(
              tooltip: 'Görüntülü ara',
              icon: Icon(Icons.videocam_outlined, color: c.primary),
              onPressed: () => _call(ct['id'] as String, video: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyTile(Map<String, dynamic> h, AppColors c) {
    final me = _me;
    final outgoing = h['from_id'] == me;
    final otherId = (outgoing ? h['to_id'] : h['from_id']).toString();
    final video = h['kind'] == 'video';
    final status = (h['status'] ?? '').toString();

    String statusText;
    Color statusColor;
    switch (status) {
      case 'accepted':
      case 'ended':
        statusText = 'Görüşme yapıldı';
        statusColor = c.online;
        break;
      case 'declined':
        statusText = 'Reddedildi';
        statusColor = c.danger;
        break;
      default: // ringing, cancelled
        statusText = outgoing ? 'Cevapsız' : 'Cevapsız arama';
        statusColor = c.danger;
    }

    final when = DateTime.tryParse(h['created_at'].toString())?.toLocal();
    final whenText = when == null ? '' : DateFormat('d MMM HH:mm', 'tr_TR').format(when);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: ListTile(
        leading: Icon(
          outgoing ? Icons.call_made : Icons.call_received,
          color: statusColor,
        ),
        title: Text(_nameOf(otherId),
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${video ? 'Görüntülü' : 'Sesli'} · $statusText · $whenText',
          style: TextStyle(color: c.textSecondary, fontSize: 12),
        ),
        trailing: IconButton(
          tooltip: 'Tekrar ara',
          icon: Icon(video ? Icons.videocam_outlined : Icons.call_outlined, color: c.primary),
          onPressed: () => _call(otherId, video: video),
        ),
      ),
    );
  }
}
