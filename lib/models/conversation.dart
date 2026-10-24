import 'profile.dart';

class Conversation {
  final String id;
  final String type;
  final String? name;
  final List<Profile> members;
  final DateTime updatedAt;
  final String? lastMessage;
  final DateTime? lastMessageTime;

  Conversation({
    required this.id,
    required this.type,
    this.name,
    required this.members,
    required this.updatedAt,
    this.lastMessage,
    this.lastMessageTime,
  });

  factory Conversation.fromJson(Map<String, dynamic> json, {String? currentUserId}) {
    var memberList = (json['conversation_members'] as List? ?? [])
        .map((e) => Profile.fromJson(e['profiles']))
        .toList();

    return Conversation(
      id: json['id'],
      type: json['type'],
      name: json['name'],
      members: memberList,
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Profile getOtherMember(String myId) {
    if (type == 'group') {
      return Profile(id: id, username: name ?? 'Grup');
    }
    try {
      return members.firstWhere((m) => m.id != myId);
    } catch (e) {
      return Profile(id: '', username: 'Bilinmeyen');
    }
  }
}
