class Profile {
  final String id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final String status;

  Profile({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.status = 'offline',
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'],
      username: json['username'] ?? 'Kullanıcı',
      fullName: json['full_name'],
      avatarUrl: json['avatar_url'],
      status: json['status'] ?? 'offline',
    );
  }
}
