// ============================================================
// lib/services/chat_lock_service.dart
// (.txt olarak verildi. Projeye eklerken adını chat_lock_service.dart yapın.)
//
// Sohbet kilidi: seçilen sohbetler PIN ile korunur.
//  - PIN: PBKDF2 (tuzlu) ile saklanır, düz metin yok. Bu cihaza özeldir.
//  - Kilitli sohbet, uygulama arka plana gidene kadar bir kez açılır.
//  - Kilit listesi bu cihazda tutulur (diğer cihazlarda kilitli görünmez).
// ============================================================

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import 'web_crypto.dart';

class ChatLock {
  ChatLock._();
  static final ChatLock instance = ChatLock._();

  static const String _kPinHash = 'chat_lock_pin_hash_v1';
  static const String _kPinSalt = 'chat_lock_pin_salt_v1';
  static const String _kLocked = 'chat_lock_ids_v1';
  static const int _iterations = 200000;

  /// Bu oturumda PIN ile açılmış sohbetler (uygulama arka plana gidince temizlenir).
  final Set<String> _sessionUnlocked = {};

  // ---------- Kilitli sohbet listesi ----------

  Future<Set<String>> lockedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_kLocked) ?? <String>[]).toSet();
  }

  Future<bool> isLocked(String convId) async =>
      (await lockedIds()).contains(convId);

  Future<void> setLocked(String convId, bool locked) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_kLocked) ?? <String>[]).toSet();
    if (locked) {
      ids.add(convId);
    } else {
      ids.remove(convId);
      _sessionUnlocked.remove(convId);
    }
    await prefs.setStringList(_kLocked, ids.toList());
  }

  // ---------- PIN ----------

  Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_kPinHash);
  }

  Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final saltBytes =
        Uint8List.fromList(List<int>.generate(16, (_) => rnd.nextInt(256)));
    final salt = base64.encode(saltBytes);
    final key = await WebCrypto.deriveKey(pin, salt, _iterations);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinSalt, salt);
    await prefs.setString(_kPinHash, base64.encode(key));
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_kPinSalt);
    final hash = prefs.getString(_kPinHash);
    if (salt == null || hash == null) return false;
    final key = await WebCrypto.deriveKey(pin, salt, _iterations);
    return base64.encode(key) == hash;
  }

  /// PIN'i ve tüm kilitleri kaldırır.
  Future<void> removePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPinHash);
    await prefs.remove(_kPinSalt);
    await prefs.remove(_kLocked);
    _sessionUnlocked.clear();
  }

  // ---------- Oturum ----------

  /// Uygulama arka plana gidince çağrılır: bir sonraki açılışta PIN yeniden sorulur.
  void lockSession() => _sessionUnlocked.clear();

  /// Sohbet kilitli değilse ya da bu oturumda açıldıysa true.
  /// Kilitliyse PIN sorar; doğruysa true döner.
  Future<bool> ensureUnlocked(BuildContext context, String convId) async {
    if (!await isLocked(convId)) return true;
    if (_sessionUnlocked.contains(convId)) return true;
    final ok = await askPin(context);
    if (ok) _sessionUnlocked.add(convId);
    return ok;
  }

  /// PIN sorar. Doğruysa true.
  Future<bool> askPin(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _PinDialog(
        title: 'PIN girin',
        createNew: false,
        onSubmit: verifyPin,
      ),
    );
    return ok == true;
  }

  /// Yeni PIN oluşturur (ilk kilit). Oluşturulduysa true.
  Future<bool> createPin(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _PinDialog(
        title: 'Sohbet kilidi için PIN oluşturun',
        createNew: true,
        onSubmit: (pin) async {
          await setPin(pin);
          return true;
        },
      ),
    );
    return ok == true;
  }
}

// ============================================================
// PIN DİYALOĞU
// ============================================================
class _PinDialog extends StatefulWidget {
  final String title;
  final bool createNew;
  final Future<bool> Function(String pin) onSubmit;

  const _PinDialog({
    required this.title,
    required this.createNew,
    required this.onSubmit,
  });

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _pin2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p = _pin.text.trim();
    if (p.length < 4) {
      setState(() => _error = 'En az 4 haneli PIN girin');
      return;
    }
    if (widget.createNew && p != _pin2.text.trim()) {
      setState(() => _error = 'PIN\'ler eşleşmiyor');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.onSubmit(p);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = 'PIN yanlış';
        _pin.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fmt = [FilteringTextInputFormatter.digitsOnly];

    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(widget.title, style: TextStyle(color: c.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: fmt,
            maxLength: 8,
            decoration: const InputDecoration(labelText: 'PIN'),
            onSubmitted: (_) => widget.createNew ? null : _submit(),
          ),
          if (widget.createNew)
            TextField(
              controller: _pin2,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: fmt,
              maxLength: 8,
              decoration: const InputDecoration(labelText: 'PIN (tekrar)'),
              onSubmitted: (_) => _submit(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!,
                  style: TextStyle(color: c.danger, fontSize: 13)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('İptal'),
        ),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Tamam', style: TextStyle(color: c.primary)),
        ),
      ],
    );
  }
}
