// ============================================================
// lib/services/cloud_vaults.dart
// (.txt olarak verildi. Projeye eklerken adını cloud_vaults.dart yapın.)
// Tüm bulut kasalarını tek seferde kilitler (otomatik kilit, çıkış).
// ============================================================

import 'cloud_notebook.dart';
import 'cloud_pass.dart';

class CloudVaults {
  CloudVaults._();

  static void lockAll() {
    PassCloud.instance.lock();
    NotebookCloud.instance.lock();
  }
}
