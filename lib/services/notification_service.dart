// ============================================================
// lib/services/notification_service.dart
// (.txt olarak verildi. Projeye eklerken adını notification_service.dart yapın.)
//
// Ayarlara bağlı bildirimler:
//  - Arama zil sesi / titreşimi (AppSettings.notifCallSound / notifCallVibrate)
//  - Mesaj sesi / titreşimi / önizleme (notifMessageSound / notifMessageVibrate / notifMessagePreview)
// Android kanal sesi sonradan değiştirilemez; bu yüzden ayar kombinasyonu başına
// ayrı bir kanal kullanılır (ör. gettic_call_s1v0).
// Zil sesi: android/app/src/main/res/raw/ringtone.ogg (CI bunu assets'ten kopyalar)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../core/app_settings.dart';
import 'meet_log.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String actionAccept = 'accept';
  static const String actionDecline = 'decline';

  static const Color _brand = Color(0xFF7c3aed);

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  void Function(NotificationResponse)? _onResponse;
  bool _ready = false;

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

    _ready = true;
    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  int idFor(String key) => key.hashCode & 0x7fffffff;

  /// Ayar kombinasyonuna göre kanal oluşturur (varsa dokunmaz).
  Future<String> _channel({
    required String base,
    required String name,
    required Importance importance,
    required bool sound,
    required bool vibrate,
    String? description,
  }) async {
    final id = '${base}_s${sound ? 1 : 0}v${vibrate ? 1 : 0}';
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(AndroidNotificationChannel(
      id,
      name,
      description: description,
      importance: importance,
      playSound: sound,
      sound: sound
          ? (base == 'gettic_calls'
              ? const RawResourceAndroidNotificationSound('ringtone')
              : base == 'gettic_messages'
                  ? const RawResourceAndroidNotificationSound('notification')
                  : null)
          : null,
      enableVibration: vibrate,
    ));
    return id;
  }

  // ----------------------------------------------------------
  // Mesaj
  // ----------------------------------------------------------
  Future<void> showMessage({
    required String key,
    required String title,
    required String body,
    String? payload,
  }) async {
    final s = AppSettings.instance;
    final channelId = await _channel(
      base: 'gettic_messages',
      name: 'Mesaj bildirimleri',
      importance: Importance.high,
      sound: s.notifMessageSound,
      vibrate: s.notifMessageVibrate,
      description: 'Yeni mesaj bildirimleri',
    );

    await _plugin.show(
      idFor(key),
      title,
      s.notifMessagePreview ? body : 'Yeni mesaj',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Mesaj bildirimleri',
          channelDescription: 'Yeni mesaj bildirimleri',
          importance: Importance.high,
          priority: Priority.high,
          playSound: s.notifMessageSound,
          enableVibration: s.notifMessageVibrate,
          icon: '@mipmap/ic_launcher',
          color: _brand,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: s.notifMessageSound),
      ),
      payload: payload,
    );
  }

  // ----------------------------------------------------------
  // Gelen arama (Cevapla / Reddet, 40 sn)
  // ----------------------------------------------------------
  Future<void> showIncomingCall({
    required String callId,
    required String fromName,
    required bool video,
  }) async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await android?.areNotificationsEnabled();
      MeetLog.add('N', 'gelen arama bildirimi: izin=$enabled from=$fromName');
      await _showIncomingCallInner(callId: callId, fromName: fromName, video: video);
      MeetLog.add('N', 'gelen arama bildirimi gönderildi');
    } catch (e) {
      MeetLog.add('N', 'gelen arama bildirimi HATA: $e');
    }
  }

  Future<void> _showIncomingCallInner({
    required String callId,
    required String fromName,
    required bool video,
  }) async {
    final s = AppSettings.instance;
    final channelId = await _channel(
      base: 'gettic_calls',
      name: 'Gelen aramalar',
      importance: Importance.max,
      sound: s.notifCallSound,
      vibrate: s.notifCallVibrate,
      description: 'Gelen sesli ve görüntülü aramalar',
    );

    await _plugin.show(
      idFor(callId),
      video ? 'Görüntülü arama' : 'Sesli arama',
      '$fromName arıyor',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Gelen aramalar',
          channelDescription: 'Gelen sesli ve görüntülü aramalar',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          playSound: s.notifCallSound,
          enableVibration: s.notifCallVibrate,
          icon: '@mipmap/ic_launcher',
          color: _brand,
          ongoing: true,
          autoCancel: false,
          timeoutAfter: 40000,
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(actionAccept, 'Cevapla', showsUserInterface: true),
            AndroidNotificationAction(actionDecline, 'Reddet',
                showsUserInterface: true, cancelNotification: true),
          ],
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      payload: callId,
    );
  }

  Future<void> showMissedCall({
    required String callId,
    required String fromName,
    required bool video,
  }) async {
    final channelId = await _channel(
      base: 'gettic_missed',
      name: 'Cevapsız aramalar',
      importance: Importance.defaultImportance,
      sound: true,
      vibrate: true,
    );
    await _plugin.show(
      idFor('missed-$callId'),
      'Cevapsız arama',
      '$fromName ${video ? 'görüntülü' : 'sesli'} aradı',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Cevapsız aramalar',
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
          'gettic_messages_s1v1',
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
