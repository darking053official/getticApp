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
  final String? lastMessageSenderId; // Son mesajı kim attı (bildirim için)
  final int unreadCount;
  
  // Grup bilgileri
  final String? groupAvatarUrl;
  final String? createdBy;
  
  // UI durumları (local state, veritabanında yok)
  final bool isPinned;
  final bool isArchived;
  final bool isMuted;
  final bool isTyping; // Karşı taraf yazıyor mu

  Conversation({
    required this.id,
    required this.type,
    this.name,
    required this.members,
    required this.updatedAt,
    this.lastMessage,
    this.lastMessageTime,
    this.lastMessageSenderId,
    this.unreadCount = 0,
    this.groupAvatarUrl,
    this.createdBy,
    this.isPinned = false,
    this.isArchived = false,
    this.isMuted = false,
    this.isTyping = false,
  });

  // Supabase'den gelen JSON verisini modele çevirir
  factory Conversation.fromJson(Map<String, dynamic> json) {
    // conversation_members içindeki profiles verisini güvenli şekilde çek
    final rawMembers = json['conversation_members'] as List? ?? [];
    final List<Profile> memberList = rawMembers
        .where((e) => e['profiles'] != null)
        .map((e) => Profile.fromJson(e['profiles']))
        .toList();

    // Son mesaj bilgisi (mesaj join'i varsa)
    String? lastMsg;
    DateTime? lastMsgTime;
    String? lastMsgSenderId;

    if (json['messages'] != null &&
        json['messages'] is List &&
        (json['messages'] as List).isNotEmpty) {
      final lastMessageData = (json['messages'] as List).first;
      if (lastMessageData != null) {
        lastMsg = lastMessageData['content'] as String?;
        if (lastMessageData['created_at'] != null) {
          lastMsgTime = DateTime.tryParse(lastMessageData['created_at'].toString());
        }
        lastMsgSenderId = lastMessageData['sender_id']?.toString();
      }
    }

    // Eğer last_message map olarak geliyorsa (getMyConversationsWithUnread'den)
    if (json['last_message'] != null && json['last_message'] is Map) {
      final lm = json['last_message'] as Map;
      lastMsg = lm['content'] as String?;
      if (lm['created_at'] != null) {
        lastMsgTime = DateTime.tryParse(lm['created_at'].toString());
      }
      lastMsgSenderId = lm['sender_id']?.toString();
    }

    return Conversation(
      id: json['id']?.toString() ?? json['conversation_id']?.toString() ?? '',
      type: json['type'] as String? ?? 'direct',
      name: json['name'] as String?,
      members: memberList,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      lastMessage: lastMsg,
      lastMessageTime: lastMsgTime,
      lastMessageSenderId: lastMsgSenderId,
      unreadCount: json['unread_count'] as int? ?? 0,
      groupAvatarUrl: json['group_avatar_url'] as String?,
      createdBy: json['created_by']?.toString(),
    );
  }

  // Conversation modelini JSON'a çevirir
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'updated_at': updatedAt.toIso8601String(),
      'unread_count': unreadCount,
      'group_avatar_url': groupAvatarUrl,
      'created_by': createdBy,
    };
  }

  // Sadece belirli alanları değiştirip yeni bir Conversation oluşturur
  Conversation copyWith({
    String? id,
    String? type,
    String? name,
    List<Profile>? members,
    DateTime? updatedAt,
    String? lastMessage,
    DateTime? lastMessageTime,
    String? lastMessageSenderId,
    int? unreadCount,
    String? groupAvatarUrl,
    String? createdBy,
    bool? isPinned,
    bool? isArchived,
    bool? isMuted,
    bool? isTyping,
  }) {
    return Conversation(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      members: members ?? this.members,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCount: unreadCount ?? this.unreadCount,
      groupAvatarUrl: groupAvatarUrl ?? this.groupAvatarUrl,
      createdBy: createdBy ?? this.createdBy,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isMuted: isMuted ?? this.isMuted,
      isTyping: isTyping ?? this.isTyping,
    );
  }

  // Grup mu?
  bool get isGroup => type == 'group';

  // Birebir sohbet mi?
  bool get isDirect => type == 'direct';

  // Karşı tarafı bulma (Birebir sohbetler için)
  Profile? getOtherMember(String myId) {
    if (isGroup) return null;
    try {
      return members.firstWhere((m) => m.id != myId);
    } catch (_) {
      return null;
    }
  }

  // Sohbetin başlığını getirir (Grup adı veya karşı tarafın adı)
  String getTitle(String myId) {
    if (isGroup) return name ?? 'Grup';
    return getOtherMember(myId)?.username ?? 'Bilinmeyen';
  }

  // Sohbetin avatar URL'ini getirir
  String? getAvatarUrl(String myId) {
    if (isGroup) return groupAvatarUrl;
    return getOtherMember(myId)?.avatarUrl;
  }

  // Sohbetteki toplam üye sayısı
  int get memberCount => members.length;
}
