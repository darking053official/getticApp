import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../services/supabase_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  final _service = SupabaseService();
  bool _isLogin = true;
  bool _isLoading = false;
  String? _error;

  Future<void> _submit() async {
    // Klavye kapat
    FocusScope.of(context).unfocus();
    
    // Form doğrulaması (E-posta ve şifre formatı)
    if (!_formKey.currentState!.validate()) return;

    setState(() { 
      _isLoading = true; 
      _error = null; 
    });
    
    try {
      if (_isLogin) {
        await _service.signInWithEmail(
          _emailController.text.trim(), 
          _passwordController.text
        );
        // Yönlendirme main.dart'taki AuthWrapper tarafından otomatik yapılır.
      } else {
        await _service.signUpWithEmail(
          _emailController.text.trim(), 
          _passwordController.text, 
          _usernameController.text.trim()
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kayıt başarılı! Lütfen e-postanızı kontrol edin.'),
              backgroundColor: AppTheme.primary,
            ),
          );
        }
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOAuth(String provider) async {
    try {
      if (provider == 'google') {
        await _service.signInWithGoogle();
      } else if (provider == 'github') {
        await _service.signInWithGithub();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sosyal giriş başarısız: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
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
                // GETTIC LOGOSU
                Image.asset('assets/logo.png', width: 90, height: 90),
                const SizedBox(height: 12),
                const Text(
                  'Gettic', 
                  style: TextStyle(
                    fontSize: 36, 
                    fontWeight: FontWeight.bold, 
                    color: AppTheme.textPrimary,
                    letterSpacing: -1,
                  )
                ),
                const SizedBox(height: 8),
                const Text(
                  'Gizlilik odaklı mesajlaşma',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 32),
                
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.inputBorder),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Sekmeler
                        Row(
                          children: [
                            Expanded(child: _tab('Giriş Yap', _isLogin, () => setState(() { _isLogin = true; _error = null; }))),
                            const SizedBox(width: 8),
                            Expanded(child: _tab('Kayıt Ol', !_isLogin, () => setState(() { _isLogin = false; _error = null; }))),
                          ],
                        ),
                        const SizedBox(height: 24),
                        
                        // Kullanıcı Adı (Sadece Kayıt Ol'da görünür)
                        if (!_isLogin) ...[
                          TextFormField(
                            controller: _usernameController,
                            style: const TextStyle(color: AppTheme.textPrimary),
                            decoration: const InputDecoration(
                              hintText: 'Kullanıcı Adı',
                              prefixIcon: Icon(Icons.person_outline, color: AppTheme.textSecondary),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Kullanıcı adı boş bırakılamaz';
                              if (val.trim().length < 3) return 'En az 3 karakter olmalıdır';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // Email
                        TextFormField(
                          controller: _emailController, 
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: AppTheme.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined, color: AppTheme.textSecondary),
                          ),
                          validator: AppUtils.validateEmail,
                        ),
                        const SizedBox(height: 16),
                        
                        // Şifre
                        TextFormField(
                          controller: _passwordController, 
                          obscureText: true,
                          style: const TextStyle(color: AppTheme.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Şifre',
                            prefixIcon: Icon(Icons.lock_outline, color: AppTheme.textSecondary),
                          ),
                          validator: AppUtils.validatePassword,
                        ),
                        
                        // Hata Mesajı
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!, 
                                    style: const TextStyle(color: Colors.redAccent, fontSize: 13)
                                  )
                                ),
                              ],
                            ),
                          ),
                        ],
                        
                        const SizedBox(height: 24),
                        
                        // Ana Buton
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary, 
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24, height: 24,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                                  )
                                : Text(
                                    _isLogin ? 'Giriş Yap' : 'Kayıt Ol', 
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                                  ),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Ayırıcı
                        const Row(
                          children: [
                            Expanded(child: Divider(color: AppTheme.inputBorder)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text('veya', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                            ),
                            Expanded(child: Divider(color: AppTheme.inputBorder)),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // SOSYAL MEDYA BUTONLARI
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isLoading ? null : () => _handleOAuth('google'),
                                icon: const Icon(Icons.g_mobiledata, color: Colors.white, size: 30),
                                label: const Text('Google', style: TextStyle(color: Colors.white)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppTheme.inputBorder),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isLoading ? null : () => _handleOAuth('github'),
                                icon: const Icon(Icons.code, color: Colors.white),
                                label: const Text('GitHub', style: TextStyle(color: Colors.white)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppTheme.inputBorder),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(String text, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : AppTheme.inputBackground, 
          borderRadius: BorderRadius.circular(10)
        ),
        child: Center(
          child: Text(
            text, 
            style: TextStyle(
              color: active ? Colors.white : AppTheme.textSecondary, 
              fontWeight: FontWeight.w600
            )
          )
        ),
      ),
    );
  }
}
