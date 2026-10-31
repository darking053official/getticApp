import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../core/utils.dart';
import '../core/security.dart';
import '../services/supabase_service.dart';

const String _kRememberEmail = 'auth_remember_email';

// ============================================================
// GİRİŞ DENEME SINIRI (arayüz seviyesi)
// Hatalı girişlerde bekleme süresi uygular. E-posta, SHA-256 ile
// özetlenerek saklanır; düz metin e-posta tutulmaz.
// Not: Sunucu tarafında zaten hız sınırı vardır; bu yalnızca ek bir katmandır.
// ============================================================
class _LoginThrottle {
  static const int _freeAttempts = 5;

  static String _key(String email) {
    final hash = Crypto.sha256HexOfString(email.trim().toLowerCase());
    return 'auth_fail_${hash.substring(0, 24)}';
  }

  static Future<Duration?> remaining(String email) async {
    try {
      final p = await SharedPreferences.getInstance();
      final until = p.getInt('${_key(email)}_until');
      if (until == null) return null;
      final diff = until - DateTime.now().millisecondsSinceEpoch;
      return diff > 0 ? Duration(milliseconds: diff) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> registerFailure(String email) async {
    try {
      final p = await SharedPreferences.getInstance();
      final k = _key(email);
      final n = (p.getInt('${k}_n') ?? 0) + 1;
      await p.setInt('${k}_n', n);
      if (n >= _freeAttempts) {
        // 15 sn, 30 sn, 60 sn ... en fazla 10 dk
        final int exp = (n - _freeAttempts).clamp(0, 5).toInt();
        final int secs = (15 * (1 << exp)).clamp(15, 600).toInt();
        await p.setInt(
            '${k}_until', DateTime.now().millisecondsSinceEpoch + secs * 1000);
      }
    } catch (_) {}
  }

  static Future<void> clear(String email) async {
    try {
      final p = await SharedPreferences.getInstance();
      final k = _key(email);
      await p.remove('${k}_n');
      await p.remove('${k}_until');
    } catch (_) {}
  }
}

// ============================================================
// E-POSTA DOĞRULAMA DİYALOĞU (tekrar gönderme + bekleme süresi)
// ============================================================
class _VerifyEmailDialog extends StatefulWidget {
  final String email;
  const _VerifyEmailDialog({required this.email});

  @override
  State<_VerifyEmailDialog> createState() => _VerifyEmailDialogState();
}

class _VerifyEmailDialogState extends State<_VerifyEmailDialog> {
  Timer? _timer;
  int _cooldown = 0;
  bool _sending = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _sending) return;
    setState(() {
      _sending = true;
      _status = null;
    });
    try {
      await Supabase.instance.client.auth
          .resend(type: OtpType.signup, email: widget.email);
      if (!mounted) return;
      setState(() {
        _status = 'Doğrulama e-postası tekrar gönderildi';
        _statusIsError = false;
      });
      _startCooldown(60);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = e.message.toLowerCase().contains('rate')
            ? 'Çok sık istek gönderdin, biraz bekle'
            : 'Gönderilemedi: ${InputGuard.redact(e.message)}';
        _statusIsError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Gönderilemedi: ${InputGuard.redact(e.toString())}';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return AlertDialog(
      backgroundColor: c.surface,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.mark_email_read_outlined,
                color: c.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('E-postanı Doğrula',
                style: TextStyle(color: c.textPrimary, fontSize: 18)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kayıt başarılı! Giriş yapabilmen için önce e-postana gelen doğrulama bağlantısına tıklaman gerekiyor.',
            style: TextStyle(color: c.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              widget.email,
              style: TextStyle(
                color: c.primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Spam klasörünü de kontrol etmeyi unutma 📬',
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(
              _status!,
              style: TextStyle(
                color: _statusIsError ? c.danger : c.online,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: (_cooldown > 0 || _sending) ? null : _resend,
          child: _sending
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: c.primary),
                )
              : Text(_cooldown > 0
                  ? 'Tekrar gönder ($_cooldown)'
                  : 'Tekrar gönder'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Anladım'),
        ),
      ],
    );
  }
}

// ============================================================
// GİRİŞ / KAYIT SAYFASI
// ============================================================
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _service = SupabaseService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _rememberMe = true;
  bool _usernameAvailable = true;
  bool _checkingUsername = false;
  String? _error;
  String? _usernameError;

  // Şifre gücü (security.dart)
  PasswordReport _report = PasswordReport.evaluate('');

  // Giriş deneme sınırı geri sayımı
  int _lockSeconds = 0;
  Timer? _lockTimer;

  // Kullanıcı adı kontrolü (gecikmeli + yarış koşullarına karşı)
  Timer? _usernameDebounce;
  int _usernameRequestId = 0;

  // Sosyal yükleniyor durumları
  bool _googleLoading = false;
  bool _githubLoading = false;

  static final RegExp _usernameChars =
      RegExp(r'^[\p{L}0-9_.\-]+$', unicode: true);

  AppColors get _c => context.appColors;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _usernameDebounce?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  // ---------- Beni hatırla (yalnızca e-posta) ----------
  Future<void> _loadRemembered() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_kRememberEmail);
      if (saved != null && saved.isNotEmpty && mounted) {
        setState(() {
          _emailController.text = saved;
          _rememberMe = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _persistRemembered(String email) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await p.setString(_kRememberEmail, email);
      } else {
        await p.remove(_kRememberEmail);
      }
    } catch (_) {}
  }

  // ---------- Şifre gücü ----------
  List<String> get _passwordContext {
    final email = _emailController.text.trim();
    return [
      email,
      if (email.contains('@')) email.split('@').first,
      _usernameController.text.trim(),
    ];
  }

  void _onPasswordChanged(String v) {
    setState(() {
      _report = PasswordReport.evaluate(v, userInputs: _passwordContext);
    });
  }

  Color _strengthColor(PasswordStrength s) {
    switch (s) {
      case PasswordStrength.veryWeak:
        return _c.danger;
      case PasswordStrength.weak:
        return Colors.deepOrange;
      case PasswordStrength.fair:
        return Colors.amber.shade700;
      case PasswordStrength.strong:
        return Colors.lightGreen.shade600;
      case PasswordStrength.veryStrong:
        return _c.online;
    }
  }

  // ---------- Kullanıcı adı ----------
  void _onUsernameChanged(String v) {
    _usernameDebounce?.cancel();
    final t = v.trim();
    if (t.length < 3) {
      _usernameRequestId++;
      setState(() {
        _usernameAvailable = true;
        _usernameError = null;
        _checkingUsername = false;
      });
      return;
    }
    setState(() => _checkingUsername = true);
    _usernameDebounce =
        Timer(const Duration(milliseconds: 450), () => _checkUsername(t));
  }

  Future<void> _checkUsername(String username) async {
    final id = ++_usernameRequestId;
    try {
      final users = await _service.searchUsers(username);
      final exists = users.any(
        (p) => p.username.toLowerCase() == username.toLowerCase(),
      );
      if (!mounted || id != _usernameRequestId) return;
      setState(() {
        _usernameAvailable = !exists;
        _usernameError = exists ? 'Bu kullanıcı adı zaten alınmış' : null;
        _checkingUsername = false;
      });
    } catch (_) {
      if (!mounted || id != _usernameRequestId) return;
      setState(() {
        _usernameAvailable = true;
        _checkingUsername = false;
      });
    }
  }

  // ---------- Deneme sınırı geri sayımı ----------
  void _startLockCountdown(Duration d) {
    _lockTimer?.cancel();
    setState(() {
      _lockSeconds = (d.inMilliseconds / 1000).ceil();
      _error = 'Çok fazla hatalı deneme. Biraz bekleyip tekrar dene.';
    });
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _lockSeconds--);
      if (_lockSeconds <= 0) {
        t.cancel();
        setState(() {
          _lockSeconds = 0;
          _error = null;
        });
      }
    });
  }

  // ---------- Gönder ----------
  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_lockSeconds > 0 || _isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();

    // Kayıt olurken kullanıcı adı müsait değilse engelle
    if (!_isLogin && !_usernameAvailable) {
      setState(() => _error = 'Bu kullanıcı adı zaten alınmış');
      return;
    }

    if (_isLogin) {
      final rem = await _LoginThrottle.remaining(email);
      if (!mounted) return;
      if (rem != null) {
        _startLockCountdown(rem);
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_isLogin) {
        await _service.signInWithEmail(email, _passwordController.text);
        await _LoginThrottle.clear(email);
        await _persistRemembered(email);
        TextInput.finishAutofillContext();
      } else {
        final response = await _service.signUpWithEmail(
          email,
          _passwordController.text,
          _usernameController.text.trim(),
        );

        if (response.user != null && response.session == null) {
          // Şifreleri bellekteki alanlardan temizle
          _passwordController.clear();
          _confirmController.clear();
          _report = PasswordReport.evaluate('');
          if (mounted) await _showEmailVerificationDialog(email);
        } else {
          TextInput.finishAutofillContext();
        }
      }
    } on AuthException catch (e) {
      if (_isLogin && e.message.toLowerCase().contains('invalid login')) {
        await _LoginThrottle.registerFailure(email);
        final rem = await _LoginThrottle.remaining(email);
        if (rem != null && mounted) {
          _startLockCountdown(rem);
          return;
        }
      }
      if (mounted) {
        setState(() => _error = _translateAuthError(e.message));
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = 'Beklenmeyen bir hata: ${InputGuard.redact(e.toString())}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _translateAuthError(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('invalid login')) return 'E-posta veya şifre hatalı';
    if (lower.contains('email not confirmed')) {
      return 'Önce e-postanı doğrulaman gerekiyor';
    }
    if (lower.contains('user already registered')) {
      return 'Bu e-posta zaten kayıtlı';
    }
    if (lower.contains('invalid email')) return 'Geçersiz e-posta adresi';
    if (lower.contains('password')) return 'Şifre en az 6 karakter olmalı';
    if (lower.contains('rate limit')) {
      return 'Çok fazla deneme yaptınız. Lütfen bekleyin.';
    }
    if (lower.contains('network')) return 'İnternet bağlantınızı kontrol edin';
    return InputGuard.redact(msg);
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      await _service.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = 'Google giriş başarısız: ${InputGuard.redact(e.toString())}');
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _signInWithGithub() async {
    setState(() {
      _githubLoading = true;
      _error = null;
    });
    try {
      await _service.signInWithGithub();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = 'GitHub giriş başarısız: ${InputGuard.redact(e.toString())}');
      }
    } finally {
      if (mounted) setState(() => _githubLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (!InputGuard.isValidEmail(email)) {
      _snack('Lütfen önce geçerli bir e-posta adresi girin', isError: true);
      return;
    }

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      _snack('Şifre sıfırlama bağlantısı e-postanıza gönderildi ✓');
    } catch (e) {
      _snack('Hata: ${InputGuard.redact(e.toString())}', isError: true);
    }
  }

  Future<void> _showEmailVerificationDialog(String email) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VerifyEmailDialog(email: email),
    );
    if (mounted) _setMode(true);
  }

  void _setMode(bool login) {
    if (_isLogin == login) return;
    setState(() {
      _isLogin = login;
      _error = null;
    });
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _c.danger : _c.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final c = _c;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          _buildBackground(c, isDark),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      _buildBrand(c),
                      const SizedBox(height: 28),
                      _buildCard(c, isDark),
                      const SizedBox(height: 24),
                      _buildSocialSection(c),
                      const SizedBox(height: 28),
                      _buildTerms(c),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Arka plan (yumuşak mor ışıltılar) ----------
  Widget _buildBackground(AppColors c, bool isDark) {
    Widget glow(Color color, double size, double opacity) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(opacity), color.withOpacity(0)],
          ),
        ),
      );
    }

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -140,
            left: -100,
            child: glow(c.primary, 380, isDark ? 0.30 : 0.16),
          ),
          Positioned(
            bottom: -160,
            right: -120,
            child: glow(const Color(0xFF4F46E5), 420, isDark ? 0.20 : 0.10),
          ),
        ],
      ),
    );
  }

  // ---------- Logo + başlık ----------
  Widget _buildBrand(AppColors c) {
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(
                color: c.primary.withOpacity(0.35),
                blurRadius: 28,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Image.asset(
            'assets/logo.png',
            errorBuilder: (_, __, ___) =>
                Icon(Icons.message_rounded, color: c.primary, size: 44),
          ),
        ),
        const SizedBox(height: 18),
        ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            colors: [c.textPrimary, c.primary],
          ).createShader(rect),
          child: const Text(
            'Gettic',
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -1.2,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Gizlilik odaklı mesajlaşma',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  // ---------- Form kartı ----------
  Widget _buildCard(AppColors c, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Column(
          children: [
            _buildModeSwitch(c),
            const SizedBox(height: 22),
            _buildCardHeader(c),
            const SizedBox(height: 18),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  // Kullanıcı adı (sadece kayıt)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: !_isLogin
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _usernameField(c),
                          )
                        : const SizedBox(width: double.infinity),
                  ),

                  _emailField(c),
                  const SizedBox(height: 12),
                  _passwordField(c),

                  // Şifre gücü + gereksinimler (sadece kayıt)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: (!_isLogin && _passwordController.text.isNotEmpty)
                        ? Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _strengthMeter(c),
                          )
                        : const SizedBox(width: double.infinity),
                  ),

                  // Şifre tekrar (sadece kayıt)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: !_isLogin
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _confirmField(c),
                          )
                        : const SizedBox(width: double.infinity),
                  ),

                  // Beni hatırla + şifremi unuttum
                  if (_isLogin) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () =>
                              setState(() => _rememberMe = !_rememberMe),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) =>
                                        setState(() => _rememberMe = v ?? true),
                                    activeColor: c.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('E-postamı hatırla',
                                    style: TextStyle(
                                        color: c.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _forgotPassword,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text('Şifremi unuttum',
                              style: TextStyle(color: c.primary, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],

                  // Hata mesajı
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _error == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            key: ValueKey(_error),
                            padding: const EdgeInsets.only(top: 12),
                            child: _errorBanner(c, _error!),
                          ),
                  ),

                  const SizedBox(height: 20),
                  _primaryButton(c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardHeader(AppColors c) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Align(
        key: ValueKey(_isLogin),
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isLogin ? 'Tekrar hoş geldin' : 'Hesap oluştur',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isLogin
                  ? 'Giriş yap ve sohbete devam et'
                  : 'Birkaç saniyede başla',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Giriş / Kayıt geçişi (kayan hap) ----------
  Widget _buildModeSwitch(AppColors c) {
    Widget label(String text, bool loginTab) {
      final selected = _isLogin == loginTab;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _setMode(loginTab),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: selected ? Colors.white : c.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
              ),
              child: Text(text),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: _isLogin ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      c.primary,
                      Color.lerp(c.primary, const Color(0xFF4F46E5), 0.5)!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: c.primary.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              label('Giriş Yap', true),
              label('Kayıt Ol', false),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- Alanlar ----------
  Widget _usernameField(AppColors c) {
    Widget? suffix;
    if (_checkingUsername) {
      suffix = Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
        ),
      );
    } else if (_usernameController.text.trim().length >= 3) {
      suffix = Icon(
        _usernameAvailable ? Icons.check_circle : Icons.cancel,
        color: _usernameAvailable ? c.online : c.danger,
        size: 20,
      );
    }

    return TextFormField(
      controller: _usernameController,
      style: TextStyle(color: c.textPrimary),
      textInputAction: TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
      maxLength: 24,
      autofillHints: const [AutofillHints.newUsername],
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      onChanged: _onUsernameChanged,
      decoration: InputDecoration(
        hintText: 'Kullanıcı adı',
        counterText: '',
        prefixIcon: Icon(Icons.person_outline, color: c.textSecondary),
        suffixIcon: suffix,
      ),
      validator: (v) {
        final t = (v ?? '').trim();
        if (t.isEmpty) return 'Kullanıcı adı boş olamaz';
        if (t.length < 3) return 'En az 3 karakter olmalı';
        if (!_usernameChars.hasMatch(t)) {
          return 'Sadece harf, rakam ve _ . - kullanabilirsin';
        }
        if (!_usernameAvailable) return _usernameError;
        return null;
      },
    );
  }

  Widget _emailField(AppColors c) {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: _isLogin
          ? const [AutofillHints.username, AutofillHints.email]
          : const [AutofillHints.email],
      style: TextStyle(color: c.textPrimary),
      onChanged: (_) {
        if (!_isLogin && _passwordController.text.isNotEmpty) {
          _onPasswordChanged(_passwordController.text);
        }
      },
      decoration: InputDecoration(
        hintText: 'E-posta adresi',
        prefixIcon: Icon(Icons.email_outlined, color: c.textSecondary),
      ),
      validator: AppUtils.validateEmail,
    );
  }

  Widget _passwordField(AppColors c) {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      textInputAction: _isLogin ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: _isLogin ? (_) => _submit() : null,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      autofillHints: _isLogin
          ? const [AutofillHints.password]
          : const [AutofillHints.newPassword],
      style: TextStyle(color: c.textPrimary),
      onChanged: !_isLogin ? _onPasswordChanged : null,
      decoration: InputDecoration(
        hintText: 'Şifre',
        prefixIcon: Icon(Icons.lock_outline, color: c.textSecondary),
        suffixIcon: IconButton(
          tooltip: _obscurePassword ? 'Şifreyi göster' : 'Şifreyi gizle',
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: c.textSecondary,
            size: 20,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (v) {
        final base = AppUtils.validatePassword(v);
        if (base != null) return base;
        if (!_isLogin) {
          final pw = v ?? '';
          if (pw.length < 8) return 'Şifre en az 8 karakter olmalı';
          final r = PasswordReport.evaluate(pw, userInputs: _passwordContext);
          if (!r.isAcceptable) return 'Daha güçlü bir şifre seç';
        }
        return null;
      },
    );
  }

  Widget _confirmField(AppColors c) {
    return TextFormField(
      controller: _confirmController,
      obscureText: _obscureConfirm,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _submit(),
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      autofillHints: const [AutofillHints.newPassword],
      style: TextStyle(color: c.textPrimary),
      decoration: InputDecoration(
        hintText: 'Şifre tekrar',
        prefixIcon: Icon(Icons.lock_reset_outlined, color: c.textSecondary),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirm
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: c.textSecondary,
            size: 20,
          ),
          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
      ),
      validator: (v) {
        if (_isLogin) return null;
        if ((v ?? '').isEmpty) return 'Şifreni tekrar gir';
        if (v != _passwordController.text) return 'Şifreler eşleşmiyor';
        return null;
      },
    );
  }

  // ---------- Şifre gücü göstergesi ----------
  Widget _strengthMeter(AppColors c) {
    final r = _report;
    final color = _strengthColor(r.strength);
    final pw = _passwordController.text;

    final reqs = <MapEntry<String, bool>>[
      MapEntry('8+ karakter', pw.length >= 8),
      MapEntry(
        'Büyük harf',
        RegExp(r'[A-ZÇĞİÖŞÜ]').hasMatch(pw),
      ),
      MapEntry('Rakam', RegExp(r'[0-9]').hasMatch(pw)),
      MapEntry(
        'Özel karakter',
        RegExp(r'[^A-Za-z0-9\u0080-\uFFFF]').hasMatch(pw),
      ),
    ];

    String? warning;
    for (final h in r.hints) {
      if (h.contains('yaygın') || h.contains('dizi') || h.contains('kullanıcı')) {
        warning = h;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(5, (i) {
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 5,
                margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                decoration: BoxDecoration(
                  color: i <= r.strength.index ? color : c.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.shield_outlined, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              'Şifre gücü: ${r.label}',
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final req in reqs)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    req.value
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 14,
                    color: req.value ? c.online : c.textHint,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    req.key,
                    style: TextStyle(
                      color: req.value ? c.textPrimary : c.textHint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (warning != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.amber.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  warning,
                  style: TextStyle(color: Colors.amber.shade700, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _errorBanner(AppColors c, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.danger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.danger.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: c.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: c.danger, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Ana buton ----------
  Widget _primaryButton(AppColors c) {
    final locked = _lockSeconds > 0;
    final enabled = !_isLoading && !locked;

    String text;
    if (locked) {
      text = 'Tekrar dene ($_lockSeconds sn)';
    } else {
      text = _isLogin ? 'Giriş Yap' : 'Hesap Oluştur';
    }

    return Opacity(
      opacity: enabled || _isLoading ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                c.primary,
                Color.lerp(c.primary, const Color(0xFF4F46E5), 0.55)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: c.primary.withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? _submit : null,
            child: SizedBox(
              height: 54,
              width: double.infinity,
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (locked) ...[
                            const Icon(Icons.lock_clock,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Sosyal giriş ----------
  Widget _buildSocialSection(AppColors c) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: c.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('veya şununla devam et',
                  style: TextStyle(color: c.textHint, fontSize: 12)),
            ),
            Expanded(child: Divider(color: c.border)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _socialButton(
                c: c,
                onTap: _isLoading || _googleLoading ? null : _signInWithGoogle,
                assetPath: 'assets/google.png',
                label: 'Google',
                loading: _googleLoading,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _socialButton(
                c: c,
                onTap: _isLoading || _githubLoading ? null : _signInWithGithub,
                assetPath: 'assets/github.png',
                label: 'GitHub',
                loading: _githubLoading,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _socialButton({
    required AppColors c,
    required VoidCallback? onTap,
    required String assetPath,
    required String label,
    required bool loading,
  }) {
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          child: loading
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.primary),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      assetPath,
                      width: 22,
                      height: 22,
                      errorBuilder: (_, __, ___) => Icon(
                        label == 'Google' ? Icons.g_mobiledata : Icons.code,
                        color: c.textPrimary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ---------- Alt yazı ----------
  Widget _buildTerms(AppColors c) {
    return Text.rich(
      TextSpan(
        text: 'Devam ederek ',
        style: TextStyle(color: c.textSecondary, fontSize: 11),
        children: [
          TextSpan(
            text: 'Kullanım Şartları',
            style: TextStyle(color: c.primary, fontWeight: FontWeight.w600),
          ),
          const TextSpan(text: ' ve '),
          TextSpan(
            text: 'Gizlilik Politikası',
            style: TextStyle(color: c.primary, fontWeight: FontWeight.w600),
          ),
          const TextSpan(text: '\'nı kabul etmiş olursun.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
