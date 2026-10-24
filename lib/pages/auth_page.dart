import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
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
  final _service = SupabaseService();
  
  bool _isLogin = true;
  bool _isLoading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      if (_isLogin) {
        await _service.signIn(_emailController.text.trim(), _passwordController.text);
      } else {
        if (_usernameController.text.trim().isEmpty) {
          throw 'Kullanıcı adı boş bırakılamaz';
        }
        await _service.signUp(
          _emailController.text.trim(),
          _passwordController.text,
          _usernameController.text.trim(),
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.forum, size: 80, color: GetticTheme.accent),
                const SizedBox(height: 16),
                const Text('Gettic', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: GetticTheme.textPrimary)),
                const SizedBox(height: 32),
                
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: GetticTheme.bgSecondary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: GetticTheme.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildTab('Giriş Yap', _isLogin, () => setState(() => _isLogin = true))),
                          const SizedBox(width: 8),
                          Expanded(child: _buildTab('Kayıt Ol', !_isLogin, () => setState(() => _isLogin = false))),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      if (!_isLogin) ...[
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(hintText: 'Kullanıcı Adı'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(hintText: 'Email'),
                      ),
                      const SizedBox(height: 12),
                      
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(hintText: 'Şifre'),
                      ),
                      
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                      ],
                      
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GetticTheme.accent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isLoading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(_isLogin ? 'Giriş Yap' : 'Kayıt Ol', style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(String text, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? GetticTheme.accent : GetticTheme.bgTertiary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(text, style: TextStyle(
            color: active ? Colors.white : GetticTheme.textSecondary,
            fontWeight: FontWeight.w600,
          )),
        ),
      ),
    );
  }
}
