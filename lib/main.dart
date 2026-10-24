import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'pages/auth_page.dart';
import 'pages/chat_list_page.dart';

// Supabase AuthState'ini global olarak dinleyen Riverpod Provider.
// Bu provider, uygulamanın her yerinden oturum durumuna erişmemizi sağlar.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

void main() async {
  // Flutter motorunu başlat
  WidgetsFlutterBinding.ensureInitialized();
  
  // Türkçe tarih formatlaması için lokalizasyonu başlat
  // (AppUtils içindeki DateFormat('...', 'tr_TR') fonksiyonları için gerekli)
  await initializeDateFormatting('tr_TR', null);

  // Supabase bağlantısını başlat
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  // Uygulamayı ProviderScope ile sarmalayarak Riverpod'u aktif et
  runApp(const ProviderScope(child: GetticApp()));
}

class GetticApp extends StatelessWidget {
  const GetticApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gettic',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme, // Premium Karanlık Temamız
      home: const AuthWrapper(), // Oturum kontrolünü yapan yapı
    );
  }
}

// Kullanıcının giriş yapıp yapmadığını kontrol eden ve 
// duruma göre yönlendirme yapan yapı.
class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Riverpod üzerinden AuthState stream'ini dinliyoruz
    final authStateAsync = ref.watch(authStateProvider);

    return authStateAsync.when(
      // Yükleniyor durumunda (Splash Screen)
      loading: () => const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      ),
      
      // Hata durumu (Nadir de olsa bağlantı kopmalarında)
      error: (error, stackTrace) => Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'Bağlantı hatası oluştu.\nLütfen uygulamayı yeniden başlatın.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
            ),
          ),
        ),
      ),
      
      // Veri geldiğinde oturum kontrolü yap
      data: (authState) {
        // Supabase'de aktif bir oturum var mı?
        final session = authState.session;

        if (session == null) {
          // Oturum yoksa Giriş/Kayıt sayfasına yönlendir
          return const AuthPage();
        } else {
          // Oturum varsa Sohbet Listesine yönlendir
          return const ChatListPage();
        }
      },
    );
  }
}
