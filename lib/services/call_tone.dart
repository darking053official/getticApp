// ============================================================
// lib/services/call_tone.dart
// (.txt olarak verildi. Projeye eklerken adını call_tone.dart yapın.)
// Arama sesleri (assets/): ringback.ogg = arayan tarafın "çalıyor" sesi,
// ringtone.ogg = gelen arama zil sesi. İkisi de döngüde çalar.
// ============================================================

import 'package:just_audio/just_audio.dart';

class CallTone {
  CallTone._();

  static const String ringback = 'assets/ringback.ogg';
  static const String ringtone = 'assets/ringtone.ogg';

  /// Sesi döngüde başlatır. Dönen oynatıcı durdurulunca [stop] ile kapatılmalı.
  static Future<AudioPlayer?> loop(String asset) async {
    try {
      final player = AudioPlayer();
      await player.setAsset(asset);
      await player.setLoopMode(LoopMode.all);
      await player.play();
      return player;
    } catch (_) {
      return null;
    }
  }

  static Future<void> stop(AudioPlayer? player) async {
    if (player == null) return;
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {}
  }
}
