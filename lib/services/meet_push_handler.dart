// ============================================================
// lib/services/meet_push_handler.dart
// (.txt olarak verildi. Projeye eklerken adını meet_push_handler.dart yapın.)
//
// OneSignal bildirimine tıklama ve bildirim düğmeleri (Cevapla / Reddet).
// main.dart içinde OneSignal başlatıldıktan sonra registerMeetPushHandlers() çağrılır.
// ============================================================

import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../pages/chat_room_page.dart';
import 'meet_log.dart';
import 'meet_service.dart';

void registerMeetPushHandlers() {
  OneSignal.Notifications.addClickListener((event) {
    final data = event.notification.additionalData ?? {};
    if (data['type'] == 'chat_message') {
      final convId = data['conversationId']?.toString();
      if (convId != null) _openChatFromPush(convId);
      return;
    }
    if (data['type'] != 'meet_invite') return;

    final callId = data['callId']?.toString();
    if (callId == null || callId.isEmpty) return;

    // actionId: bildirim düğmesine basıldıysa "accept" / "decline", gövdeye basıldıysa null
    final action = event.result.actionId;
    MeetLog.add('N', 'push tıklandı: callId=$callId action=$action');
    MeetService.instance.onPushAction(callId, action);
  });
}

/// Sohbet bildirimine dokunulunca ilgili sohbeti açar.
Future<void> _openChatFromPush(String convId) async {
  try {
    final sb = Supabase.instance.client;
    final me = sb.auth.currentUser?.id;
    if (me == null) return;
    final row = await sb
        .from('conversation_members')
        .select('user_id, profiles(*)')
        .eq('conversation_id', convId)
        .neq('user_id', me)
        .limit(1)
        .maybeSingle();
    final p = row?['profiles'];
    if (p == null) return;
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(
      builder: (_) => ChatRoomPage(
        conversationId: convId,
        otherUser: Profile.fromJson(Map<String, dynamic>.from(p as Map)),
      ),
    ));
  } catch (e) {
    MeetLog.add('N', 'sohbet açılamadı: $e');
  }
}
