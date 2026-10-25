class AppConstants {
  // --- SUPABASE BAĞLANTI BİLGİLERİ ---
  static const String supabaseUrl = 'https://ayucfychcemsvzlgsdqq.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF5dWNmeWNoY2Vtc3Z6bGdzZHFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg4MDAwODksImV4cCI6MjEwNDM3NjA4OX0.XhXZjzy58cWuAhejswK_44_Y8JJKdSzPI4QCUrS8ipg';

  // --- UYGULAMA BİLGİLERİ ---
  static const String appName = 'Gettic';
  static const String appVersion = '1.0.0';
  
  // --- LİMİTLER ---
  static const int messageMaxLength = 2000;
  static const int messagesPerPage = 50;
  static const int searchMinLength = 2;
  
  // Eski kodlarla uyumluluk için alias'lar
  static const int messageFetchLimit = messagesPerPage;
  static const int userSearchLimit = 20;

  // --- TABLO İSİMLERİ ---
  static const String tableProfiles = 'profiles';
  static const String tableConversations = 'conversations';
  static const String tableConversationMembers = 'conversation_members';
  static const String tableMessages = 'messages';
  static const String tableMessageReads = 'message_reads';

  // --- STORAGE BUCKET İSİMLERİ ---
  static const String bucketAvatars = 'avatars';
  static const String bucketChatMedia = 'chat-media';

  // --- DOSYA LİMİTLERİ ---
  static const int maxAvatarSizeMB = 5;
  static const int maxMediaSizeMB = 25;
  static const List<String> allowedImageFormats = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
  static const List<String> allowedVideoFormats = ['mp4', 'mov', 'avi'];
  static const List<String> allowedDocFormats = ['pdf', 'doc', 'docx', 'txt'];
}
