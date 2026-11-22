// ============================================================
// lib/pages/password_reset_page.dart
// (.txt olarak verildi. Projeye eklerken adını password_reset_page.dart yapın.)
// Uygulama içi şifre sıfırlama: e-postadaki 6 haneli kod + yeni şifre.
// Web sitesine yönlendirme yok.
// ============================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme.dart';

class PasswordResetPage extends StatefulWidget {
  final String email;
  const PasswordResetPage({super.key, required this.email});

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final _codeCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _pass2Ctl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeCtl.dispose();
    _passCtl.dispose();
    _pass2Ctl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtl.text.trim();
    final p1 = _passCtl.text;
    final p2 = _pass2Ctl.text;

    if (code.length < 6) {
      setState(() => _error = 'E-postadaki kodu girin');
      return;
    }
    if (p1.length < 6) {
      setState(() => _error = 'Yeni şifre en az 6 karakter olmalı');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'Şifreler eşleşmiyor');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Kodu doğrula (kullanıcı oturumu açılır), sonra şifreyi değiştir
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.recovery,
        email: widget.email,
        token: code,
      );
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: p1));
      // Şifre değişti: oturumu kapat, giriş ekranına dön
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Şifreniz değiştirildi. Yeni şifrenizle giriş yapın.'),
        behavior: SnackBarBehavior.floating,
      ));
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message.toLowerCase().contains('expired')
              ? 'Kodun süresi dolmuş. Yeniden kod isteyin.'
              : 'Kod hatalı veya süresi dolmuş.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Hata: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Şifre sıfırla'),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '${widget.email} adresine gönderilen 6 haneli kodu ve yeni şifrenizi girin.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _codeCtl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: 22, letterSpacing: 6),
            decoration: const InputDecoration(
              labelText: 'Doğrulama kodu',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtl,
            obscureText: true,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Yeni şifre'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass2Ctl,
            obscureText: true,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Yeni şifre (tekrar)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Şifreyi değiştir'),
          ),
        ],
      ),
    );
  }
}
