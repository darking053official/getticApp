// ============================================================
// lib/services/notification_privacy.dart
// Bildirimde içerik gizleme: açıksa bildirimlerde gönderen adı ve mesaj içeriği
// yerine "Yeni mesaj" gösterilir. Ayar profiles.hide_message_preview alanında tutulur.
// Sunucu (message-push) bu ayara göre bildirim metnini belirler.
// ============================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationPrivacy {
  NotificationPrivacy._();

  /// Oturum açıkken yüklenir, masaüstü bildirimleri bu değere bakar.
  static bool hidePreview = false;

  static Future<void> load() async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('hide_message_preview')
          .eq('id', me)
          .maybeSingle();
      hidePreview = row?['hide_message_preview'] == true;
    } catch (_) {}
  }

  static Future<void> set(bool value) async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return;
    await Supabase.instance.client
        .from('profiles')
        .update({'hide_message_preview': value})
        .eq('id', me);
    hidePreview = value;
  }
}

/// Ayarlar ekranına eklenecek anahtar.
class NotificationPrivacyTile extends StatefulWidget {
  const NotificationPrivacyTile({super.key});

  @override
  State<NotificationPrivacyTile> createState() =>
      _NotificationPrivacyTileState();
}

class _NotificationPrivacyTileState extends State<NotificationPrivacyTile> {
  bool _value = NotificationPrivacy.hidePreview;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    NotificationPrivacy.load().then((_) {
      if (mounted) setState(() => _value = NotificationPrivacy.hidePreview);
    });
  }

  Future<void> _change(bool v) async {
    setState(() {
      _busy = true;
      _value = v;
    });
    try {
      await NotificationPrivacy.set(v);
    } catch (e) {
      if (mounted) {
        setState(() => _value = !v);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.visibility_off_outlined, size: 22),
      title: const Text('Bildirimde içeriği gizle'),
      subtitle: const Text('Bildirimlerde gönderen ve mesaj yerine "Yeni mesaj" yazar'),
      value: _value,
      onChanged: _busy ? null : _change,
    );
  }
}
