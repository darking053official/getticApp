// ============================================================
// lib/services/meet_log.dart
// (.txt olarak verildi. Projeye eklerken adını meet_log.dart yapın.)
// Ayrıntılı log: Ayarlar > Tanılama > "Ayrıntılı log" açıksa kaydedilir ve gösterilir.
// Kapalıyken hiçbir log tutulmaz.
// ============================================================

import '../core/app_settings.dart';

class MeetLog {
  MeetLog._();

  static const int maxLines = 400;
  static final List<String> _lines = [];

  /// Ayarlardaki "Ayrıntılı log" seçeneği
  static bool get enabled => AppSettings.instance.detailedLog;

  static List<String> get lines => List.unmodifiable(_lines);

  static String get text => _lines.join('\n');

  static void add(String tag, String message) {
    if (!enabled) return;
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    _lines.add(
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)} [$tag] $message');
    if (_lines.length > maxLines) _lines.removeAt(0);
  }

  static void clear() => _lines.clear();
}
