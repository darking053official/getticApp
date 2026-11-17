// ============================================================
// lib/services/meet_log.dart
// (.txt olarak verildi. Projeye eklerken adını meet_log.dart yapın.)
// Meet için ortak log tamponu. Servis (S) ve görüşme ekranı (P) buraya yazar,
// görüşme ekranındaki log panelinde ve "Kopyala" ile görünür.
// ============================================================

class MeetLog {
  MeetLog._();

  static const int maxLines = 400;
  static final List<String> _lines = [];

  static List<String> get lines => List.unmodifiable(_lines);

  static String get text => _lines.join('\n');

  static void add(String tag, String message) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    _lines.add(
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)} [$tag] $message');
    if (_lines.length > maxLines) _lines.removeAt(0);
  }

  static void clear() => _lines.clear();
}
