class Profile {
  final String id;
  final String username;
  final String? fullName;       // Bio/Hakkımda
  final String? avatarUrl;
  final String status;          // "online", "offline", veya özel durum mesajı
  final bool showOnlineStatus;
  final bool showLastSeen;
  final DateTime? lastSeenAt;   // Son görülme zamanı (yeni)
  final DateTime? createdAt;    // Hesap oluşturma (yeni)

  Profile({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.status = 'offline',
    this.showOnlineStatus = true,
    this.showLastSeen = true,
    this.lastSeenAt,
    this.createdAt,
  });

  // Supabase'den gelen JSON'u Profile modeline çevirir
  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id']?.toString() ?? '',
      username: (json['username'] as String?) ?? 'Kullanıcı',
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      status: (json['status'] as String?)?.isNotEmpty == true
          ? json['status'] as String
          : 'offline',
      showOnlineStatus: _parseBool(json['show_online_status'], defaultValue: true),
      showLastSeen: _parseBool(json['show_last_seen'], defaultValue: true),
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  // Profile modelini JSON'a çevirir
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'status': status,
      'show_online_status': showOnlineStatus,
      'show_last_seen': showLastSeen,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }

  // Sadece belirli alanları değiştirip yeni bir Profile oluşturur
  Profile copyWith({
    String? id,
    String? username,
    String? fullName,
    String? avatarUrl,
    String? status,
    bool? showOnlineStatus,
    bool? showLastSeen,
    DateTime? lastSeenAt,
    DateTime? createdAt,
  }) {
    return Profile(
      id: id ?? this.id,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      status: status ?? this.status,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      showLastSeen: showLastSeen ?? this.showLastSeen,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Kullanıcı çevrimiçi mi?
  bool get isOnline => status == 'online';

  // Avatar yoksa baş harfi döner
  String get initial =>
      username.isNotEmpty ? username[0].toUpperCase() : '?';

  // Bool alanları güvenli şekilde parse eder (0/1, 'true'/'false' destekli)
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
