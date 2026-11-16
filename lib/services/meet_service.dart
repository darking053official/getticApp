// ============================================================
// lib/services/meet_service.dart
// (.txt olarak verildi. Projeye eklerken adını meet_service.dart yapın.)
//
// Gettic Meet (P2P, 1:1).
//  - Davet: meet_invites tablosuna yazılır, alıcı Realtime ile görür.
//  - Uygulama açıksa: çağrı diyaloğu + gelen arama zil sesi (assets/ringtone.ogg).
//  - Uygulama arka plandaysa: "Cevapla / Reddet" bildirimi (ses ayarlara bağlı).
//  - Arayan iptal ederse (ya da bitirirse) alıcıdaki çağrı ekranı/bildirim kapanır.
//  - 40 sn cevapsız: arayana "cancelled"; alıcı arka plandaysa cevapsız arama bildirimi.
//  - Meşgul: görüşmedeyken gelen davet otomatik reddedilir.
// Not: Uygulama tamamen kapalıysa çağrı bildirimi gelmez (push gerekir).
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme.dart';
import '../pages/meet_page.dart';
import 'call_tone.dart';
import 'notification_service.dart';
import 'web_crypto.dart';

/// MaterialApp'e verilir: gelen çağrı ekranını her yerden açabilmek için.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class _PendingCall {
  final String fromId;
  final String fromName;
  final bool video;
  const _PendingCall(this.fromId, this.fromName, this.video);
}

class MeetService {
  MeetService._();
  static final MeetService instance = MeetService._();

  static const Duration ringDuration = Duration(seconds: 40);

  final NotificationService _notifications = NotificationService();

  RealtimeChannel? _inbox;
  RealtimeChannel? _inboxUpdates;
  bool _showingIncoming = false;
  bool _inCall = false;
  Timer? _ringTimer;
  BuildContext? _dialogCtx;
  AudioPlayer? _ringPlayer;
  final Map<String, _PendingCall> _pending = {};

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _myId => _sb.auth.currentUser?.id;

  /// Görüşme ekranı açılınca/kapanınca çağrılır (meşgul kontrolü için).
  void setInCall(bool value) => _inCall = value;

  bool get isInCall => _inCall;

  bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  // ----------------------------------------------------------
  // Dinleme
  // ----------------------------------------------------------

  /// Oturum açılınca çağrılır: yeni davetleri ve davet güncellemelerini dinler.
  void startListening() {
    final uid = _myId;
    if (uid == null) return;
    stopListening();

    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'to_id',
      value: uid,
    );

    _inbox = _sb
        .channel('meet-invites-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'meet_invites',
          filter: filter,
          callback: (payload) => _onInvite(payload.newRecord),
        )
        .subscribe();

    // Arayan iptal ederse ya da bitirirse alıcıdaki çağrı kapanır
    _inboxUpdates = _sb
        .channel('meet-invite-updates-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'meet_invites',
          filter: filter,
          callback: (payload) => _onInviteUpdate(payload.newRecord),
        )
        .subscribe();
  }

  void stopListening() {
    final a = _inbox;
    final b = _inboxUpdates;
    if (a != null) _sb.removeChannel(a);
    if (b != null) _sb.removeChannel(b);
    _inbox = null;
    _inboxUpdates = null;
  }

  // ----------------------------------------------------------
  // Arama başlatma
  // ----------------------------------------------------------

  Future<void> startCall({
    required String toId,
    required String toName,
    required bool video,
  }) async {
    final me = _myId;
    if (me == null) throw StateError('Oturum yok');
    if (_inCall) throw StateError('Zaten bir görüşmedesiniz');

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
  // Gelen davet
  // ----------------------------------------------------------

  void _onInvite(Map<String, dynamic> rec) {
    if (rec['status'] != 'ringing') return;

    final callId = rec['id'].toString();

    // Meşgulse otomatik reddet
    if (_inCall || _showingIncoming) {
      _setStatus(callId, 'declined');
      return;
    }

    final fromId = rec['from_id'].toString();
    final fromName = (rec['from_name'] ?? 'Biri').toString();
    final video = rec['kind'] == 'video';
    _pending[callId] = _PendingCall(fromId, fromName, video);

    _showingIncoming = true;
    _ringTimer?.cancel();
    _ringTimer = Timer(ringDuration, () => _onRingTimeout(callId));

    if (_isForeground) {
      _startRingtone();
      _showDialog(callId);
    } else {
      // Arka planda: sistem bildirimi (Cevapla / Reddet düğmeleri, ses ayarlara bağlı)
      _notifications.showIncomingCall(
        callId: callId,
        fromName: fromName,
        video: video,
      );
    }
  }

  /// Davet güncellendi: arayan iptal etti ya da bitirdi.
  void _onInviteUpdate(Map<String, dynamic> rec) {
    final status = rec['status'];
    if (status != 'cancelled' && status != 'ended') return;

    final callId = rec['id'].toString();
    if (!_pending.containsKey(callId)) return;

    // Arka plandaysa cevapsız arama olarak bildir
    _dismissRinging(callId, missed: !_isForeground);
  }

  void _showDialog(String callId) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) {
      _endRinging(callId, 'declined');
      return;
    }
    final p = _pending[callId];
    if (p == null) return;

    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dctx) {
        _dialogCtx = dctx;
        final c = dctx.appColors;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text(
            p.video ? 'Görüntülü arama' : 'Sesli arama',
            style: TextStyle(color: c.textPrimary),
          ),
          content: Text('${p.fromName} arıyor',
              style: TextStyle(color: c.textSecondary)),
          actions: [
            TextButton(
              onPressed: () {
                _closeDialog();
                _endRinging(callId, 'declined');
              },
              child: Text('Reddet', style: TextStyle(color: c.danger)),
            ),
            TextButton(
              onPressed: () {
                _closeDialog();
                _accept(callId);
              },
              child: Text('Cevapla', style: TextStyle(color: c.primary)),
            ),
          ],
        );
      },
    ).whenComplete(() {
      _dialogCtx = null;
    });
  }

  /// Bildirimdeki Cevapla / Reddet düğmeleri veya gövdeye dokunma.
  void onNotificationResponse(NotificationResponse r) {
    final callId = r.payload;
    if (callId == null) return;

    if (r.actionId == NotificationService.actionDecline) {
      _endRinging(callId, 'declined');
      return;
    }
    _accept(callId);
  }

  void _accept(String callId) {
    final p = _pending.remove(callId);
    _stopRingtone();
    _notifications.cancelCall(callId);
    _ringTimer?.cancel();
    _ringTimer = null;
    _showingIncoming = false;

    if (p == null) {
      // Uygulama yeniden başlatıldıysa davet artık geçerli olmayabilir
      _setStatus(callId, 'cancelled');
      return;
    }
    _setStatus(callId, 'accepted');
    _open(MeetCallPage(
      callId: callId,
      remoteId: p.fromId,
      remoteName: p.fromName,
      isCaller: false,
      video: p.video,
    ));
  }

  void _onRingTimeout(String callId) {
    final p = _pending.remove(callId);
    _closeDialog();
    _stopRingtone();
    _notifications.cancelCall(callId);
    _setStatus(callId, 'cancelled');
    if (p != null && !_isForeground) {
      _notifications.showMissedCall(
        callId: callId,
        fromName: p.fromName,
        video: p.video,
      );
    }
    _showingIncoming = false;
    _ringTimer = null;
  }

  /// Çağrıyı reddeder ya da kapatır ve durumu kaydeder.
  void _endRinging(String callId, String status) {
    _pending.remove(callId);
    _ringTimer?.cancel();
    _ringTimer = null;
    _showingIncoming = false;
    _stopRingtone();
    _notifications.cancelCall(callId);
    _setStatus(callId, status);
  }

  /// Karşı taraf iptal ettiğinde: ekranı ve bildirimi kapatır, durumu değiştirmez.
  void _dismissRinging(String callId, {required bool missed}) {
    final p = _pending.remove(callId);
    _ringTimer?.cancel();
    _ringTimer = null;
    _showingIncoming = false;
    _closeDialog();
    _stopRingtone();
    _notifications.cancelCall(callId);
    if (missed && p != null) {
      _notifications.showMissedCall(
        callId: callId,
        fromName: p.fromName,
        video: p.video,
      );
    }
  }

  // ----------------------------------------------------------
  // Yardımcılar
  // ----------------------------------------------------------

  Future<void> _startRingtone() async {
    if (_ringPlayer != null) return;
    _ringPlayer = await CallTone.loop(CallTone.ringtone);
  }

  Future<void> _stopRingtone() async {
    final p = _ringPlayer;
    _ringPlayer = null;
    await CallTone.stop(p);
  }

  void _closeDialog() {
    final ctx = _dialogCtx;
    if (ctx != null && ctx.mounted && Navigator.of(ctx).canPop()) {
      Navigator.of(ctx).pop();
    }
    _dialogCtx = null;
  }

  Future<void> _setStatus(String callId, String status) async {
    try {
      await _sb
          .from('meet_invites')
          .update({'status': status})
          .eq('id', callId);
    } catch (_) {}
  }

  /// Görüşme ekranı, görüşme bitince durum yazmak için kullanır.
  Future<void> markStatus(String callId, String status) =>
      _setStatus(callId, status);

  void _open(Widget page) {
    appNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => page));
  }
}
