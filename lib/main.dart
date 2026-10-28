import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'pages/auth_page.dart';
import 'pages/chat_list_page.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// ==========================================
// ONESIGNAL APP ID
// ==========================================
const String oneSignalAppId = "87e2dd8a-b811-49f7-b637-589f3a74d6fe";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Türkçe tarih formatları
  await initializeDateFormatting('tr_TR', null);

  // Supabase başlat
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  // Google Auth callback (web için)
  final uri = Uri.base;
  final code = uri.queryParameters['code'];
  if (code != null && code.isNotEmpty) {
    try {
      await Supabase.instance.client.auth.exchangeCodeForSession(code);
    } catch (e) {
      debugPrint('Auth callback hatası: $e');
    }
  }

  // OneSignal başlat
  OneSignal.initialize(oneSignalAppId);
  
  // Bildirim izni iste (Android 13+ ve iOS için)
  OneSignal.Notifications.requestPermission(true);

  // Kullanıcı oturum açtıysa OneSignal'a tanıt
  final currentUser = Supabase.instance.client.auth.currentUser;
  if (currentUser != null) {
    OneSignal.login(currentUser.id);
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

  @override
  void initState() {
    super.initState();
    
    // 1.5 saniyelik splash göster, sonra yönlendir
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showSplash = false);
    });

    // Auth state değiştiğinde OneSignal'ı güncelle
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        final userId = data.session?.user.id;
        if (userId != null) {
          OneSignal.login(userId);
        }
      } else if (event == AuthChangeEvent.signedOut) {
        OneSignal.logout();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authStateAsync = ref.watch(authStateProvider);

    if (_showSplash) {
      return const SplashScreen();
    }

    return authStateAsync.when(
      loading: () => const SplashScreen(),
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
