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
import 'chat_lock_service.dart';
import 'meet_log.dart';
import 'supabase_service.dart';
import 'meet_service.dart';

void registerMeetPushHandlers() {
  OneSignal.Notifications.addClickListener((event) {
    final data = event.notification.additionalData ?? {};
    if (data['type'] == 'chat_message') {
      final convId = data['conversationId']?.toString();
      if (convId == null) return;
      // "Okundu olarak işaretle" düğmesi: sohbeti açmadan okundu yap
      if (event.result.actionId == 'read') {
        SupabaseService().markConversationRead(convId);
        return;
      }
      // "Yanıtla" ya da gövdeye dokunma: sohbeti aç
      _openChatFromPush(convId);
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
    final conv = await sb
        .from('conversations')
        .select('type, name, created_by')
        .eq('id', convId)
        .maybeSingle();
    if (conv == null) return;
    final isGroup = conv['type'] == 'group';

    Profile? other;
    if (!isGroup) {
      final row = await sb
          .from('conversation_members')
          .select('user_id, profiles(*)')
          .eq('conversation_id', convId)
          .neq('user_id', me)
          .limit(1)
          .maybeSingle();
      final p = row?['profiles'];
      if (p == null) return;
      other = Profile.fromJson(Map<String, dynamic>.from(p as Map));
    }

    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    // Kilitli sohbetse bildirimden de PIN iste
    final unlocked = await ChatLock.instance.ensureUnlocked(nav.context, convId);
    if (!unlocked) return;
    nav.push(MaterialPageRoute(
      builder: (_) => ChatRoomPage(
        conversationId: convId,
        otherUser: other ??
            Profile(id: '', username: (conv['name'] ?? 'Grup').toString()),
        isGroup: isGroup,
        groupName: conv['name'] as String?,
        groupCreatedBy: conv['created_by'] as String?,
      ),
    ));
  } catch (e) {
    MeetLog.add('N', 'sohbet açılamadı: $e');
  }
}
