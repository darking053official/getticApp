import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native ekran paylaşımı köprüsü.
/// Android'de ScreenShareService'i başlatır/durdurur.
/// Diğer platformlarda no-op.
class ScreenShareNative {
  static const _channel = MethodChannel('gettic/screen_share');

  static Future<bool> start() async {
    if (!Platform.isAndroid) {
      debugPrint('ScreenShareNative.start: sadece Android destekliyor');
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('start');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('ScreenShareNative.start hata: $e');
      return false;
    }
  }

  static Future<bool> stop() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('stop');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('ScreenShareNative.stop hata: $e');
      return false;
    }
  }
}
