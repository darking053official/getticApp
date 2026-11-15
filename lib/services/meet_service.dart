// ============================================================
// lib/services/meet_service.dart
// (.txt olarak verildi. Projeye eklerken adını meet_service.dart yapın.)
//
// Gettic Meet (P2P, 1:1).
//  - Davet: meet_invites tablosuna yazılır, alıcı Realtime ile anında görür.
//  - Gelen çağrı ekranı: global navigatorKey üzerinden gösterilir.
//  - Görüşme: meet_page.dart içinde WebRTC.
// ============================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme.dart';
import '../pages/meet_page.dart';
import 'web_crypto.dart';

/// MaterialApp'e verilir: gelen çağrı ekranını her yerden açabilmek için.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class MeetService {
  MeetService._();
  static final MeetService instance = MeetService._();

  RealtimeChannel? _inbox;
  bool _showingIncoming = false;

  SupabaseClient get _sb => Supabase.instance.client;

  String? get _myId => _sb.auth.currentUser?.id;

  /// Oturum açılınca çağrılır: gelen davetleri dinler.
  void startListening() {
    final uid = _myId;
    if (uid == null) return;
    stopListening();

    _inbox = _sb
        .channel('meet-invites-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'meet_invites',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'to_id',
            value: uid,
          ),
          callback: (payload) => _onInvite(payload.newRecord),
        )
        .subscribe();
  }

  void stopListening() {
    final ch = _inbox;
    if (ch != null) _sb.removeChannel(ch);
    _inbox = null;
  }

  /// Arama başlatır: daveti kaydeder ve çağrı ekranını açar.
  Future<void> startCall({
    required String toId,
    required String toName,
    required bool video,
  }) async {
    final me = _myId;
    if (me == null) return;

    final callId = WebCrypto.uuidV4();
    final profile = await _sb
        .from('profiles')
        .select('username')
        .eq('id', me)
        .maybeSingle();
    final myName = (profile?['username'] ?? 'Biri').toString();

    await _sb.from('meet_invites').insert({
      'id': callId,
      'from_id': me,
      'to_id': toId,
      'from_name': myName,
      'kind': video ? 'video' : 'audio',
      'status': 'ringing',
    });

    _open(MeetCallPage(
      callId: callId,
      remoteId: toId,
      remoteName: toName,
      isCaller: true,
      video: video,
    ));
  }

  // ----------------------------------------------------------
  // Gelen çağrı
  // ----------------------------------------------------------
  void _onInvite(Map<String, dynamic> rec) {
    if (_showingIncoming) return;
    if (rec['status'] != 'ringing') return;

    final callId = rec['id'].toString();
    final fromId = rec['from_id'].toString();
    final fromName = (rec['from_name'] ?? 'Biri').toString();
    final video = rec['kind'] == 'video';

    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;

    _showingIncoming = true;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dctx) {
        final c = dctx.appColors;
        // 40 sn cevapsız kalırsa otomatik reddet
        Future.delayed(const Duration(seconds: 40), () {
          if (Navigator.of(dctx).canPop()) {
            Navigator.of(dctx).pop();
            _setStatus(callId, 'cancelled');
          }
        });
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text(
            video ? 'Görüntülü arama' : 'Sesli arama',
            style: TextStyle(color: c.textPrimary),
          ),
          content: Text('$fromName arıyor',
              style: TextStyle(color: c.textSecondary)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dctx).pop();
                _setStatus(callId, 'declined');
              },
              child: Text('Reddet', style: TextStyle(color: c.danger)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dctx).pop();
                _setStatus(callId, 'accepted');
                _open(MeetCallPage(
                  callId: callId,
                  remoteId: fromId,
                  remoteName: fromName,
                  isCaller: false,
                  video: video,
                ));
              },
              child: Text('Cevapla', style: TextStyle(color: c.primary)),
            ),
          ],
        );
      },
    ).whenComplete(() => _showingIncoming = false);
  }

  Future<void> _setStatus(String callId, String status) async {
    try {
      await _sb
          .from('meet_invites')
          .update({'status': status})
          .eq('id', callId);
    } catch (_) {}
  }

  void _open(Widget page) {
    appNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => page));
  }
}
