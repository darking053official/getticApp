import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppUtils {
  // Türkçe lokalizasyon ayarları (Uygulama başlarken initialize edilmeli)
  // main.dart içerisinde: Intl.defaultLocale = 'tr_TR'; olarak ayarlanmalı.
  
  /// Sohbet listesindeki son mesaj saati için akıllı formatlama.
  /// Bugün ise -> 14:30
  /// Dün ise -> Dün
  /// Bu hafta içindeyse -> Pazartesi, Salı vb.
  /// Daha eskiyse -> 12.05.2024
  static String formatChatListTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      // Bugün
      return DateFormat('HH:mm').format(date);
    } else if (messageDate == yesterday) {
      // Dün
      return 'Dün';
    } else if (now.difference(date).inDays < 7) {
      // Son 1 hafta içinde
      return DateFormat('EEEE', 'tr_TR').format(date); // Örn: Pazartesi
    } else {
      // Daha eski
      return DateFormat('dd.MM.yyyy').format(date);
    }
  }

  /// Mesaj odasındaki (ChatRoom) mesajların altındaki saat formatı.
  /// Örn: 14:30
  static String formatMessageTime(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  /// Mesaj odasında gün ayırıcıları için (Örn: "Bugün", "Dün", "12 Mayıs 2024")
  static String formatDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return 'Bugün';
    } else if (messageDate == yesterday) {
      return 'Dün';
    } else {
      return DateFormat('d MMMM yyyy', 'tr_TR').format(date); // Örn: 12 Mayıs 2024
    }
  }

  /// Son görülme (Last Seen) formatlaması. (Profil ve Sohbet Listesi için)
  /// Örn: "son görülme 5 dk önce", "son görülme dün", "son görülme 12.05.2024"
  static String formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'son görülme bilinmiyor';

    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'az önce görüldü';
    } else if (difference.inMinutes < 60) {
      return 'son görülme ${difference.inMinutes} dk önce';
    } else if (difference.inHours < 24) {
      return 'son görülme ${difference.inHours} saat önce';
    } else if (difference.inDays == 1) {
      return 'son görülme dün';
    } else if (difference.inDays < 7) {
      return 'son görülme ${difference.inDays} gün önce';
    } else {
      return 'son görülme ${DateFormat('dd.MM.yyyy').format(lastSeen)}';
    }
  }

  /// Sohbet listesindeki son mesaj önizlemesi için metin kısaltma.
  /// Eğer mesaj çok uzunsa sonuna "..." ekler.
  static String truncateMessage(String text, {int maxLength = 40}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// Klavye açıldığında veya ekran boyutu değiştiğinde padding hesaplamaları için
  /// yardımcı fonksiyon (Örn: BottomSheet içinde kullanılır)
  static double getKeyboardHeight(BuildContext context) {
    return MediaQuery.of(context).viewInsets.bottom;
  }

  /// Şifre güvenlik kontrolü (Auth sayfasında kullanılacak)
  /// En az 6 karakter olmalı.
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Şifre boş bırakılamaz';
    }
    if (value.length < 6) {
      return 'Şifre en az 6 karakter olmalıdır';
    }
    return null;
  }

  /// E-posta format kontrolü
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'E-posta boş bırakılamaz';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Geçerli bir e-posta adresi giriniz';
    }
    return null;
  }
}
