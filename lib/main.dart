import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'pages/auth_page.dart';
import 'pages/chat_list_page.dart';

// Supabase AuthState'ini global olarak dinleyen Riverpod Provider.
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

  runApp(const ProviderScope(child: GetticApp()));
}

class GetticApp extends StatelessWidget {
  const GetticApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gettic',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Stream'i dinle (yeni giriş/çıkış olduğunda tetiklenir)
    ref.watch(authStateProvider);

    // ✅ KRİTİK DEĞİŞİKLİK: Her build'de güncel kullanıcıyı kontrol et
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null) {
      // Kullanıcı yok → Giriş sayfası
      return const AuthPage();
    } else {
      // Kullanıcı var → Sohbet listesi
      return const ChatListPage();
    }
  }
}
