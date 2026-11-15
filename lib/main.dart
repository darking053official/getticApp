// ============================================================
// lib/main.dart
// (.txt olarak verildi. Projeye eklerken adını main.dart yapın.)
//
// Ayar bağlantıları:
//  - Tema / yazı boyutu: AppSettings -> MaterialApp
//  - Otomatik kilit: uygulama arka plana gidince AppSettings.autoLockMinutes kontrol edilir
//  - Uygulama içi bildirim: AppSettings.inAppNotifications
// ============================================================

import 'dart:async';

import 'package:cryptography_flutter/cryptography_flutter.dart';
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
import 'services/cloud_vaults.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// ==========================================
// ONESIGNAL APP ID
// ==========================================
const String oneSignalAppId = "87e2dd8a-b811-49f7-b637-589f3a74d6fe";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Parola türetme işlemini yerel kripto kütüphanesine bağla (çok daha hızlı)
  FlutterCryptography.enable();

  await initializeDateFormatting('tr_TR', null);

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  // Ayarlar runApp'ten önce yüklenir: tema ve yazı boyutu titremez
  await AppSettings.instance.ensureLoaded();

  // Google Auth callback (web)
  final code = Uri.base.queryParameters['code'];
  if (code != null && code.isNotEmpty) {
    try {
      await Supabase.instance.client.auth.exchangeCodeForSession(code);
    } catch (e) {
      debugPrint('Auth callback hatası: $e');
    }
  }

  // OneSignal: açılışı geciktirmemek için beklenmez
  OneSignal.initialize(oneSignalAppId);
  unawaited(OneSignal.Notifications.requestPermission(true));

  final currentUser = Supabase.instance.client.auth.currentUser;
  if (currentUser != null) {
    OneSignal.login(currentUser.id);
    AppState().setCurrentUserId(currentUser.id);
  }

  WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

  // Uygulama açıkken bildirim: ayar kapalıysa, ya da kullanıcı zaten o sohbetteyse gösterme
  OneSignal.Notifications.addForegroundWillDisplayListener((event) {
    final conversationId =
        event.notification.additionalData?['conversation_id'] as String?;

    if (!AppSettings.instance.inAppNotifications) {
      event.preventDefault();
      return;
    }
    if (conversationId != null &&
        !AppState().shouldShowNotification(conversationId)) {
      event.preventDefault();
    }
  });

  runApp(const ProviderScope(child: GetticApp()));
}

// ==========================================
// UYGULAMA KÖKÜ
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
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(s.fontScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const AuthWrapper(),
        );
      },
    );
  }
}

// ==========================================
// UYGULAMA HAYAT DÖNGÜSÜ + OTOMATİK KİLİT
// ==========================================
class _AppLifecycleObserver extends WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      AppState().setAppInForeground(true);
      _applyAutoLock();
    } else if (state == AppLifecycleState.paused) {
      AppState().setAppInForeground(false);
      _pausedAt = DateTime.now();
    }
  }

  /// Arka planda ayarlanan süreden uzun kalındıysa kasayı kilitler.
  void _applyAutoLock() {
    final minutes = AppSettings.instance.autoLockMinutes;
    final pausedAt = _pausedAt;
    _pausedAt = null;

    if (minutes <= 0 || pausedAt == null) return;
    if (DateTime.now().difference(pausedAt) >= Duration(minutes: minutes)) {
      CloudVaults.lockAll();
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
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();

    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final userId = data.session?.user.id;

      if (event == AuthChangeEvent.signedIn && userId != null) {
        OneSignal.login(userId);
        AppState().setCurrentUserId(userId);
      } else if (event == AuthChangeEvent.signedOut) {
        OneSignal.logout();
        AppState().reset();
        CloudVaults.lockAll();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authStateAsync = ref.watch(authStateProvider);

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
      data: (authState) => authState.session == null
          ? const AuthPage()
          : const AppsPage(),
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
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.message_rounded, size: 100, color: c.primary),
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
            const SizedBox(height: 48),
            CircularProgressIndicator(color: c.primary),
          ],
        ),
      ),
    );
  }
}
