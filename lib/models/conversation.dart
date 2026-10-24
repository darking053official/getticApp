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
    // Null safety: profiles null olabilir, bunu güvenli şekilde ele alıyoruz.
    final rawMembers = json['conversation_members'] as List? ?? [];
    
    final List<Profile> memberList = rawMembers
        .where((e) => e['profiles'] != null) // Profili olmayanları filtrele
        .map((e) => Profile.fromJson(e['profiles']))
        .toList();

    // Son mesaj bilgisi varsa parse et
    String? lastMsg;
    DateTime? lastMsgTime;
    
    if (json['messages'] != null && json['messages'] is List && (json['messages'] as List).isNotEmpty) {
      final lastMessageData = (json['messages'] as List).first;
      if (lastMessageData != null) {
        lastMsg = lastMessageData['content'] as String?;
        if (lastMessageData['created_at'] != null) {
          lastMsgTime = DateTime.tryParse(lastMessageData['created_at']);
        }
      }
    }

    return Conversation(
      id: json['id']?.toString() ?? '',
      type: json['type'] as String? ?? 'direct',
      name: json['name'] as String?,
      members: memberList,
      updatedAt: json['updated_at'] != null 
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      lastMessage: lastMsg ?? json['last_message'] as String?,
      lastMessageTime: lastMsgTime,
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }

  // Karşı tarafı bulma (Birebir sohbetler için)
  Profile getOtherMember(String myId) {
    if (type == 'group') {
      // Gruplar için sahte bir Profile oluşturuluyor.
      // DİKKAT: Profile sınıfınızda zorunlu alanlar varsa bu satır hata verebilir.
      // Bu yüzden Profile.fromJson içinde varsayılan değerler tanımlı olmalı.
      return Profile(
        id: id, 
        username: name ?? 'Grup',
        avatarUrl: null,
        status: null,
        showOnlineStatus: true,
        showLastSeen: true,
      );
    }
    try {
      return members.firstWhere((m) => m.id != myId);
    } catch (e) {
      return Profile(
        id: 'unknown',
        username: 'Bilinmeyen Kullanıcı',
        avatarUrl: null,
        status: null,
        showOnlineStatus: true,
        showLastSeen: true,
      );
    }
  }

  // Sohbetin başlığını getirir (Grup adı veya karşı tarafın adı)
  String getTitle(String myId) {
    if (type == 'group') return name ?? 'Grup';
    return getOtherMember(myId).username;
  }
}
