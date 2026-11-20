// ============================================================
// lib/services/desktop_notifier.dart
// (.txt olarak verildi. Projeye eklerken adını desktop_notifier.dart yapın.)
// Masaüstü (Windows, macOS, Linux) yerel bildirimleri.
// Uygulama açıkken çalışır. Uygulama kapalıyken bildirim gelmez (masaüstünde push yok).
// Mobilde hiçbir şey yapmaz.
// Gerekli paket: local_notifier
// ============================================================

import 'dart:io';

import 'package:local_notifier/local_notifier.dart';

class DesktopNotifier {
  DesktopNotifier._();

  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<void> init() async {
    if (!isDesktop) return;
    try {
      await localNotifier.setup(
        appName: 'Gettic',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    } catch (_) {
      // Kurulum başarısızsa bildirimler sessizce kapalı kalır
    }
  }

  static Future<void> show({required String title, required String body}) async {
    if (!isDesktop) return;
    try {
      LocalNotification(title: title, body: body).show();
    } catch (_) {}
  }
}
