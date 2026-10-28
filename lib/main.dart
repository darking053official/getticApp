import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'pages/auth_page.dart';
import 'pages/chat_list_page.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR', null);

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  final uri = Uri.base;
  final code = uri.queryParameters['code'];
  
  if (code != null && code.isNotEmpty) {
    try {
      await Supabase.instance.client.auth.exchangeCodeForSession(code);
    } catch (e) {
      debugPrint('Auth callback hatası: $e');
    }
  }

  runApp(const ProviderScope(child: GetticApp()));
}

class GetticApp extends StatelessWidget {
  const GetticApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  bool _showSplash = true;
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    // 1.5 saniyelik yapay bekleme süresi (Splash süresi)
    // Süre bitince direkt yönlendirmeyi yap.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _showSplash = false;
          // Supabase'den son oturum bilgisini oku
          _hasSession = Supabase.instance.client.auth.currentSession != null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Riverpod ile giriş/çıkış durumlarını dinle
    final authStateAsync = ref.watch(authStateProvider);

    // Eğer yapay splash süresi bitmediyse Splash ekranını göster
    if (_showSplash) {
      return const SplashScreen();
    }

    // Splash bittiyse ve yeni bir Auth durumu değişikliği olduysa
    // Stream'den gelen veriye göre yönlendir.
    return authStateAsync.when(
      loading: () => const SplashScreen(), // Stream yüklenirken splash
      error: (error, stackTrace) => Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Text(
            'Bağlantı hatası',
            style: const TextStyle(color: AppTheme.textPrimary),
          ),
        ),
      ),
      data: (authState) {
        final session = authState.session;
        if (session == null) {
          return const AuthPage();
        } else {
          return const ChatListPage();
        }
      },
    );
  }
}

// ✅ Şık bir Splash (Yükleme) Ekranı
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo (assets klasöründe olduğundan emin ol)
            Image.asset(
              'assets/logo.png',
              width: 100,
              height: 100,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.message_rounded,
                size: 100,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Gettic',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Gizlilik odaklı mesajlaşma',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
              color: AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
