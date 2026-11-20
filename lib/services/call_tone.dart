// ============================================================
// lib/services/call_tone.dart
// (.txt olarak verildi. Projeye eklerken adını call_tone.dart yapın.)
// Arama sesleri (assets/): ringback.ogg = arayan tarafın "çalıyor" sesi,
// ringtone.ogg = gelen arama zil sesi.
//
// Düzeltme: Önceden loop() içinde play() beklendiği için fonksiyon hiç dönmüyordu,
// oynatıcı geç atanıyor ve yeni çağrılarda eski ses durdurulmadan üst üste çalıyordu.
// Şimdi: tek bir aktif ses vardır, yeni ses başlamadan öncekisi kapanır.
// ============================================================

import 'package:just_audio/just_audio.dart';

class CallTone {
  CallTone._();

  static const String ringback = 'assets/ringback.ogg';
  static const String ringtone = 'assets/ringtone.ogg';

  static AudioPlayer? _active;
  static int _generation = 0;

  /// Sesi döngüde başlatır. Önceki ses varsa önce onu kapatır.
  static Future<AudioPlayer?> loop(String asset) async {
    final my = ++_generation;
    await _disposeActive();
    try {
      final player = AudioPlayer();
      await player.setAsset(asset);
      await player.setLoopMode(LoopMode.all);
      // Bu arada başka bir ses ya da durdurma isteği geldiyse bu sesi açma
      if (my != _generation) {
        await player.dispose();
        return null;
      }
      _active = player;
      // play() döngü boyunca bitmez; beklenmemeli
      player.play();
      return player;
    } catch (_) {
      return null;
    }
  }

  /// Sesi kapatır. Bekleyen bir başlatma varsa onu da iptal eder.
  static Future<void> stop(AudioPlayer? player) async {
    _generation++;
    final p = player ?? _active;
    if (identical(p, _active)) _active = null;
    if (p == null) return;
    try {
      await p.stop();
      await p.dispose();
    } catch (_) {}
  }

  static Future<void> _disposeActive() async {
    final p = _active;
    _active = null;
    if (p == null) return;
    try {
      await p.stop();
      await p.dispose();
    } catch (_) {}
  }
}
