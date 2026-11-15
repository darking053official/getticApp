// ============================================================
// lib/pages/meet_page.dart
// (.txt olarak verildi. Projeye eklerken adını meet_page.dart yapın.)
//
// 1:1 P2P görüşme (flutter_webrtc). Sinyalleşme: Supabase Realtime
// "call:<id>" kanalı (yalnızca çağrı tarafları bilir).
// Not: STUN kullanılır. Bazı ağlarda (kurumsal Wi-Fi, simetrik NAT)
// doğrudan bağlantı kurulamaz; bu durumda TURN sunucusu gerekir.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme.dart';

class MeetCallPage extends StatefulWidget {
  final String callId;
  final String remoteId;
  final String remoteName;
  final bool isCaller;
  final bool video;

  const MeetCallPage({
    super.key,
    required this.callId,
    required this.remoteId,
    required this.remoteName,
    required this.isCaller,
    required this.video,
  });

  @override
  State<MeetCallPage> createState() => _MeetCallPageState();
}

class _MeetCallPageState extends State<MeetCallPage> {
  final RTCVideoRenderer _localView = RTCVideoRenderer();
  final RTCVideoRenderer _remoteView = RTCVideoRenderer();

  MediaStream? _localStream;
  RTCPeerConnection? _pc;
  RealtimeChannel? _signal;
  RealtimeChannel? _inviteWatch;
  Timer? _joinTimer;

  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteSet = false;
  bool _offerMade = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _ended = false;
  String _status = 'Hazırlanıyor...';

  SupabaseClient get _sb => Supabase.instance.client;

  static const Map<String, dynamic> _config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  // ----------------------------------------------------------
  // Başlatma
  // ----------------------------------------------------------
  Future<void> _start() async {
    await _localView.initialize();
    await _remoteView.initialize();

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.video ? {'facingMode': 'user'} : false,
      });
    } catch (_) {
      _fail('Mikrofon veya kamera açılamadı. İzinleri kontrol edin.');
      return;
    }
    _localView.srcObject = _localStream;

    _pc = await createPeerConnection(_config);
    final pc = _pc!;
    for (final track in _localStream!.getTracks()) {
      await pc.addTrack(track, _localStream!);
    }

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() => _remoteView.srcObject = event.streams.first);
      }
    };

    pc.onIceCandidate = (c) {
      _send({
        'type': 'ice',
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };

    pc.onConnectionState = (state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _status = 'Bağlandı');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _fail('Bağlantı kurulamadı (ağ engeli olabilir)');
      }
    };

    _signal = _sb
        .channel('call:${widget.callId}', opts: const RealtimeChannelConfig(private: true))
        .onBroadcast(event: 'signal', callback: (p) => _onSignal(p))
        .subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) _onSubscribed();
    });

    // Arayan tarafta davet durumu izlenir (alıcı reddederse kapat)
    _inviteWatch = _sb
        .channel('invite-${widget.callId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'meet_invites',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.callId,
          ),
          callback: (payload) {
            final st = payload.newRecord['status'];
            if (st == 'declined' || st == 'cancelled') {
              _fail('Arama reddedildi');
            }
          },
        )
        .subscribe();

    if (mounted) setState(() => _status = 'Bağlanılıyor...');
  }

  void _onSubscribed() {
    if (widget.isCaller) {
      // Arayan, alıcının "join" mesajını bekler
      _send({'type': 'caller-ready'});
    } else {
      // Alıcı, arayan hazır olana kadar "join" göndermeye devam eder
      _joinTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        if (!_offerMade) _send({'type': 'join'});
      });
      _send({'type': 'join'});
    }
  }

  // ----------------------------------------------------------
  // Sinyalleşme
  // ----------------------------------------------------------
  void _send(Map<String, dynamic> payload) {
    _signal?.sendBroadcastMessage(event: 'signal', payload: payload);
  }

  Future<void> _onSignal(Map<String, dynamic> p) async {
    if (_ended) return;
    final type = p['type'];

    if (type == 'join' || type == 'caller-ready') {
      if (widget.isCaller && !_offerMade) await _makeOffer();
    } else if (type == 'offer') {
      _joinTimer?.cancel();
      await _handleOffer(p);
    } else if (type == 'answer') {
      await _pc?.setRemoteDescription(
          RTCSessionDescription(p['sdp'] as String, p['sdpType'] as String));
      await _markRemoteSet();
    } else if (type == 'ice') {
      final c = RTCIceCandidate(
        p['candidate'] as String?,
        p['sdpMid'] as String?,
        p['sdpMLineIndex'] as int?,
      );
      if (_remoteSet) {
        await _pc?.addCandidate(c);
      } else {
        _pendingIce.add(c);
      }
    } else if (type == 'bye') {
      _fail('Görüşme sonlandırıldı');
    }
  }

  Future<void> _makeOffer() async {
    _offerMade = true;
    final pc = _pc;
    if (pc == null) return;
    final offer = await pc.createOffer({});
    await pc.setLocalDescription(offer);
    _send({'type': 'offer', 'sdp': offer.sdp, 'sdpType': offer.type});
  }

  Future<void> _handleOffer(Map<String, dynamic> p) async {
    final pc = _pc;
    if (pc == null) return;
    await pc.setRemoteDescription(
        RTCSessionDescription(p['sdp'] as String, p['sdpType'] as String));
    await _markRemoteSet();
    final answer = await pc.createAnswer({});
    await pc.setLocalDescription(answer);
    _send({'type': 'answer', 'sdp': answer.sdp, 'sdpType': answer.type});
  }

  Future<void> _markRemoteSet() async {
    _remoteSet = true;
    for (final c in _pendingIce) {
      await _pc?.addCandidate(c);
    }
    _pendingIce.clear();
  }

  // ----------------------------------------------------------
  // Kontroller
  // ----------------------------------------------------------
  void _toggleMute() {
    setState(() => _muted = !_muted);
    for (final t in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_muted;
    }
  }

  void _toggleCamera() {
    setState(() => _cameraOff = !_cameraOff);
    for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_cameraOff;
    }
  }

  void _hangUp() {
    if (_ended) return;
    _send({'type': 'bye'});
    _sb.from('meet_invites').update({'status': 'ended'}).eq('id', widget.callId).then((_) {}, onError: (_) {});
    _finish();
  }

  void _fail(String message) {
    if (_ended) return;
    if (mounted) {
      final c = context.appColors;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: c.danger));
    }
    _finish();
  }

  void _finish() {
    if (_ended) return;
    _ended = true;
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _cleanup() async {
    _ended = true;
    _joinTimer?.cancel();
    final sig = _signal;
    if (sig != null) await _sb.removeChannel(sig);
    final inv = _inviteWatch;
    if (inv != null) await _sb.removeChannel(inv);
    for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      t.stop();
    }
    await _localStream?.dispose();
    await _pc?.close();
    await _localView.dispose();
    await _remoteView.dispose();
  }

  // ----------------------------------------------------------
  // Görünüm
  // ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final hasRemote = _remoteView.srcObject != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: hasRemote
                  ? RTCVideoView(_remoteView,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: c.primary,
                            child: Text(
                              widget.remoteName.isNotEmpty
                                  ? widget.remoteName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  fontSize: 32, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(widget.remoteName,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 18)),
                          const SizedBox(height: 6),
                          Text(_status,
                              style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
            ),
            if (widget.video)
              Positioned(
                top: 12,
                right: 12,
                width: 110,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(_localView,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _circle(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    onTap: _toggleMute,
                    color: _muted ? Colors.white24 : Colors.white12,
                  ),
                  const SizedBox(width: 18),
                  if (widget.video)
                    _circle(
                      icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                      onTap: _toggleCamera,
                      color: _cameraOff ? Colors.white24 : Colors.white12,
                    ),
                  const SizedBox(width: 18),
                  _circle(
                    icon: Icons.call_end,
                    onTap: _hangUp,
                    color: c.danger,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle({required IconData icon, required VoidCallback onTap, required Color color}) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 60,
          height: 60,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}
