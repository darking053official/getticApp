class Profile {
  final String id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final String status;
  final bool showOnlineStatus;
  final bool showLastSeen;

  Profile({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.status = 'offline',
    this.showOnlineStatus = true,
    this.showLastSeen = true,
  });

  // Supabase'den gelen JSON verisini modele çevirir
  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      // id null gelebilir veya int olabilir → güvenli dönüşüm
      id: json['id']?.toString() ?? '',
      // username null ise varsayılan göster
      username: (json['username'] as String?) ?? 'Kullanıcı',
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      // status null veya boş ise offline
      status: (json['status'] as String?)?.isNotEmpty == true 
          ? json['status'] as String 
          : 'offline',
      // Bool alanlar için tip güvenli dönüşüm
      showOnlineStatus: _parseBool(json['show_online_status'], defaultValue: true),
      showLastSeen: _parseBool(json['show_last_seen'], defaultValue: true),
    );
  }

  // Supabase'e gönderilecek Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'status': status,
      'show_online_status': showOnlineStatus,
      'show_last_seen': showLastSeen,
    };
  }

  // Sadece belirli bir alanı değiştirip yeni nesne oluşturmak için
  Profile copyWith({
    String? id,
    String? username,
    String? fullName,
    String? avatarUrl,
    String? status,
    bool? showOnlineStatus,
    bool? showLastSeen,
  }) {
    return Profile(
      id: id ?? this.id,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      status: status ?? this.status,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      showLastSeen: showLastSeen ?? this.showLastSeen,
    );
  }

  // Bool alanları güvenli şekilde parse eden yardımcı fonksiyon
  // (Supabase bazı sürümlerde 0/1, 'true'/'false' döndürebilir)
  static bool _parseBool(dynamic value, {bool defaultValue = true}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    return defaultValue;
  }
}
