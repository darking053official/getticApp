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

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'],
      username: json['username'] ?? 'Kullanıcı',
      fullName: json['full_name'],
      avatarUrl: json['avatar_url'],
      status: json['status'] ?? 'offline',
      showOnlineStatus: json['show_online_status'] ?? true,
      showLastSeen: json['show_last_seen'] ?? true,
    );
  }
}
