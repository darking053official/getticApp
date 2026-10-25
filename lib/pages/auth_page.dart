import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../core/utils.dart';
import '../services/supabase_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  final _service = SupabaseService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late TabController _tabController;
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _usernameAvailable = true;
  bool _checkingUsername = false;
  String? _error;
  String? _usernameError;

  // Şifre gücü
  double _passwordStrength = 0;
  String _passwordStrengthLabel = '';

  // Sosyal yükleniyor durumları
  bool _googleLoading = false;
  bool _githubLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _isLogin = _tabController.index == 0;
        _error = null;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  // Şifre gücü hesapla
  void _calculatePasswordStrength(String password) {
    double strength = 0;
    if (password.length >= 6) strength += 0.25;
    if (password.length >= 10) strength += 0.25;
    if (password.contains(RegExp(r'[A-Z]'))) strength += 0.15;
    if (password.contains(RegExp(r'[0-9]'))) strength += 0.15;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength += 0.2;

    setState(() {
      _passwordStrength = strength.clamp(0.0, 1.0);
      if (password.isEmpty) {
        _passwordStrengthLabel = '';
      } else if (strength < 0.4) {
        _passwordStrengthLabel = 'Zayıf';
      } else if (strength < 0.7) {
        _passwordStrengthLabel = 'Orta';
      } else {
        _passwordStrengthLabel = 'Güçlü';
      }
    });
  }

  // Kullanıcı adı müsait mi kontrol et
  Future<void> _checkUsername(String username) async {
    if (username.trim().length < 3) {
      setState(() {
        _usernameAvailable = true;
        _usernameError = null;
        _checkingUsername = false;
      });
      return;
    }

    setState(() => _checkingUsername = true);

    try {
      final users = await _service.searchUsers(username);
      final exists = users.any(
        (p) => p.username.toLowerCase() == username.trim().toLowerCase(),
      );

      if (mounted) {
        setState(() {
          _usernameAvailable = !exists;
          _usernameError = exists ? 'Bu kullanıcı adı zaten alınmış' : null;
          _checkingUsername = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _usernameAvailable = true;
          _checkingUsername = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    // Kayıt olurken kullanıcı adı müsait değilse engelle
    if (!_isLogin && !_usernameAvailable) {
      setState(() => _error = 'Bu kullanıcı adı zaten alınmış');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_isLogin) {
        await _service.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        final response = await _service.signUpWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
          _usernameController.text.trim(),
        );

        if (response.user != null && response.session == null) {
          // E-posta doğrulama gerekli
          if (mounted) {
            _showEmailVerificationDialog();
          }
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = _translateAuthError(e.message));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Beklenmeyen bir hata: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _translateAuthError(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('invalid login')) return 'E-posta veya şifre hatalı';
    if (lower.contains('user already registered')) return 'Bu e-posta zaten kayıtlı';
    if (lower.contains('invalid email')) return 'Geçersiz e-posta adresi';
    if (lower.contains('password')) return 'Şifre en az 6 karakter olmalı';
    if (lower.contains('rate limit')) return 'Çok fazla deneme yaptınız. Lütfen bekleyin.';
    if (lower.contains('network')) return 'İnternet bağlantınızı kontrol edin';
    return msg;
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      await _service.signInWithGoogle();
    } catch (e) {
      if (mounted) setState(() => _error = 'Google giriş başarısız: $e');
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
      if (mounted) setState(() => _error = 'GitHub giriş başarısız: $e');
    } finally {
      if (mounted) setState(() => _githubLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snack('Lütfen önce e-posta adresinizi girin', isError: true);
      return;
    }

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      _snack('Şifre sıfırlama bağlantısı e-postanıza gönderildi ✓');
    } catch (e) {
      _snack('Hata: $e', isError: true);
    }
  }

  void _showEmailVerificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Row(
          children: const [
            Icon(Icons.mark_email_read_outlined,
                color: AppTheme.primary, size: 28),
            SizedBox(width: 12),
            Text('E-postanı Doğrula',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Kayıt başarılı! Ancak giriş yapabilmen için önce e-postana gelen doğrulama bağlantısına tıklaman gerekiyor.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _emailController.text.trim(),
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Spam klasörünü de kontrol etmeyi unutma 📬',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _isLogin = true;
                _tabController.animateTo(0);
              });
            },
            child: const Text('Anladım', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Logo
                Image.asset('assets/logo.png', width: 90, height: 90,
                    errorBuilder: (_, __, ___) => Container(
                          width: 90, height: 90,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(Icons.message_rounded,
                              color: AppTheme.primary, size: 50),
                        )),
                const SizedBox(height: 16),
                const Text(
                  'Gettic',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Gizlilik odaklı mesajlaşma',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 32),

                // Sekmeler
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _tabButton('Giriş Yap', true)),
                      Expanded(child: _tabButton('Kayıt Ol', false)),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Form
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Kullanıcı adı (sadece kayıt)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        child: !_isLogin
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _usernameField(),
                              )
                            : const SizedBox.shrink(),
                      ),

                      // E-posta
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'E-posta adresi',
                          prefixIcon: Icon(Icons.email_outlined,
                              color: AppTheme.textSecondary),
                        ),
                        validator: AppUtils.validateEmail,
                      ),
                      const SizedBox(height: 12),

                      // Şifre
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        onChanged: !_isLogin
                            ? (v) => _calculatePasswordStrength(v)
                            : null,
                        decoration: InputDecoration(
                          hintText: 'Şifre',
                          prefixIcon: const Icon(Icons.lock_outline,
                              color: AppTheme.textSecondary),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppTheme.textSecondary,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: AppUtils.validatePassword,
                      ),

                      // Şifre gücü (sadece kayıt)
                      if (!_isLogin && _passwordController.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _passwordStrengthBar(),
                        ),

                      // Beni hatırla + şifremi unuttum
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (_isLogin)
                            Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) =>
                                        setState(() => _rememberMe = v ?? true),
                                    activeColor: AppTheme.primary,
                                    side: const BorderSide(
                                        color: AppTheme.textSecondary),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text('Beni hatırla',
                                    style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12)),
                              ],
                            )
                          else
                            const SizedBox.shrink(),
                          if (_isLogin)
                            TextButton(
                              onPressed: _forgotPassword,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Şifremi unuttum',
                                style: TextStyle(
                                    color: AppTheme.primary, fontSize: 12),
                              ),
                            ),
                        ],
                      ),

                      // Hata mesajı
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.redAccent.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.redAccent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                      color: Colors.redAccent, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Ana buton
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Text(
                                  _isLogin ? 'Giriş Yap' : 'Hesap Oluştur',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // "veya" ayırıcı
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppTheme.inputBorder)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('veya',
                          style: TextStyle(
                              color: AppTheme.textSecondary.withOpacity(0.7),
                              fontSize: 12)),
                    ),
                    const Expanded(child: Divider(color: AppTheme.inputBorder)),
                  ],
                ),

                const SizedBox(height: 20),

                // SOSYAL BUTONLAR — Orijinal logolarla
                Row(
                  children: [
                    Expanded(
                      child: _socialButton(
                        onTap: _isLoading || _googleLoading
                            ? null
                            : _signInWithGoogle,
                        assetPath: 'assets/google.png',
                        label: 'Google',
                        loading: _googleLoading,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _socialButton(
                        onTap: _isLoading || _githubLoading
                            ? null
                            : _signInWithGithub,
                        assetPath: 'assets/github.png',
                        label: 'GitHub',
                        loading: _githubLoading,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Alt yazı
                Text.rich(
                  TextSpan(
                    text: 'Devam ederek ',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11),
                    children: [
                      TextSpan(
                        text: 'Kullanım Şartları',
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: ' ve '),
                      TextSpan(
                        text: 'Gizlilik Politikası',
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: '\'nı kabul etmiş olursun.'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabButton(String text, bool isLoginTab) {
    final isSelected = isLoginTab ? _isLogin : !_isLogin;
    return GestureDetector(
      onTap: () {
        setState(() {
          _isLogin = isLoginTab;
          _error = null;
          _tabController.index = isLoginTab ? 0 : 1;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _usernameField() {
    return TextFormField(
      controller: _usernameController,
      style: const TextStyle(color: AppTheme.textPrimary),
      onChanged: (v) {
        if (v.trim().length >= 3) {
          _checkUsername(v);
        }
      },
      decoration: InputDecoration(
        hintText: 'Kullanıcı adı',
        prefixIcon: const Icon(Icons.person_outline,
            color: AppTheme.textSecondary),
        suffixIcon: _checkingUsername
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primary),
                ),
              )
            : _usernameController.text.trim().length >= 3
                ? Icon(
                    _usernameAvailable
                        ? Icons.check_circle
                        : Icons.cancel,
                    color: _usernameAvailable
                        ? AppTheme.online
                        : Colors.redAccent,
                    size: 20,
                  )
                : null,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Kullanıcı adı boş olamaz';
        if (v.trim().length < 3) return 'En az 3 karakter olmalı';
        if (!_usernameAvailable) return _usernameError;
        return null;
      },
    );
  }

  Widget _passwordStrengthBar() {
    Color color;
    if (_passwordStrength < 0.4) {
      color = Colors.redAccent;
    } else if (_passwordStrength < 0.7) {
      color = Colors.orange;
    } else {
      color = AppTheme.online;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _passwordStrength,
            minHeight: 4,
            backgroundColor: AppTheme.inputBorder,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              'Şifre gücü: $_passwordStrengthLabel',
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _socialButton({
    required VoidCallback? onTap,
    required String assetPath,
    required String label,
    required bool loading,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.inputBorder),
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primary),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    assetPath,
                    width: 22, height: 22,
                    errorBuilder: (_, __, ___) => Icon(
                      label == 'Google' ? Icons.g_mobiledata : Icons.code,
                      color: AppTheme.textPrimary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
