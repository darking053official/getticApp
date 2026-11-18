// ============================================================
// lib/services/meet_push_handler.dart
// (.txt olarak verildi. Projeye eklerken adını meet_push_handler.dart yapın.)
//
// OneSignal bildirimine tıklama ve bildirim düğmeleri (Cevapla / Reddet).
// main.dart içinde OneSignal başlatıldıktan sonra registerMeetPushHandlers() çağrılır.
// ============================================================

import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'meet_log.dart';
import 'meet_service.dart';

void registerMeetPushHandlers() {
  OneSignal.Notifications.addClickListener((event) {
    final data = event.notification.additionalData ?? {};
    if (data['type'] != 'meet_invite') return;

    final callId = data['callId']?.toString();
    if (callId == null || callId.isEmpty) return;

    // actionId: bildirim düğmesine basıldıysa "accept" / "decline", gövdeye basıldıysa null
    final action = event.result.actionId;
    MeetLog.add('N', 'push tıklandı: callId=$callId action=$action');
    MeetService.instance.onPushAction(callId, action);
  });
}
