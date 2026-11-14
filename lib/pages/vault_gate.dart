// ============================================================
// lib/pages/vault_gate.dart
// (.txt olarak verildi. Projeye eklerken adını vault_gate.dart yapın.)
//
// Kasa durumu her seferinde kontrol edilir:
//  - Kasa hiç kurulmadıysa: "Kasa şifresi oluştur" ekranı.
//  - Kuruluysa: "Kilidi aç" ekranı.
// Durum değişirse (ör. başka bir bölümde kasa kurulduysa) ekran otomatik düzelir.
// ============================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/security.dart';
import '../core/theme.dart';

class VaultGate extends StatefulWidget {
  /// Kilit ekranındaki başlık (kasa kuruluyken)
  final String lockedTitle;
  /// Kilit ekranındaki açıklama (kasa kuruluyken)
  final String lockedHint;
  /// Logo (assets/ altında)
  final String logoAsset;
  /// Kasa açılınca gösterilecek içerik
  final WidgetBuilder builder;

  const VaultGate({
    super.key,
    required this.lockedTitle,
    required this.lockedHint,
    required this.logoAsset,
    required this.builder,
  });

  @override
  State<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<VaultGate> {
  final SecureVault _vault = SecureVault.instance;

  /// null: henüz kontrol edilmedi. true: kasa kurulu. false: kurulmamış.
  bool? _isSetUp;

  @override
  void initState() {
    super.initState();
    _vault.addListener(_onVaultChanged);
    _refreshSetupState();
  }

  @override
  void dispose() {
    _vault.removeListener(_onVaultChanged);
    // Sayfadan çıkınca kasayı kilitle (otomatik kilit süresi ayarlardan yönetilir)
    _vault.lock();
    super.dispose();
  }

  /// Kasanın kurulu olup olmadığını depodan yeniden okur.
  Future<void> _refreshSetupState() async {
    final setUp = await _vault.isSetUp;
    if (mounted) setState(() => _isSetUp = setUp);
  }

  void _onVaultChanged() {
    if (!mounted) return;
    if (_vault.isUnlocked) {
      setState(() {});
    } else {
      // Kilitlendiğinde kurulum durumunu tazele
      _refreshSetupState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final setUp = _isSetUp;

    if (setUp == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_vault.isUnlocked) {
      return widget.builder(context);
    }

    return _LockView(
      isSetUp: setUp,
      title: widget.lockedTitle,
      hint: widget.lockedHint,
      logoAsset: widget.logoAsset,
      onSetupStateChanged: (value) {
        if (mounted) setState(() => _isSetUp = value);
      },
    );
  }
}

// ============================================================
// KİLİT GÖRÜNÜMÜ
// ============================================================
class _LockView extends StatefulWidget {
  final bool isSetUp;
  final String title;
  final String hint;
  final String logoAsset;
  final ValueChanged<bool> onSetupStateChanged;

  const _LockView({
    required this.isSetUp,
    required this.title,
    required this.hint,
    required this.logoAsset,
    required this.onSetupStateChanged,
  });

  @override
  State<_LockView> createState() => _LockViewState();
}

class _LockViewState extends State<_LockView> {
  final _secret = TextEditingController();
  final _confirm = TextEditingController();
  final SecureVault _vault = SecureVault.instance;
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  PasswordReport _report = PasswordReport.evaluate('');

  @override
  void dispose() {
    _secret.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _secret.text;
    if (text.isEmpty) {
      setState(() => _error = 'Şifre gerekli');
      return;
    }

    final setup = !widget.isSetUp;
    if (setup) {
      if (!_report.isAcceptable) {
        setState(() => _error = 'Daha güçlü bir kasa şifresi seç');
        return;
      }
      if (_confirm.text != text) {
        setState(() => _error = 'Şifreler eşleşmiyor');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (setup) {
        await _vault.setUp(text);
        // Başarılı: kasa açık, VaultGate içeriği gösterir
      } else {
        await _vault.unlock(text);
      }
    } on SecurityException catch (e) {
      if (!mounted) return;
      final msg = e.message;

      // Durum bayatsa (kasa zaten kurulmuş ya da hiç kurulmamış) düzelt
      if (msg.contains('zaten kurulmuş')) {
        widget.onSetupStateChanged(true);
        setState(() => _error = 'Kasa zaten kurulu. Şifreni girerek aç.');
      } else if (msg.contains('kurulmamış')) {
        widget.onSetupStateChanged(false);
        setState(() => _error = 'Kasa henüz kurulmamış. Şifre oluştur.');
      } else {
        setState(() => _error = msg);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Beklenmeyen bir hata oluştu');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final setup = !widget.isSetUp;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: c.border),
                      ),
                      child: Image.asset(
                        widget.logoAsset,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.lock_outline, color: c.primary, size: 40),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    setup ? 'Kasa şifreni oluştur' : widget.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    setup
                        ? 'Bu şifre Notebook ve Parola Kasası için ortaktır. Unutulursa veriler kurtarılamaz.'
                        : widget.hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _secret,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    onChanged: setup
                        ? (v) => setState(
                            () => _report = PasswordReport.evaluate(v))
                        : null,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: setup ? 'Kasa şifresi' : 'Kasa şifresi',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (setup) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirm,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        hintText: 'Şifreyi tekrar gir',
                        prefixIcon: Icon(Icons.key_outlined),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    _StrengthBar(report: _report),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.danger, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(setup ? 'Kasayı oluştur' : 'Kilidi aç'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _signOut,
                      child: const Text('Çıkış yap'),
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

class _StrengthBar extends StatelessWidget {
  final PasswordReport report;
  const _StrengthBar({required this.report});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final color = switch (report.strength) {
      PasswordStrength.veryWeak || PasswordStrength.weak => c.danger,
      PasswordStrength.fair => Colors.amber.shade700,
      PasswordStrength.strong || PasswordStrength.veryStrong => c.online,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(5, (i) {
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                decoration: BoxDecoration(
                  color: i <= report.strength.index ? color : c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text('Şifre gücü: ${report.label}',
            style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }
}
