import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppUtils {
  // Not: main.dart'ta 'initializeDateFormatting('tr_TR', null)' çağrılmalı.
  // Aksi halde DateFormat('...', 'tr_TR') hata verir.

  /// Sohbet listesindeki son mesaj saati için akıllı formatlama.
  /// Bugün ise -> 14:30
  /// Dün ise -> Dün
  /// Bu hafta içindeyse -> Pazartesi, Salı vb.
  /// Daha eskiyse -> 12.05.2024
  static String formatChatListTime(DateTime date) {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final messageDate = DateTime(date.year, date.month, date.day);

      if (messageDate == today) {
        return DateFormat('HH:mm').format(date);
      } else if (messageDate == yesterday) {
        return 'Dün';
      } else if (now.difference(date).inDays < 7) {
        return DateFormat('EEEE', 'tr_TR').format(date);
      } else {
        return DateFormat('dd.MM.yyyy').format(date);
      }
    } catch (e) {
      // Locale yüklenmediyse güvenli fallback
      return DateFormat('dd.MM.yyyy').format(date);
    }
  }

  /// Mesaj odasındaki mesajların altındaki saat formatı.
  static String formatMessageTime(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  /// Mesaj odasında gün ayırıcıları için.
  static String formatDateSeparator(DateTime date) {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final messageDate = DateTime(date.year, date.month, date.day);

      if (messageDate == today) {
        return 'Bugün';
      } else if (messageDate == yesterday) {
        return 'Dün';
      } else {
        return DateFormat('d MMMM yyyy', 'tr_TR').format(date);
      }
    } catch (e) {
      return DateFormat('dd.MM.yyyy').format(date);
    }
  }

  /// Son görülme (Last Seen) formatlaması.
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
  /// Null safety eklendi.
  static String truncateMessage(String? text, {int maxLength = 40}) {
    if (text == null || text.isEmpty) return '';
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// Klavye yüksekliği
  static double getKeyboardHeight(BuildContext context) {
    return MediaQuery.of(context).viewInsets.bottom;
  }

  /// Şifre validasyonu
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Şifre boş bırakılamaz';
    }
    if (value.length < 6) {
      return 'Şifre en az 6 karakter olmalıdır';
    }
    return null;
  }

  /// E-posta validasyonu
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
