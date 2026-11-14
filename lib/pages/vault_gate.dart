// ============================================================
// lib/pages/vault_gate.dart
// (.txt olarak verildi. Projeye eklerken adını vault_gate.dart yapın.)
//
// Bulut kasa kapısı. Her ürünün kendi şifresi var (Pass ve Notebook ayrı).
//  - Doğrulama kaydı yoksa: "Kasa şifresi oluştur" (en az 8 karakter).
//  - Varsa: "Kilidi aç" (en az 6 karakter).
// ============================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/security.dart';
import '../core/theme.dart';
import '../services/cloud_vaults.dart';
import '../services/web_crypto.dart';

class VaultGate extends StatefulWidget {
  /// Bu ürünün bulut kasası (PassCloud.instance veya NotebookCloud.instance)
  final CloudVault vault;
  final String lockedTitle;
  final String lockedHint;
  final String logoAsset;
  final WidgetBuilder builder;

  const VaultGate({
    super.key,
    required this.vault,
    required this.lockedTitle,
    required this.lockedHint,
    required this.logoAsset,
    required this.builder,
  });

  @override
  State<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<VaultGate> {
  /// null: kontrol ediliyor, true: doğrulama var, false: kurulmamış
  bool? _hasVerifier;
  String? _loadError;

  CloudVault get _vault => widget.vault;

  @override
  void initState() {
    super.initState();
    _vault.addListener(_onChanged);
    _check();
  }

  @override
  void didUpdateWidget(covariant VaultGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vault != widget.vault) {
      oldWidget.vault.removeListener(_onChanged);
      widget.vault.addListener(_onChanged);
      _check();
    }
  }

  @override
  void dispose() {
    _vault.removeListener(_onChanged);
    // Sayfadan çıkınca bu kasayı kilitle
    _vault.lock();
    super.dispose();
  }

  Future<void> _check() async {
    if (_loadError != null) setState(() => _loadError = null);
    try {
      final has = await _vault.hasVerifier();
      if (mounted) setState(() => _hasVerifier = has);
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = 'Bağlantı kurulamadı. İnternetini kontrol et.');
      }
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_vault.isUnlocked) return widget.builder(context);

    if (_loadError != null) {
      final c = context.appColors;
      return Scaffold(
        backgroundColor: c.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textSecondary)),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _check, child: const Text('Tekrar dene')),
              ],
            ),
          ),
        ),
      );
    }

    final has = _hasVerifier;
    if (has == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return _LockView(
      vault: _vault,
      hasVerifier: has,
      title: widget.lockedTitle,
      hint: widget.lockedHint,
      logoAsset: widget.logoAsset,
      onVerifierChanged: (v) {
        if (mounted) setState(() => _hasVerifier = v);
      },
    );
  }
}

// ============================================================
// KİLİT GÖRÜNÜMÜ
// ============================================================
class _LockView extends StatefulWidget {
  final CloudVault vault;
  final bool hasVerifier;
  final String title;
  final String hint;
  final String logoAsset;
  final ValueChanged<bool> onVerifierChanged;

  const _LockView({
    required this.vault,
    required this.hasVerifier,
    required this.title,
    required this.hint,
    required this.logoAsset,
    required this.onVerifierChanged,
  });

  @override
  State<_LockView> createState() => _LockViewState();
}

class _LockViewState extends State<_LockView> {
  final _secret = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

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

    final setup = !widget.hasVerifier;
    if (setup && _confirm.text != text) {
      setState(() => _error = 'Şifreler eşleşmiyor');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (setup) {
        await widget.vault.setup(text);
      } else {
        await widget.vault.unlock(text);
      }
      // Başarılı: CloudVault bildirir, VaultGate içeriği gösterir
    } on SecurityException catch (e) {
      if (!mounted) return;
      final msg = e.message;
      if (msg.contains('zaten') || msg.contains('oluşturulmamış')) {
        // Durum değişmiş: ekranı doğru moda getir
        widget.onVerifierChanged(!msg.contains('oluşturulmamış'));
      }
      setState(() => _error = msg);
    } catch (e) {
      if (mounted) setState(() => _error = 'Bağlantı hatası. Tekrar dene.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    CloudVaults.lockAll();
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final setup = !widget.hasVerifier;

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
                    setup ? 'Şifre oluştur' : widget.title,
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
                        ? 'Bu şifre yalnızca bu bölüm için. En az 8 karakter. Unutulursa veriler kurtarılamaz.'
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
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Şifre',
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
                          : Text(setup ? 'Oluştur ve aç' : 'Kilidi aç'),
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
