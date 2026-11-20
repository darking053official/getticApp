// lib/services/app_lock.dart
// Uygulama kilidi: uygulama 30 saniyeden uzun arka planda kaldıysa PIN sorulur.
// PIN, PBKDF2 (tuzlu) ile saklanır. Parmak izi bu sürümde yok.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import 'web_crypto.dart';

class AppLock {
  AppLock._();
  static final AppLock instance = AppLock._();

  static const String _kEnabled = 'app_lock_enabled_v1';
  static const String _kHash = 'app_lock_hash_v1';
  static const String _kSalt = 'app_lock_salt_v1';
  static const int _iterations = 200000;
  static const Duration _grace = Duration(seconds: 30);

  bool enabled = false;
  bool _showing = false;
  DateTime? _pausedAt;

  /// Açılışta bir kez çağrılır.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_kEnabled) ?? false;
  }

  Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt = base64.encode(
        Uint8List.fromList(List<int>.generate(16, (_) => rnd.nextInt(256))));
    final key = await WebCrypto.deriveKey(pin, salt, _iterations);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSalt, salt);
    await prefs.setString(_kHash, base64.encode(key));
    await prefs.setBool(_kEnabled, true);
    enabled = true;
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_kSalt);
    final hash = prefs.getString(_kHash);
    if (salt == null || hash == null) return false;
    final key = await WebCrypto.deriveKey(pin, salt, _iterations);
    return base64.encode(key) == hash;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHash);
    await prefs.remove(_kSalt);
    await prefs.setBool(_kEnabled, false);
    enabled = false;
  }

  /// Uygulama arka plana gittiğinde çağrılır.
  void markPaused() {
    _pausedAt = DateTime.now();
  }

  /// Uygulama ön plana geldiğinde çağrılır. Süre dolduysa kilit ekranını açar.
  Future<void> onResume(BuildContext context) async {
    if (!enabled || _showing) return;
    final p = _pausedAt;
    if (p == null || DateTime.now().difference(p) < _grace) return;
    _showing = true;
    try {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const AppLockScreen(),
        ),
      );
    } finally {
      _showing = false;
    }
  }
}

// ============================================================
// KİLİT EKRANI
// ============================================================
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p = _pin.text.trim();
    if (p.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await AppLock.instance.verifyPin(p);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
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
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 56, color: c.primary),
                  const SizedBox(height: 16),
                  Text('Uygulama kilitli',
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _pin,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 8,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textPrimary, fontSize: 22),
                    decoration: const InputDecoration(labelText: 'PIN'),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: TextStyle(color: c.danger, fontSize: 13)),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Aç'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
