// ============================================================
// lib/services/ban_watcher.dart
// (.txt olarak verildi. Projeye eklerken adını ban_watcher.dart yapın.)
// Açık oturumda hesap banlanırsa uygulamayı anında kapatır.
// profiles tablosundaki kendi satırını dinler; banned=true olunca çıkış yapar.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'meet_service.dart'; // appNavigatorKey

class BanWatcher {
  BanWatcher._();

  static StreamSubscription<List<Map<String, dynamic>>>? _sub;
  static bool _handled = false;

  /// Oturum açıkken çağrılır.
  static void start(String uid) {
    stop();
    _handled = false;
    _sub = Supabase.instance.client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .listen(
          (rows) {
            if (rows.isEmpty || _handled) return;
            if (rows.first['banned'] == true) {
              _handled = true;
              _onBanned();
            }
          },
          onError: (_) {},
        );
  }

  /// Çıkışta çağrılır.
  static void stop() {
    _sub?.cancel();
    _sub = null;
  }

  static Future<void> _onBanned() async {
    stop();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    final ctx = appNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Hesap yasaklandı'),
        content: const Text('Hesabınız politikalar gereği yasaklandı.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}
