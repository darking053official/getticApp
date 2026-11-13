import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_settings.dart';
import 'core/app_state.dart';
import 'core/constants.dart';
import 'core/security.dart';
import 'core/theme.dart';
import 'pages/apps.dart';
import 'pages/auth_page.dart';

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

  // Kayıtlı ayarları (tema vb.) runApp'ten önce yükle, açılışta tema titremesin
  await AppSettings.instance.ensureLoaded();

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

  // Bildirim izni iste
  OneSignal.Notifications.requestPermission(true);

  // Kullanıcı oturum açtıysa OneSignal'a tanıt
  final currentUser = Supabase.instance.client.auth.currentUser;
  if (currentUser != null) {
    OneSignal.login(currentUser.id);
    AppState().setCurrentUserId(currentUser.id);
  }

  // Uygulama hayat döngüsünü dinle
  WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

  // OneSignal ön plan bildirim dinleyicisi
  // Kullanıcı zaten o sohbetteyse bildirimi gösterme
  OneSignal.Notifications.addForegroundWillDisplayListener((event) {
    final additionalData = event.notification.additionalData;
    final conversationId = additionalData?['conversation_id'] as String?;

    if (conversationId != null &&
        !AppState().shouldShowNotification(conversationId)) {
      event.preventDefault();
      debugPrint('Bildirim engellendi (aktif sohbet): $conversationId');
    }
  });

  runApp(const ProviderScope(child: GetticApp()));
}

// ==========================================
// UYGULAMA KÖKÜ (tema ayarlara bağlı)
// ==========================================
class GetticApp extends StatelessWidget {
  const GetticApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;

    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: s.useSystemTheme
              ? ThemeMode.system
              : AppTheme.themeModeFrom(s.themeMode),
          home: const AuthWrapper(),
        );
      },
    );
  }
}

// ==========================================
// UYGULAMA HAYAT DÖNGÜSÜ
// ==========================================
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      AppState().setAppInForeground(true);
      debugPrint('AppState: Uygulama ön planda');
    } else if (state == AppLifecycleState.paused) {
      AppState().setAppInForeground(false);
      debugPrint('AppState: Uygulama arka planda');
    }
  }
}

// ==========================================
// AUTH WRAPPER
// ==========================================
class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  bool _showSplash = true;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();

    // Kısa splash, sonra oturum durumuna göre yönlendir
    _splashTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showSplash = false);
    });

    // Oturum değişince OneSignal, AppState ve kasa güncellenir
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final userId = data.session?.user.id;

      if (event == AuthChangeEvent.signedIn && userId != null) {
        OneSignal.login(userId);
        AppState().setCurrentUserId(userId);
        debugPrint('OneSignal login: $userId');
      } else if (event == AuthChangeEvent.signedOut) {
        OneSignal.logout();
        AppState().reset();
        // Çıkışta parola kasasını kilitle: kayıtlar bellekte kalmasın
        SecureVault.instance.lock();
        debugPrint('OneSignal logout');
      }
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authStateAsync = ref.watch(authStateProvider);

    if (_showSplash) {
      return const SplashScreen();
    }

    return authStateAsync.when(
      loading: () => const SplashScreen(),
      error: (_, __) => Scaffold(
        body: Center(
          child: Text(
            'Bağlantı hatası',
            style: TextStyle(color: context.appColors.textPrimary),
          ),
        ),
      ),
      data: (authState) {
        // Oturum yoksa giriş, varsa uygulama seçim ekranı
        return authState.session == null
            ? const AuthPage()
            : const AppsPage();
      },
    );
  }
}

// ==========================================
// SPLASH SCREEN
// ==========================================
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
              width: 100,
              height: 100,
              errorBuilder: (_, __, ___) => Icon(
                Icons.message_rounded,
                size: 100,
                color: c.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Gettic',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Yükleniyor...',
              style: TextStyle(color: c.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 48),
            CircularProgressIndicator(color: c.primary),
          ],
        ),
      ),
    );
  }
}
