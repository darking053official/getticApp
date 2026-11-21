// lib/models/profile.dart
// (.txt olarak verildi. Projeye eklerken adını profile.dart yapın.)
// status: çevrimiçi bilgisi (online/offline). mode: kullanıcının seçtiği durum modu.

class Profile {
  final String id;
  final String username;
  final String? fullName; // Bio/Hakkımda
  final String? avatarUrl;
  final String status; // "online" veya "offline"
  final String mode; // "active" | "idle" | "dnd"
  final bool showOnlineStatus;
  final bool showLastSeen;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;

  Profile({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.status = 'offline',
    this.mode = 'active',
    this.showOnlineStatus = true,
    this.showLastSeen = true,
    this.lastSeenAt,
    this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id']?.toString() ?? '',
      username: (json['username'] as String?) ?? 'Kullanıcı',
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      status: (json['status'] as String?)?.isNotEmpty == true
          ? json['status'] as String
          : 'offline',
      mode: (json['mode'] as String?)?.isNotEmpty == true
          ? json['mode'] as String
          : 'active',
      showOnlineStatus:
          _parseBool(json['show_online_status'], defaultValue: true),
      showLastSeen: _parseBool(json['show_last_seen'], defaultValue: true),
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'status': status,
      'mode': mode,
      'show_online_status': showOnlineStatus,
      'show_last_seen': showLastSeen,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Profile copyWith({
    String? id,
    String? username,
    String? fullName,
    String? avatarUrl,
    String? status,
    String? mode,
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
      mode: mode ?? this.mode,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      showLastSeen: showLastSeen ?? this.showLastSeen,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get isOnline => status == 'online';

  String get initial =>
      username.isNotEmpty ? username[0].toUpperCase() : '?';

  /// Durum modunun Türkçe adı.
  String get modeLabel {
    switch (mode) {
      case 'idle':
        return 'Boşta';
      case 'dnd':
        return 'Rahatsız etmeyin';
      default:
        return 'Aktif';
    }
  }

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
