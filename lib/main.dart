import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'pages/auth_page.dart';
import 'pages/chat_list_page.dart';

void main() async {
  // Flutter motorunu başlat
  WidgetsFlutterBinding.ensureInitialized();
  
  // Supabase bağlantısını başlat (Anahtarlar constants.dart'tan geliyor)
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  runApp(const GetticApp());
}

class GetticApp extends StatelessWidget {
  const GetticApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gettic',
      debugShowCheckedModeBanner: false, // Sağ üstteki DEBUG şeridini kaldırır
      theme: GetticTheme.darkTheme,      // Premium Karanlık Temamız
      home: const AuthWrapper(),         // Oturum kontrolünü yapan yapı
    );
  }
}

// Kullanıcının giriş yapıp yapmadığını kontrol eden yapı
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    
    // Supabase'de oturum durumu değiştiğinde (giriş/çıkış) ekranı yeniler
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.signedOut) {
        if (mounted) setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Eğer aktif bir oturum varsa Sohbet Listesine, yoksa Giriş sayfasına yönlendir
    final session = Supabase.instance.client.auth.currentSession;
    
    if (session == null) {
      return const AuthPage();
    } else {
      return const ChatListPage();
    }
  }
}
