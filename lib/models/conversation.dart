import 'profile.dart';

class Conversation {
  final String id;
  final String type; // 'direct' veya 'group'
  final String? name; // Sadece gruplar için
  final List<Profile> members;
  final DateTime updatedAt;
  
  // Son mesaj bilgileri (Sohbet listesinde önizleme için)
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;

  Conversation({
    required this.id,
    required this.type,
    this.name,
    required this.members,
    required this.updatedAt,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
  });

  // Supabase'den gelen JSON verisini modele çevirir
  factory Conversation.fromJson(Map<String, dynamic> json) {
    // conversation_members içindeki profiles verisini çekiyoruz
    var memberList = (json['conversation_members'] as List? ?? [])
        .map((e) => Profile.fromJson(e['profiles']))
        .toList();

    return Conversation(
      id: json['id'],
      type: json['type'] ?? 'direct',
      name: json['name'],
      members: memberList,
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : DateTime.now(),
    );
  }

  // Karşı tarafı bulma (Birebir sohbetler için)
  Profile getOtherMember(String myId) {
    if (type == 'group') {
      return Profile(id: id, username: name ?? 'Grup');
    }
    try {
      return members.firstWhere((m) => m.id != myId);
    } catch (e) {
      return Profile(id: '', username: 'Bilinmeyen Kullanıcı');
    }
  }

  // Sohbetin başlığını getirir (Grup adı veya karşı tarafın adı)
  String getTitle(String myId) {
    if (type == 'group') return name ?? 'Grup';
    return getOtherMember(myId).username;
  }
}
