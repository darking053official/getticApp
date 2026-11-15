// ============================================================
// lib/services/notification_service.dart
// (.txt olarak verildi. Projeye eklerken adını notification_service.dart yapın.)
//
// Kanallar:
//  - gettic_messages : mesaj bildirimleri
//  - gettic_calls    : gelen arama (Cevapla / Reddet düğmeli, 40 sn)
//  - gettic_missed   : cevapsız arama
// Gerekli paketler: flutter_local_notifications (^17.2.x), timezone (^0.9.x)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Kanal kimlikleri
  static const String messagesChannelId = 'gettic_messages';
  static const String callsChannelId = 'gettic_calls';
  static const String missedChannelId = 'gettic_missed';

  // Gelen arama düğmeleri
  static const String actionAccept = 'accept';
  static const String actionDecline = 'decline';

  static const Color _brand = Color(0xFF7c3aed);

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  void Function(NotificationResponse)? _onResponse;
  bool _ready = false;

  /// Bir kez çağrılır. [onResponse] bildirime veya düğmesine basılınca tetiklenir.
  Future<void> initialize({void Function(NotificationResponse)? onResponse}) async {
    if (onResponse != null) _onResponse = onResponse;
    if (_ready) return;

    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (r) {
        final cb = _onResponse;
        if (cb != null) cb(r);
      },
    );

    await _createChannels();
    _ready = true;
    await _requestPermissions();
  }

  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(const AndroidNotificationChannel(
      messagesChannelId,
      'Mesaj bildirimleri',
      description: 'Yeni mesaj bildirimleri',
      importance: Importance.high,
      enableLights: true,
      ledColor: _brand,
    ));

    await android.createNotificationChannel(const AndroidNotificationChannel(
      callsChannelId,
      'Gelen aramalar',
      description: 'Gelen sesli ve görüntülü aramalar',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));

    await android.createNotificationChannel(const AndroidNotificationChannel(
      missedChannelId,
      'Cevapsız aramalar',
      description: 'Cevaplanmayan aramalar',
      importance: Importance.defaultImportance,
    ));
  }

  Future<void> _requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Bildirim kimliği: çağrı kimliğinden (uuid) sabit bir int üretir
  int idFor(String key) => key.hashCode & 0x7fffffff;

  // ----------------------------------------------------------
  // Mesaj
  // ----------------------------------------------------------
  Future<void> showMessage({
    required String key,
    required String title,
    required String body,
    String? payload,
  }) {
    return _plugin.show(
      idFor(key),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          messagesChannelId,
          'Mesaj bildirimleri',
          channelDescription: 'Yeni mesaj bildirimleri',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: _brand,
          enableLights: true,
          ledColor: _brand,
          ledOnMs: 1000,
          ledOffMs: 500,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  // ----------------------------------------------------------
  // Gelen arama (Cevapla / Reddet düğmeleri, 40 sn sonra kendiliğinden kapanır)
  // ----------------------------------------------------------
  Future<void> showIncomingCall({
    required String callId,
    required String fromName,
    required bool video,
  }) {
    return _plugin.show(
      idFor(callId),
      video ? 'Görüntülü arama' : 'Sesli arama',
      '$fromName arıyor',
      NotificationDetails(
        android: AndroidNotificationDetails(
          callsChannelId,
          'Gelen aramalar',
          channelDescription: 'Gelen sesli ve görüntülü aramalar',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          icon: '@mipmap/ic_launcher',
          color: _brand,
          ongoing: true,
          autoCancel: false,
          timeoutAfter: 40000,
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(
              actionAccept,
              'Cevapla',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              actionDecline,
              'Reddet',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          categoryIdentifier: 'incomingCall',
        ),
      ),
      payload: callId,
    );
  }

  // ----------------------------------------------------------
  // Cevapsız arama
  // ----------------------------------------------------------
  Future<void> showMissedCall({
    required String callId,
    required String fromName,
    required bool video,
  }) {
    return _plugin.show(
      idFor('missed-$callId'),
      'Cevapsız arama',
      '$fromName ${video ? 'görüntülü' : 'sesli'} aradı',
      NotificationDetails(
        android: AndroidNotificationDetails(
          missedChannelId,
          'Cevapsız aramalar',
          channelDescription: 'Cevaplanmayan aramalar',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
          color: _brand,
          autoCancel: true,
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      payload: callId,
    );
  }

  // ----------------------------------------------------------
  // Yardımcılar
  // ----------------------------------------------------------
  Future<void> cancelCall(String callId) => _plugin.cancel(idFor(callId));

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) {
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          messagesChannelId,
          'Mesaj bildirimleri',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<void> cancel(int id) => _plugin.cancel(id);
}
