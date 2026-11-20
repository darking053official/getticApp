// lib/services/secure_screen.dart
// Ekran görüntüsü ve kayıt engelleme. Android'de FLAG_SECURE ile çalışır.
// Diğer platformlarda sessizce hiçbir şey yapmaz.

import 'package:flutter/services.dart';

class SecureScreen {
  SecureScreen._();

  static const MethodChannel _channel = MethodChannel('gettic/secure');

  /// Hassas bir ekran açıldığında true, kapandığında false ver.
  static Future<void> set(bool secure) async {
    try {
      await _channel.invokeMethod('setSecure', {'on': secure});
    } catch (_) {
      // Desteklenmeyen platform: sessizce geç
    }
  }
}
