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
import '../pages/incoming_call_page.dart';
import '../pages/meet_page.dart';
import 'call_tone.dart';
import 'meet_log.dart';
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
        .subscribe((status, error) {
      MeetLog.add('S', 'davet kanalı: $status ${error ?? ''}');
    });

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
        .subscribe((status, error) {
      MeetLog.add('S', 'güncelleme kanalı: $status ${error ?? ''}');
    });
    MeetLog.add('S', 'dinleme başladı (uid=$uid)');
    _checkRingingInvites();
  }

  /// Uygulama açılınca ya da ön plana gelince: son 40 sn içinde gelmiş çalan bir arama varsa göster.
  Future<void> _checkRingingInvites() async {
    final me = _myId;
    if (me == null) return;
    try {
      final since = DateTime.now().toUtc().subtract(ringDuration).toIso8601String();
      final rows = await _sb
          .from('meet_invites')
          .select('id, from_id, from_name, kind, created_at')
          .eq('to_id', me)
          .eq('status', 'ringing')
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return;
      final r = rows.first;
      final callId = r['id'].toString();
      if (_pending.containsKey(callId) || _inCall || _showingIncoming) return;

      final created = DateTime.parse(r['created_at'].toString()).toUtc();
      final left = ringDuration - DateTime.now().toUtc().difference(created);
      if (left <= Duration.zero) return;

      _pending[callId] = _PendingCall(
        r['from_id'].toString(),
        (r['from_name'] ?? 'Biri').toString(),
        r['kind'] == 'video',
      );
      _showingIncoming = true;
      _ringTimer?.cancel();
      _ringTimer = Timer(left, () => _onRingTimeout(callId));
      MeetLog.add('S', 'bekleyen arama bulundu: $callId (kalan ${left.inSeconds} sn)');
      if (_isForeground) {
        _startRingtone();
        _showDialog(callId);
      }
    } catch (e) {
      MeetLog.add('S', 'bekleyen arama kontrolü hata: $e');
    }
  }

  /// Bildirim düğmesi (accept/decline) ya da bildirime dokunma.
  Future<void> onPushAction(String callId, String? action) async {
    if (action == 'decline') {
      _endRinging(callId, 'declined');
      return;
    }
    // accept veya gövdeye dokunma: daveti veritabanından al ve aç
    try {
      final row = await _sb
          .from('meet_invites')
          .select('id, from_id, from_name, kind, status')
          .eq('id', callId)
          .maybeSingle();
      if (row == null || row['status'] != 'ringing') {
        MeetLog.add('S', 'push: çağrı artık geçerli değil ($callId)');
        return;
      }
      _pending.remove(callId);
      _ringTimer?.cancel();
      _ringTimer = null;
      _stopRingtone();
      _notifications.cancelCall(callId);
      _showingIncoming = false;
      _setStatus(callId, 'accepted');
      _open(MeetCallPage(
        callId: callId,
        remoteId: row['from_id'].toString(),
        remoteName: (row['from_name'] ?? 'Biri').toString(),
        isCaller: false,
        video: row['kind'] == 'video',
      ));
    } catch (e) {
      MeetLog.add('S', 'push eylemi hata: $e');
    }
  }

  /// main.dart: uygulama ön plana gelince çağrılır.
  void onAppResumed() => _checkRingingInvites();

  void stopListening() {
    MeetLog.add('S', 'dinleme durduruldu');
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
    MeetLog.add('S', 'arama başlatılıyor: $callId -> $toName (${video ? 'görüntülü' : 'sesli'})');
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

    MeetLog.add('S', 'davet kaydedildi (ringing)');
    // Alıcıya push gönder (uygulama kapalıyken de ulaşsın)
    try {
      final res = await _sb.functions.invoke('meet-push', body: {'callId': callId});
      MeetLog.add('S', 'push istendi: status=${res.status}');
    } catch (e) {
      MeetLog.add('S', 'push HATA: $e');
    }
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
    final callId = rec['id'].toString();
    MeetLog.add('S', 'davet geldi: $callId status=${rec['status']} from=${rec['from_name']} kind=${rec['kind']}');
    if (rec['status'] != 'ringing') return;

    // Meşgulse otomatik reddet
    // Meşgul: yalnızca gerçek bir çağrı ekranı ya da açık diyalog varsa
    // (takılı kalmış bayrak yüzünden davetler sessizce reddedilmesin)
    if (_inCall || (_showingIncoming && _dialogCtx != null)) {
      MeetLog.add('S', 'meşgul: davet otomatik reddedildi (inCall=$_inCall showing=$_showingIncoming)');
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

    MeetLog.add('S', 'çalıyor (${_isForeground ? 'ön plan: diyalog' : 'arka plan: bildirim'}), 40 sn');
    if (_isForeground) {
      _startRingtone();
      _showDialog(callId);
    } else {
      // Arka planda bildirimi push gönderir; burada yerel bildirim gösterilmez
      MeetLog.add('S', 'arka plan: push bildirimi bekleniyor');
    }
  }

  /// Davet güncellendi: arayan iptal etti ya da bitirdi.
  void _onInviteUpdate(Map<String, dynamic> rec) {
    final status = rec['status'];
    final callId = rec['id'].toString();
    MeetLog.add('S', 'davet güncellendi: $callId status=$status bekleyen=${_pending.containsKey(callId)}');
    if (status != 'cancelled' && status != 'ended') return;
    if (!_pending.containsKey(callId)) return;

    // Arka plandaysa cevapsız arama olarak bildir
    _dismissRinging(callId, missed: !_isForeground);
  }

  void _showDialog(String callId) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      _endRinging(callId, 'declined');
      return;
    }
    final p = _pending[callId];
    if (p == null) return;

    nav.push<void>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) {
        _dialogCtx = ctx;
        return IncomingCallPage(
          fromName: p.fromName,
          video: p.video,
          onAccept: () {
            _closeDialog();
            _accept(callId);
          },
          onDecline: () {
            _closeDialog();
            _endRinging(callId, 'declined');
          },
        );
      },
    )).whenComplete(() {
      _dialogCtx = null;
    });
  }

  /// Bildirimdeki Cevapla / Reddet düğmeleri veya gövdeye dokunma.
  void onNotificationResponse(NotificationResponse r) {
    MeetLog.add('S', 'bildirim tepkisi: action=${r.actionId} payload=${r.payload}');
    final callId = r.payload;
    if (callId == null) return;

    if (r.actionId == NotificationService.actionDecline) {
      _endRinging(callId, 'declined');
      return;
    }
    _accept(callId);
  }

  void _accept(String callId) {
    MeetLog.add('S', 'kabul edildi: $callId');
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
    MeetLog.add('S', 'zaman aşımı (40 sn): $callId');
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
    MeetLog.add('S', 'çağrı sonlandı: $callId -> $status');
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
    MeetLog.add('S', 'karşı taraf iptal etti: $callId (cevapsız bildirim=$missed)');
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

  bool _ringWanted = false;

  Future<void> _startRingtone() async {
    _ringWanted = true;
    if (_ringPlayer != null) return;
    final player = await CallTone.loop(CallTone.ringtone);
    // Yükleme sürerken çağrı kabul/red edildiyse sesi hemen kapat
    if (!_ringWanted) {
      await CallTone.stop(player);
      return;
    }
    _ringPlayer = player;
    MeetLog.add('S', player == null ? 'zil sesi çalınamadı' : 'zil sesi çalıyor');
  }

  Future<void> _stopRingtone() async {
    _ringWanted = false;
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
      MeetLog.add('S', 'durum yazıldı: $callId -> $status');
    } catch (e) {
      MeetLog.add('S', 'durum yazılamadı ($status): $e');
    }
  }

  /// Görüşme ekranı, görüşme bitince durum yazmak için kullanır.
  Future<void> markStatus(String callId, String status) =>
      _setStatus(callId, status);

  void _open(Widget page) {
    appNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => page));
  }
}
