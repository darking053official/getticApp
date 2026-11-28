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
  bool _showPass = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Şifre güç göstergesi için yazıldıkça yeniden çiz
    _passCtl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _codeCtl.dispose();
    _passCtl.dispose();
    _pass2Ctl.dispose();
    super.dispose();
  }

  /// Şifre gücü: 0 (çok zayıf) ile 4 (güçlü) arası
  int _strength(String p) {
    var s = 0;
    if (p.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'[0-9]').hasMatch(p)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
    return s;
  }

  Future<void> _submit() async {
    final code = _codeCtl.text.trim();
    final p1 = _passCtl.text;
    final p2 = _pass2Ctl.text;

    if (!RegExp(r'^\d{6,8}$').hasMatch(code)) {
      setState(() => _error = 'E-postadaki kodu (6-8 rakam) girin');
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
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: p1));
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

  Widget _strengthBar(AppColors c) {
    final s = _strength(_passCtl.text);
    const labels = ['Çok zayıf', 'Zayıf', 'Orta', 'İyi', 'Güçlü'];
    final color = s <= 1 ? c.danger : (s == 2 ? Colors.orange : c.online);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: List.generate(
                4,
                (i) => Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: i < s ? color : c.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            labels[s],
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Şifre sıfırla'),
        backgroundColor: c.background,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: c.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mark_email_read_outlined,
                    color: c.primary, size: 34),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Kodu girin',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.email} adresine gönderilen 6-8 haneli kodu ve yeni şifrenizi girin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _codeCtl,
              keyboardType: TextInputType.number,
              maxLength: 8,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.textPrimary, fontSize: 22, letterSpacing: 6),
              decoration: const InputDecoration(
                labelText: 'Doğrulama kodu',
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passCtl,
              obscureText: !_showPass,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                labelText: 'Yeni şifre',
                suffixIcon: IconButton(
                  icon: Icon(_showPass
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
            if (_passCtl.text.isNotEmpty) _strengthBar(c),
            const SizedBox(height: 12),
            TextField(
              controller: _pass2Ctl,
              obscureText: !_showPass,
              style: TextStyle(color: c.textPrimary),
              decoration: const InputDecoration(labelText: 'Yeni şifre (tekrar)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.danger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: c.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: c.danger, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Şifreyi değiştir'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: Text('Vazgeç', style: TextStyle(color: c.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
