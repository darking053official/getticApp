import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppUtils {
  // ==========================================
  // TARİH & ZAMAN FORMATLAMA
  // ==========================================

  /// Sohbet listesindeki son mesaj saati için akıllı formatlama.
  /// Bugün → "14:30"
  /// Dün → "Dün"
  /// Bu hafta → "Pazartesi"
  /// Daha eski → "12.05.2024"
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
    } catch (_) {
      return DateFormat('dd.MM.yyyy').format(date);
    }
  }

  /// Mesaj baloncuklarının altındaki saat formatı.
  /// Örn: "14:30"
  static String formatMessageTime(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  /// Sohbet içindeki tarih ayırıcıları.
  /// Bugün → "Bugün"
  /// Dün → "Dün"
  /// Daha eski → "12 Mayıs 2024"
  static String formatMessageDateDivider(DateTime date) {
    try {
      final now = DateTime.now();
      if (isSameDay(date, now)) return 'Bugün';
      if (isSameDay(date, now.subtract(const Duration(days: 1)))) return 'Dün';
      return DateFormat('d MMMM yyyy', 'tr_TR').format(date);
    } catch (_) {
      return DateFormat('dd.MM.yyyy').format(date);
    }
  }

  /// İki tarihin aynı gün olup olmadığını kontrol eder.
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Son görülme (Last Seen) formatlaması.
  /// Örn: "son görülme 5 dk önce"
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

  /// Kısa tarih formatı.
  /// Örn: "12.05.2024"
  static String formatShortDate(DateTime date) {
    return DateFormat('dd.MM.yyyy').format(date);
  }

  /// Uzun tarih formatı.
  /// Örn: "12 Mayıs 2024"
  static String formatLongDate(DateTime date) {
    try {
      return DateFormat('d MMMM yyyy', 'tr_TR').format(date);
    } catch (_) {
      return DateFormat('dd.MM.yyyy').format(date);
    }
  }

  // ==========================================
  // METİN İŞLEMLERİ
  // ==========================================

  /// Uzun metni kısaltır ve sonuna "..." ekler.
  /// Null-safe.
  static String truncate(String? text, {int maxLength = 40}) {
    if (text == null || text.isEmpty) return '';
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// Kullanıcı adından baş harf alır.
  /// Örn: "Ahmet" → "A"
  static String getInitial(String? name) {
    if (name == null || name.isEmpty) return '?';
    return name.trim()[0].toUpperCase();
  }

  /// Metni büyük harfe çevirir (Türkçe uyumlu).
  static String toUpperCaseTr(String text) {
    return text
        .replaceAll('i', 'İ')
        .replaceAll('ı', 'I')
        .toUpperCase();
  }

  // ==========================================
  // SAYI & DOSYA FORMATLARI
  // ==========================================

  /// Dosya boyutunu okunabilir formata çevirir.
  /// Örn: 1536000 → "1.5 MB"
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  /// Okunmamış sayısını formatlar. 99'dan büyükse "99+" döner.
  static String formatUnreadCount(int count) {
    if (count > 99) return '99+';
    return count.toString();
  }

  // ==========================================
  // KLAVYE & UI
  // ==========================================

  /// Klavye yüksekliğini döner.
  static double getKeyboardHeight(BuildContext context) {
    return MediaQuery.of(context).viewInsets.bottom;
  }

  /// Rastgele renk üretir (avatar fallback için).
  static Color generateColorFromString(String text) {
    final hash = text.hashCode;
    final random = Random(hash);
    final hue = random.nextDouble() * 360;
    return HSLColor.fromAHSL(1.0, hue, 0.6, 0.5).toColor();
  }

  // ==========================================
  // VALİDASYONLAR
  // ==========================================

  /// Şifre validasyonu (en az 6 karakter).
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Şifre boş bırakılamaz';
    }
    if (value.length < 6) {
      return 'Şifre en az 6 karakter olmalıdır';
    }
    return null;
  }

  /// E-posta validasyonu.
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

  /// Kullanıcı adı validasyonu (3-20 karakter, sadece harf/rakam/_).
  static String? validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Kullanıcı adı boş bırakılamaz';
    }
    if (value.trim().length < 3) {
      return 'Kullanıcı adı en az 3 karakter olmalıdır';
    }
    if (value.trim().length > 20) {
      return 'Kullanıcı adı en fazla 20 karakter olabilir';
    }
    final usernameRegex = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!usernameRegex.hasMatch(value.trim())) {
      return 'Sadece harf, rakam ve alt çizgi kullanabilirsiniz';
    }
    return null;
  }

  /// Mesaj validasyonu.
  static String? validateMessage(String? value, {int maxLength = 2000}) {
    if (value == null || value.trim().isEmpty) {
      return 'Mesaj boş olamaz';
    }
    if (value.length > maxLength) {
      return 'Mesaj çok uzun (max $maxLength karakter)';
    }
    return null;
  }
}
